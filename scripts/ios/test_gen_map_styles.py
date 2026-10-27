#!/usr/bin/env python3
"""Checks the generated iOS map styles (scripts/ios/gen-map-styles.py).

Run from the repository root:
    python3 scripts/ios/test_gen_map_styles.py
"""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/ios/gen-map-styles.py"
BASE = ROOT / "iosApp/Vela/Resources/liberty-roboto.json"


def load_generator():
    spec = importlib.util.spec_from_file_location("gen_map_styles", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GeneratedStylesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()
        cls.base = json.loads(BASE.read_text())
        cls.base_layers = {layer["id"] for layer in cls.base["layers"]}
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls.tmp.name)
        cls.generator.generate(cls.out)
        cls.styles = {
            look: json.loads((cls.out / f"style-{look}.json").read_text())
            for look in cls.generator.PALETTES
        }

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_all_five_looks_and_the_dark_vela_variant_exist(self):
        self.assertEqual(
            set(self.styles),
            {"vela-light", "vela-dark", "bright", "positron", "fiord", "black"})

    def test_no_style_document_is_fetched(self):
        for look, style in self.styles.items():
            for source in style["sources"].values():
                self.assertNotIn("/styles/", source.get("url", ""), f"{look} fetches a style")
                for tile in source.get("tiles", []):
                    self.assertNotIn("/styles/", tile, f"{look} fetches a style")
            self.assertIn("url", style["sources"]["openmaptiles"])
            self.assertEqual(style["sources"]["openmaptiles"]["url"],
                             "https://tiles.openfreemap.org/planet")
            self.assertNotIn("ne2_shaded", style["sources"])

    def test_house_numbers_and_exits_use_source_fields_that_exist(self):
        for look, style in self.styles.items():
            layers = {layer["id"]: layer for layer in style["layers"]}
            self.assertIn("vela-housenumber", layers, look)
            house = layers["vela-housenumber"]
            self.assertEqual(house["source-layer"], "housenumber")
            self.assertEqual(house["layout"]["text-field"], ["get", "housenumber"])
            self.assertEqual(house["minzoom"], 17.8)
            self.assertTrue(house["layout"]["text-ignore-placement"])

            self.assertIn("vela-exit-shield", layers, look)
            exit_layer = layers["vela-exit-shield"]
            self.assertEqual(exit_layer["source-layer"], "transportation_name")
            self.assertEqual(exit_layer["minzoom"], 12.5)
            self.assertIn(["==", ["get", "subclass"], "junction"], exit_layer["filter"])
            self.assertIn(["has", "ref"], exit_layer["filter"])
            self.assertEqual(exit_layer["layout"]["text-field"], ["to-string", ["get", "ref"]])

    def test_every_layer_keeps_its_base_shape_and_adds_only_the_two_missing_ones(self):
        for look, style in self.styles.items():
            ids = [layer["id"] for layer in style["layers"]]
            self.assertEqual(len(ids), len(set(ids)), f"{look} has duplicate layer ids")
            added = {"vela-housenumber", "vela-exit-shield"}
            self.assertEqual(set(ids) - self.base_layers, added)
            self.assertNotIn("natural_earth", ids)

    def test_fonts_are_the_ones_the_glyph_host_serves(self):
        for look, style in self.styles.items():
            fonts = [
                font
                for layer in style["layers"]
                for font in (layer.get("layout", {}).get("text-font") or [])
            ]
            self.assertTrue(fonts, look)
            self.assertFalse([font for font in fonts if font.startswith("Roboto")], look)

    def test_looks_are_visibly_different(self):
        backgrounds = {
            look: style["layers"][0]["paint"]["background-color"]
            for look, style in self.styles.items()
        }
        self.assertEqual(len(set(backgrounds.values())), len(backgrounds), backgrounds)

    def test_buildings_render_from_neighborhood_zoom(self):
        for look, style in self.styles.items():
            layers = {layer["id"]: layer for layer in style["layers"]}
            self.assertEqual(layers["building"]["minzoom"], 16, look)
            self.assertEqual(layers["building"]["maxzoom"], 24, look)
            self.assertEqual(layers["building-3d"]["minzoom"], 17, look)

    def test_poi_layers_keep_the_ids_and_icon_size_i1b_filters(self):
        for look, style in self.styles.items():
            layers = {layer["id"]: layer for layer in style["layers"]}
            for identifier in ("poi_r1", "poi_r7", "poi_r20", "poi_transit"):
                self.assertIn(identifier, layers, look)
                self.assertIn("icon-size", layers[identifier]["layout"], look)
            self.assertEqual(layers["poi_r1"]["layout"]["icon-size"], 0.5)
            self.assertEqual(layers["poi_transit"]["layout"]["icon-size"], 0.7)


if __name__ == "__main__":
    unittest.main()
