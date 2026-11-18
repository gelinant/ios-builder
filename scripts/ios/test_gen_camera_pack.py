#!/usr/bin/env python3
"""Checks the generated iOS camera pack (scripts/ios/gen-camera-pack.py).

Run from the repository root:
    python3 scripts/ios/test_gen_camera_pack.py
"""

from __future__ import annotations

import gzip
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/ios/gen-camera-pack.py"


def load_generator():
    spec = importlib.util.spec_from_file_location("gen_camera_pack", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CameraPackGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()

    def generate(self, source: Path, version: str, output: Path) -> dict:
        generator = self.generator
        old = generator.SOURCE, generator.VERSION, generator.OUTPUT
        generator.SOURCE = str(source)
        generator.VERSION = str(version)
        generator.OUTPUT = str(output)
        try:
            version_file = output.with_suffix(".version.txt")
            version_file.write_text(version, encoding="utf-8")
            generator.VERSION = str(version_file)
            generator.main()
        finally:
            generator.SOURCE, generator.VERSION, generator.OUTPUT = old
        return json.loads(output.read_text(encoding="utf-8"))

    def test_direction_pairs_and_duplicate_coordinates(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            source = folder / "camera.bin"
            rows = [
                "37.500000\t-121.500000\tFlock Safety\t90",
                "37.500004\t-121.500004\tFlock Safety\t",  # rounds onto the row above
                "37.500004\t-121.500004\tFlock Safety\t270",  # fill the missing bearing
                "37.600000\t-121.600000\tFlock Safety\t",  # no bearing: keep a pair
                "37.700000\t-121.700000\tFlock Safety\t360",  # normalizes to north
                "37.800000\t-121.800000\tFlock Safety\t-90",  # normalizes to west
                "37.900000\t-121.900000\tFlock Safety\tnot-a-number",  # no guess
            ]
            with gzip.open(source, "wt", encoding="utf-8") as handle:
                handle.write("\n".join(rows) + "\n")
            pack = self.generate(source, "20260102", folder / "pack.json")

        self.assertEqual(pack["name"], "camera-pack-2026-01-02")
        self.assertEqual(pack["date"], "2026-01-02")
        self.assertEqual(pack["precisionM"], 1.1)
        self.assertEqual(pack["bearingPrecisionDeg"], 1)
        self.assertEqual(pack["oriented"], 3)
        self.assertEqual(pack["unoriented"], 2)
        self.assertEqual(pack["cameras"], [
            [37.5, -121.5, 90],
            [37.6, -121.6],
            [37.7, -121.7, 0],
            [37.8, -121.8, 270],
            [37.9, -121.9],
        ])

    def test_the_committed_pack_is_reproducible_and_carries_bearings(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            first = folder / "first.json"
            second = folder / "second.json"
            pack = self.generate(
                ROOT / "app/src/main/assets/flock_cameras.bin", "20260721", first)
            again = self.generate(
                ROOT / "app/src/main/assets/flock_cameras.bin", "20260721", second)
            self.assertEqual(first.read_bytes(), second.read_bytes(), "the output is deterministic")

        self.assertEqual(pack, again)
        self.assertEqual(len(pack["cameras"]), 127_264)
        self.assertEqual(pack["oriented"], 118_504)
        self.assertEqual(pack["unoriented"], 8_760)
        self.assertEqual(pack["oriented"] + pack["unoriented"], len(pack["cameras"]))
        self.assertFalse(pack["cameras"] == [], "the Android asset must produce a pack")
        self.assertTrue(all(len(camera) in (2, 3) for camera in pack["cameras"]))
        self.assertTrue(all(
            isinstance(camera[2], int) and 0 <= camera[2] < 360
            for camera in pack["cameras"] if len(camera) == 3), "bearings are whole degrees")
        for camera in pack["cameras"]:
            self.assertEqual(camera[0], round(camera[0], 5), "latitude keeps five decimals")
            self.assertEqual(camera[1], round(camera[1], 5), "longitude keeps five decimals")


if __name__ == "__main__":
    unittest.main()
