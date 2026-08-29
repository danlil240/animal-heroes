import json
import os
import tempfile
import unittest
from pathlib import Path

from deploy.animal_heroes_deploy.smoke_results import (
    DeviceSnapshot,
    ParseError,
    parse_gfxinfo,
    parse_meminfo,
    parse_battery,
    parse_thermalservice,
    parse_logcat,
    parse_snapshot,
    parse_results,
    compute_metrics,
    main,
)


GFXINFO_SAMPLE = """Applications: 1
Total frames rendered: 36000
Janky frames: 720 (2.00%)
50th percentile: 8ms
90th percentile: 16ms
95th percentile: 23ms
99th percentile: 45ms
Number Missed Vsync: 10
HISTOGRAM: 5ms=80% 8ms=95%
"""

MEMINFO_SAMPLE = """Applications Memory Usage (kB):
** MEMINFO in pid 1234 [org.danlil.animalheroes] **
                   Pss  Private  Private
                Total    Dirty    Clean
  Native Heap    12345    12340      0
  Dalvik Heap     1234     1230      0
TOTAL PSS:    13579    13579      0
TOTAL RSS:    24680    13579      0
"""

BATTERY_SAMPLE = """Current Battery Service state:
  AC powered: false
  USB powered: true
  level: 85
  scale: 100
  temperature: 285
"""

THERMAL_SAMPLE = """Current temperatures from thermal sensors:
  CurrentThermalStatus: 0
  ThermalEventStatus: 0
"""

LOGCAT_CLEAN = """08-29 10:00:00.000 I/GodotApp: started
08-29 10:05:00.000 I/Session: connected
08-29 10:10:00.000 I/Gameplay: checkpoint reached
"""

LOGCAT_WITH_CRASH = LOGCAT_CLEAN + """
08-29 10:07:00.000 E/AndroidRuntime: FATAL EXCEPTION
08-29 10:07:00.000 E/AndroidRuntime: at org.danlil.animalheroes
"""

LOGCAT_WITH_RECONNECT = LOGCAT_CLEAN + """
08-29 10:06:00.000 I/Session: reconnect attempt 1
08-29 10:06:05.000 I/Session: reconnect attempt 2
"""


class ParseGfxinfoTests(unittest.TestCase):
    def test_extracts_frames_jank_and_percentiles(self) -> None:
        fields = parse_gfxinfo(GFXINFO_SAMPLE)
        self.assertEqual(fields["total_frames"], 36000)
        self.assertEqual(fields["janky_frames"], 720)
        self.assertAlmostEqual(fields["janky_percent"], 2.0)
        self.assertAlmostEqual(fields["percentile_50_ms"], 8.0)
        self.assertAlmostEqual(fields["percentile_90_ms"], 16.0)
        self.assertAlmostEqual(fields["percentile_95_ms"], 23.0)
        self.assertAlmostEqual(fields["percentile_99_ms"], 45.0)

    def test_empty_text_returns_empty(self) -> None:
        self.assertEqual(parse_gfxinfo(""), {})

    def test_missing_percentiles_omitted(self) -> None:
        fields = parse_gfxinfo("Total frames rendered: 100\n")
        self.assertEqual(fields, {"total_frames": 100})


class ParseMeminfoTests(unittest.TestCase):
    def test_extracts_total_pss(self) -> None:
        fields = parse_meminfo(MEMINFO_SAMPLE)
        self.assertEqual(fields["total_pss_kb"], 13579)

    def test_fallback_total_line(self) -> None:
        fields = parse_meminfo("  TOTAL    98765    98765      0\n")
        self.assertEqual(fields["total_pss_kb"], 98765)

    def test_empty_returns_empty(self) -> None:
        self.assertEqual(parse_meminfo(""), {})


class ParseBatteryTests(unittest.TestCase):
    def test_extracts_level(self) -> None:
        self.assertEqual(parse_battery(BATTERY_SAMPLE), {"battery_level": 85})

    def test_empty_returns_empty(self) -> None:
        self.assertEqual(parse_battery(""), {})


