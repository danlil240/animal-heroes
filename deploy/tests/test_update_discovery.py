import json
import socket
import unittest

from deploy.animal_heroes_deploy.discovery import (
    DiscoveryAdvertisement,
    DiscoveryError,
    UpdateDiscoveryResponder,
)


CERT_SHA = "a" * 64


def valid_advertisement(pairing_nonce: str | None = None) -> DiscoveryAdvertisement:
    return DiscoveryAdvertisement(
        protocol_version=1,
        service_id="ah-deploy-1",
        host="192.168.1.100",
        port=8443,
        certificate_sha256=CERT_SHA,
        pairing_nonce=pairing_nonce,
    )


class DiscoveryAdvertisementTests(unittest.TestCase):
    def test_round_trip_without_nonce(self) -> None:
        ad = valid_advertisement()
        packet = ad.to_bytes()
        self.assertLessEqual(len(packet), 1024)
        decoded = DiscoveryAdvertisement.from_dict(json.loads(packet))
        self.assertEqual(decoded.host, "192.168.1.100")
        self.assertEqual(decoded.port, 8443)
        self.assertEqual(decoded.certificate_sha256, CERT_SHA)
        self.assertIsNone(decoded.pairing_nonce)

    def test_round_trip_with_nonce(self) -> None:
        ad = valid_advertisement(pairing_nonce="deadbeef")
        packet = ad.to_bytes()
        decoded = DiscoveryAdvertisement.from_dict(json.loads(packet))
        self.assertEqual(decoded.pairing_nonce, "deadbeef")

    def test_rejects_oversized(self) -> None:
        ad = DiscoveryAdvertisement(
            protocol_version=1,
            service_id="x" * 1000,
            host="192.168.1.100",
            port=8443,
            certificate_sha256=CERT_SHA,
            pairing_nonce=None,
        )
        with self.assertRaises(DiscoveryError):
            ad.to_bytes()

    def test_rejects_wrong_protocol(self) -> None:
        with self.assertRaises(DiscoveryError):
            DiscoveryAdvertisement.from_dict({
                "protocol": 99,
                "service_id": "ah-deploy-1",
                "host": "192.168.1.100",
                "port": 8443,
                "certificate_sha256": CERT_SHA,
            })

    def test_rejects_unknown_keys(self) -> None:
        with self.assertRaises(DiscoveryError):
            DiscoveryAdvertisement.from_dict({
                "protocol": 1,
                "service_id": "ah-deploy-1",
                "host": "192.168.1.100",
                "port": 8443,
                "certificate_sha256": CERT_SHA,
                "extra": True,
            })

    def test_rejects_invalid_host(self) -> None:
        with self.assertRaises(DiscoveryError):
            DiscoveryAdvertisement.from_dict({
                "protocol": 1,
                "service_id": "ah-deploy-1",
                "host": "8.8.8.8",
                "port": 8443,
                "certificate_sha256": CERT_SHA,
            })

    def test_rejects_invalid_fingerprint(self) -> None:
        with self.assertRaises(DiscoveryError):
            DiscoveryAdvertisement.from_dict({
                "protocol": 1,
                "service_id": "ah-deploy-1",
                "host": "192.168.1.100",
                "port": 8443,
                "certificate_sha256": "short",
            })


class UpdateDiscoveryResponderTests(unittest.TestCase):
    def test_start_close_round_trip(self) -> None:
        responder = UpdateDiscoveryResponder(valid_advertisement())
        host, port = responder.start(bind_address="127.0.0.1", port=0)
        self.assertGreater(port, 0)
        responder.close()

    def test_responds_to_probe(self) -> None:
        responder = UpdateDiscoveryResponder(valid_advertisement())
        host, port = responder.start(bind_address="127.0.0.1", port=0)
        try:
            probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            probe.settimeout(0.2)
            probe.sendto(b"probe", (host, port))
            data = None
            for _ in range(20):
                responder.tick()
                try:
                    data, _ = probe.recvfrom(1024)
                    break
                except socket.timeout:
                    continue
            if data is None:
                self.fail("responder did not answer probe")
            ad = DiscoveryAdvertisement.from_dict(json.loads(data))
            self.assertEqual(ad.host, "192.168.1.100")
            probe.close()
        finally:
            responder.close()
