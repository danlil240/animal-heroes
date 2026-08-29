import unittest
from pathlib import Path
from unittest.mock import MagicMock

from deploy.animal_heroes_deploy.devices import (
    AdbAdapter,
    DeviceProbe,
    DeviceRejected,
    PairResult,
    TransportError,
    validate_endpoint,
)
from deploy.animal_heroes_deploy.domain import DeviceRole
from deploy.animal_heroes_deploy.toolchain import Tool


def make_adb(runner_mock=None) -> AdbAdapter:
    return AdbAdapter(runner_mock or MagicMock())


class ValidateEndpointTests(unittest.TestCase):
    def test_accepts_valid(self) -> None:
        self.assertEqual(validate_endpoint("192.168.1.5:12345"), "192.168.1.5:12345")

    def test_rejects_invalid(self) -> None:
        for bad in ("not-an-endpoint", "192.168.1.5", "http://192.168.1.5:1234"):
            with self.subTest(bad=bad):
                from deploy.animal_heroes_deploy.devices import DeviceError
                with self.assertRaises(DeviceError):
                    validate_endpoint(bad)


class PairResultTests(unittest.TestCase):
    def test_parse_success(self) -> None:
        result = PairResult.parse(b"Successfully paired with 192.168.1.5:12345\n")
        self.assertTrue(result.success)

    def test_parse_failure(self) -> None:
        result = PairResult.parse(b"Failed to pair: wrong code\n")
        self.assertFalse(result.success)


class AdbAdapterTests(unittest.TestCase):
    def test_pair_passes_code_via_stdin_only(self) -> None:
        runner = MagicMock()
        runner.run.return_value = MagicMock(returncode=0, stdout=b"Successfully paired\n", stderr=b"")
        adb = AdbAdapter(runner)
        result = adb.pair("192.168.1.5:12345", b"123456")
        self.assertTrue(result.success)
        call = runner.run.call_args
        self.assertIn(b"123456", call.kwargs["stdin"])
        self.assertIn("123456", call.kwargs["secret_values"])

    def test_enroll_requires_sm_t220(self) -> None:
        runner = MagicMock()
        def run_fn(tool, args, **kwargs):
            if "getprop" in args:
                prop = args[-1]
                if prop == "ro.product.model":
                    return MagicMock(returncode=0, stdout=b"Pixel 9\n", stderr=b"")
                return MagicMock(returncode=0, stdout=b"SERIAL123\n", stderr=b"")
            return MagicMock(returncode=0, stdout=b"", stderr=b"")
        runner.run.side_effect = run_fn
        adb = AdbAdapter(runner)
        with self.assertRaises(DeviceRejected):
            adb.enroll("192.168.1.5:12345", DeviceRole.HOST)

    def test_enroll_succeeds_for_sm_t220(self) -> None:
        runner = MagicMock()
        def run_fn(tool, args, **kwargs):
            if "getprop" in args:
                prop = args[-1]
                if prop == "ro.product.model":
                    return MagicMock(returncode=0, stdout=b"SM-T220\n", stderr=b"")
                return MagicMock(returncode=0, stdout=b"R28M30ABCDEF\n", stderr=b"")
            return MagicMock(returncode=0, stdout=b"", stderr=b"")
        runner.run.side_effect = run_fn
        adb = AdbAdapter(runner)
        identity = adb.enroll("192.168.1.5:12345", DeviceRole.HOST)
        self.assertEqual(identity.hardware_id, "R28M30ABCDEF")
        self.assertEqual(identity.role, DeviceRole.HOST)

    def test_enroll_two_distinct_devices(self) -> None:
        runner = MagicMock()
        def run_fn(tool, args, **kwargs):
            if "getprop" in args:
                prop = args[-1]
                if prop == "ro.product.model":
                    return MagicMock(returncode=0, stdout=b"SM-T220\n", stderr=b"")
                return MagicMock(returncode=0, stdout=b"R28M30XYZ\n", stderr=b"")
            return MagicMock(returncode=0, stdout=b"", stderr=b"")
        runner.run.side_effect = run_fn
        adb = AdbAdapter(runner)
        host = adb.enroll("192.168.1.5:12345", DeviceRole.HOST)
        def run_fn2(tool, args, **kwargs):
            if "getprop" in args:
                prop = args[-1]
                if prop == "ro.product.model":
                    return MagicMock(returncode=0, stdout=b"SM-T220\n", stderr=b"")
                return MagicMock(returncode=0, stdout=b"R28M30ABC\n", stderr=b"")
            return MagicMock(returncode=0, stdout=b"", stderr=b"")
        runner.run.side_effect = run_fn2
        client = adb.enroll("192.168.1.6:12346", DeviceRole.CLIENT)
        self.assertNotEqual(host.hardware_id, client.hardware_id)

    def test_install_success(self) -> None:
        runner = MagicMock()
        runner.run.return_value = MagicMock(returncode=0, stdout=b"Success\n", stderr=b"")
        adb = AdbAdapter(runner)
        self.assertTrue(adb.install("192.168.1.5:12345", Path("/tmp/test.apk")))

    def test_install_transport_error(self) -> None:
        runner = MagicMock()
        runner.run.return_value = MagicMock(returncode=1, stdout=b"transport error\n", stderr=b"")
        adb = AdbAdapter(runner)
        with self.assertRaises(TransportError):
            adb.install("192.168.1.5:12345", Path("/tmp/test.apk"))

    def test_install_failure_returns_false(self) -> None:
        runner = MagicMock()
        runner.run.return_value = MagicMock(returncode=1, stdout=b"INSTALL_FAILED_VERIFICATION\n", stderr=b"")
        adb = AdbAdapter(runner)
        self.assertFalse(adb.install("192.168.1.5:12345", Path("/tmp/test.apk")))


class DeviceProbeTests(unittest.TestCase):
    def test_battery_boundary(self) -> None:
        apk_size = 100 * 1024 * 1024
        self.assertFalse(DeviceProbe(battery_pct=24, charging=False, free_data_bytes=500*1024*1024, device_binding_hash="x").ready_for(apk_size))
        self.assertTrue(DeviceProbe(battery_pct=25, charging=False, free_data_bytes=500*1024*1024, device_binding_hash="x").ready_for(apk_size))
        self.assertTrue(DeviceProbe(battery_pct=5, charging=True, free_data_bytes=500*1024*1024, device_binding_hash="x").ready_for(apk_size))

    def test_storage_boundary(self) -> None:
        apk_size = 100 * 1024 * 1024
        min_free = max(2 * apk_size, 250 * 1024 * 1024)
        self.assertFalse(DeviceProbe(battery_pct=100, charging=False, free_data_bytes=min_free - 1, device_binding_hash="x").ready_for(apk_size))
        self.assertTrue(DeviceProbe(battery_pct=100, charging=False, free_data_bytes=min_free, device_binding_hash="x").ready_for(apk_size))

    def test_large_apk_doubles_storage(self) -> None:
        apk_size = 200 * 1024 * 1024
        min_free = 2 * apk_size
        self.assertFalse(DeviceProbe(battery_pct=100, charging=False, free_data_bytes=min_free - 1, device_binding_hash="x").ready_for(apk_size))
        self.assertTrue(DeviceProbe(battery_pct=100, charging=False, free_data_bytes=min_free, device_binding_hash="x").ready_for(apk_size))