class ParseThermalTests(unittest.TestCase):
    def test_extracts_status(self) -> None:
        self.assertEqual(parse_thermalservice(THERMAL_SAMPLE), {"thermal_status": 0})

    def test_empty_returns_empty(self) -> None:
        self.assertEqual(parse_thermalservice(""), {})


class ParseLogcatTests(unittest.TestCase):
    def test_clean_logcat(self) -> None:
        fields = parse_logcat(LOGCAT_CLEAN)
        self.assertEqual(fields["crash_count"], 0)
        self.assertEqual(fields["reconnect_count"], 0)

    def test_crash_detection(self) -> None:
        fields = parse_logcat(LOGCAT_WITH_CRASH)
        self.assertEqual(fields["crash_count"], 1)

    def test_reconnect_detection(self) -> None:
        fields = parse_logcat(LOGCAT_WITH_RECONNECT)
        self.assertEqual(fields["reconnect_count"], 2)


class ParseSnapshotTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def _write(self, name: str, content: str) -> None:
        (self.dir / name).write_text(content, encoding="utf-8")

    def test_parses_all_files(self) -> None:
        self._write("host-before-gfxinfo.txt", GFXINFO_SAMPLE)
        self._write("host-before-meminfo.txt", MEMINFO_SAMPLE)
        self._write("host-before-battery.txt", BATTERY_SAMPLE)
        self._write("host-before-thermalservice.txt", THERMAL_SAMPLE)
        self._write("host-before-logcat.txt", LOGCAT_CLEAN)
        snap = parse_snapshot(self.dir, "host", "before")
        self.assertEqual(snap.total_frames, 36000)
        self.assertEqual(snap.total_pss_kb, 13579)
        self.assertEqual(snap.battery_level, 85)
        self.assertEqual(snap.thermal_status, 0)
        self.assertEqual(snap.crash_count, 0)
        self.assertEqual(snap.reconnect_count, 0)

    def test_missing_files_yield_none(self) -> None:
        snap = parse_snapshot(self.dir, "host", "before")
        self.assertIsNone(snap.total_frames)
        self.assertEqual(snap.crash_count, 0)


class ComputeMetricsTests(unittest.TestCase):
    def test_average_fps_from_frame_delta(self) -> None:
        before = DeviceSnapshot(total_frames=36000, battery_level=90)
        after = DeviceSnapshot(total_frames=66000, battery_level=85, thermal_status=0)
        m = compute_metrics("host", before, after, 600)
        self.assertAlmostEqual(m.average_fps, 50.0)
        self.assertEqual(m.battery_change, -5)

    def test_zero_duration_skips_fps(self) -> None:
        before = DeviceSnapshot(total_frames=100)
        after = DeviceSnapshot(total_frames=200)
        m = compute_metrics("host", before, after, 0)
        self.assertIsNone(m.average_fps)

    def test_thermal_throttling_flagged(self) -> None:
        after = DeviceSnapshot(thermal_status=4)
        m = compute_metrics("host", DeviceSnapshot(), after, 600)
        self.assertEqual(m.thermal_status, 4)
        self.assertTrue(any("throttling" in e for e in m.errors))

    def test_crash_count_delta(self) -> None:
        before = DeviceSnapshot(crash_count=0)
        after = DeviceSnapshot(crash_count=2)
        m = compute_metrics("host", before, after, 600)
        self.assertEqual(m.crash_count, 2)
        self.assertTrue(any("crash" in e for e in m.errors))

    def test_peak_pss_converted_to_mb(self) -> None:
        after = DeviceSnapshot(total_pss_kb=13579)
        m = compute_metrics("host", DeviceSnapshot(), after, 600)
        self.assertAlmostEqual(m.peak_pss_mb, 13.3, places=1)

    def test_reconnect_delta(self) -> None:
        before = DeviceSnapshot(reconnect_count=0)
        after = DeviceSnapshot(reconnect_count=3)
        m = compute_metrics("host", before, after, 600)
        self.assertEqual(m.reconnect_count, 3)


class ParseResultsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def _write_pair(self, role: str, before_frames: int, after_frames: int,
                    battery_before: int = 90, battery_after: int = 85,
                    thermal: int = 0, logcat_before: str = LOGCAT_CLEAN,
                    logcat_after: str = LOGCAT_CLEAN) -> None:
        for timing, frames, batt, log in [
            ("before", before_frames, battery_before, logcat_before),
            ("after", after_frames, battery_after, logcat_after),
        ]:
            (self.dir / f"{role}-{timing}-gfxinfo.txt").write_text(
                f"Total frames rendered: {frames}\n99th percentile: 45ms\n", encoding="utf-8")
            (self.dir / f"{role}-{timing}-meminfo.txt").write_text(
                MEMINFO_SAMPLE, encoding="utf-8")
            (self.dir / f"{role}-{timing}-battery.txt").write_text(
                f"level: {batt}\n", encoding="utf-8")
            (self.dir / f"{role}-{timing}-thermalservice.txt").write_text(
                f"CurrentThermalStatus: {thermal}\n", encoding="utf-8")
            (self.dir / f"{role}-{timing}-logcat.txt").write_text(
                log, encoding="utf-8")

    def test_full_report_both_devices(self) -> None:
        self._write_pair("host", 36000, 66000)
        self._write_pair("client", 36000, 60000, battery_after=80)
        report = parse_results(self.dir, 600)
        self.assertEqual(report["duration_seconds"], 600)
        self.assertIn("host", report["devices"])
        self.assertIn("client", report["devices"])
        self.assertAlmostEqual(report["devices"]["host"]["average_fps"], 50.0)
        self.assertAlmostEqual(report["devices"]["client"]["average_fps"], 40.0)
        self.assertEqual(report["devices"]["host"]["battery_change"], -5)
        self.assertEqual(report["devices"]["client"]["battery_change"], -10)

    def test_no_evidence_raises(self) -> None:
        with self.assertRaises(ParseError):
            parse_results(self.dir, 600)

    def test_negative_duration_raises(self) -> None:
        with self.assertRaises(ParseError):
            parse_results(self.dir, -1)


class MainTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_table_output(self) -> None:
        for role in ("host", "client"):
            for timing, frames in [("before", 100), ("after", 200)]:
                (self.dir / f"{role}-{timing}-gfxinfo.txt").write_text(
                    f"Total frames rendered: {frames}\n", encoding="utf-8")
                (self.dir / f"{role}-{timing}-battery.txt").write_text(
                    f"level: {85 if timing == 'before' else 80}\n", encoding="utf-8")
        (self.dir / "run-duration-seconds.txt").write_text("100", encoding="utf-8")
        rc = main([str(self.dir), "--format", "table"])
        self.assertEqual(rc, 0)

    def test_json_output(self) -> None:
        for role in ("host", "client"):
            for timing, frames in [("before", 100), ("after", 200)]:
                (self.dir / f"{role}-{timing}-gfxinfo.txt").write_text(
                    f"Total frames rendered: {frames}\n", encoding="utf-8")
        (self.dir / "run-duration-seconds.txt").write_text("100", encoding="utf-8")
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = main([str(self.dir), "--format", "json"])
        self.assertEqual(rc, 0)
        data = json.loads(buf.getvalue())
        self.assertIn("devices", data)

    def test_missing_dir_returns_2(self) -> None:
        rc = main(["/nonexistent/path"])
        self.assertEqual(rc, 2)

    def test_crash_returns_nonzero(self) -> None:
        for role in ("host",):
            (self.dir / f"{role}-before-gfxinfo.txt").write_text(
                "Total frames rendered: 100\n", encoding="utf-8")
            (self.dir / f"{role}-after-gfxinfo.txt").write_text(
                "Total frames rendered: 200\n", encoding="utf-8")
            (self.dir / f"{role}-before-logcat.txt").write_text(
                LOGCAT_CLEAN, encoding="utf-8")
            (self.dir / f"{role}-after-logcat.txt").write_text(
                LOGCAT_WITH_CRASH, encoding="utf-8")
        (self.dir / "run-duration-seconds.txt").write_text("100", encoding="utf-8")
        rc = main([str(self.dir), "--format", "json"])
        self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main()
