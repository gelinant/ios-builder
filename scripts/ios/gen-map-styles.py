#!/usr/bin/env python3
"""Generate the iOS map style variants from the bundled Liberty base.

The app never fetches a style document: every look is a JSON file in
`iosApp/Vela/Resources` built here from `liberty-roboto.json`. Tiles, sprites and glyphs stay
remote for the online map (and the offline factory swaps them for local paths). The script also
adds the OpenMapTiles layers Liberty leaves out, house numbers and motorway exit numbers, using
the fields the vector source actually carries (`housenumber`, and
`transportation_name.subclass == junction` with `ref`).

Usage:
    python3 scripts/ios/gen-map-styles.py
    python3 scripts/ios/gen-map-styles.py --out /tmp/styles
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "iosApp/Vela/Resources/liberty-roboto.json"
RESOURCES = ROOT / "iosApp/Vela/Resources"

# The palettes mirror LayersPanel.kt (the Vela look from VelaMapView.applyLight/applyDark and the
# four OpenFreeMap looks from their swatches). Only the fills Liberty paints are recolored; the
# layer order, filters and zoom gates stay the base style's own.
PALETTES = {
    "vela-light": {
        "land": "#f8f7f7",
        "water": "#90daee",
        "green": "#d3f8e1",
        "pitch": "#a9eac2",
        "building": "#e8e9ed",
        "building_line": "#d6d9e6",
        "minor": "#aab9c9",
        "service": "#9bacbc",
        "major": "#8aa4c0",
        "motorway": "#8aa4c0",
        "minor_casing": "#f8f7f7",
        "major_casing": "#f8f7f7",
        "label": "#333333",
        "halo": "#ffffff",
    },
    "vela-dark": {
        "land": "#162640",
        "water": "#000d2a",
        "green": "#0d3847",
        "pitch": "#0d4956",
        "building": "#1c3b69",
        "building_line": "#2e3d6d",
        "minor": "#3d5a77",
        "service": "#2a4056",
        "major": "#476789",
        "motorway": "#476789",
        "minor_casing": "#162640",
        "major_casing": "#162640",
        "label": "#c3cad6",
        "halo": "#1a2230",
    },
    "bright": {
        "land": "#f8f4f0",
        "water": "#aecfe2",
        "green": "#d8e8c8",
        "pitch": "#cbe6b3",
        "building": "#f2eae2",
        "building_line": "#e4d8cb",
        "minor": "#ffffff",
        "service": "#f7f3ee",
        "major": "#ffeeaa",
        "motorway": "#ffdd88",
        "minor_casing": "#cfcdca",
        "major_casing": "#e9ac77",
        "label": "#3a3a3a",
        "halo": "#ffffff",
    },
    "positron": {
        "land": "#f2f3f0",
        "water": "#c2c8ca",
        "green": "#e6e9e5",
        "pitch": "#dfe6dc",
        "building": "#eaeae5",
        "building_line": "#dcdcd6",
        "minor": "#e0e0e0",
        "service": "#ececea",
        "major": "#ffffff",
        "motorway": "#ffffff",
        "minor_casing": "#d5d5d5",
        "major_casing": "#d5d5d5",
        "label": "#3a3a3a",
        "halo": "#ffffff",
    },
    "fiord": {
        "land": "#45516e",
        "water": "#38435c",
        "green": "#4a5c68",
        "pitch": "#536774",
        "building": "#2a3450",
        "building_line": "#394566",
        "minor": "#5a678c",
        "service": "#4a5575",
        "major": "#3c4357",
        "motorway": "#3c4357",
        "minor_casing": "#5a678c",
        "major_casing": "#5a678c",
        "label": "#e6e9f2",
        "halo": "#2c3550",
    },
    "black": {
        "land": "#0c0c0c",
        "water": "#1b1b1d",
        "green": "#202020",
        "pitch": "#242424",
        "building": "#0a0a0a",
        "building_line": "#1d1d1d",
        "minor": "#2a2a2a",
        "service": "#202020",
        "major": "#121212",
        "motorway": "#121212",
        "minor_casing": "#3c3c3c",
        "major_casing": "#3c3c3c",
        "label": "#e8e8e8",
        "halo": "#000000",
    },
}

# Existing OpenFreeMap sprite names, so POI labels keep their icons on every look. Liberty's
# bundled style points at Android's runtime `vela-poi-*` bitmaps, which iOS does not install.
POI_ICONS = {
    "vela-poi-food": "restaurant",
    "vela-poi-shop": "shop",
    "vela-poi-lodging": "lodging",
    "vela-poi-fuel": "fuel",
    "vela-poi-parking": "parking",
    "vela-poi-park": "park",
    "vela-poi-health": "hospital",
    "vela-poi-edu": "school",
    "vela-poi-civic": "town_hall",
    "vela-poi-culture": "museum",
    "vela-poi-sport": "stadium",
    "vela-poi-transit": "bus",
    "vela-poi-default": "circle_11",
}

HOUSE_MIN_ZOOM = 17.8
HOUSE_FADE_ZOOM = 18.4
EXIT_MIN_ZOOM = 12.5

MOTORWAY = ("road_motorway", "road_motorway_link", "bridge_motorway", "bridge_motorway_link",
            "tunnel_motorway", "tunnel_motorway_link", "road_motorway_casing",
            "road_motorway_link_casing", "bridge_motorway_casing", "bridge_motorway_link_casing",
            "tunnel_motorway_casing", "tunnel_motorway_link_casing")
MAJOR = ("road_trunk_primary", "bridge_trunk_primary", "tunnel_trunk_primary",
         "road_secondary_tertiary", "bridge_secondary_tertiary", "tunnel_secondary_tertiary",
         "road_trunk_primary_casing", "bridge_trunk_primary_casing", "tunnel_trunk_primary_casing",
         "road_secondary_tertiary_casing", "bridge_secondary_tertiary_casing",
         "tunnel_secondary_tertiary_casing")
MINOR = ("road_minor", "road_link", "bridge_street", "bridge_link", "tunnel_minor",
         "tunnel_link", "road_minor_casing", "road_link_casing", "bridge_street_casing",
         "bridge_link_casing", "tunnel_street_casing", "tunnel_link_casing")
SERVICE = ("road_service_track", "bridge_service_track", "tunnel_service_track",
           "road_service_track_casing", "bridge_service_track_casing",
           "tunnel_service_track_casing")
SHIELD_LAYERS = {"highway-shield-us-interstate", "road_shield_us", "highway-shield-non-us"}


def renamed_fonts(value):
    """Map Android's Roboto stacks to the glyphs the OpenFreeMap/Noto host serves."""
    if isinstance(value, str):
        return {
            "Roboto Regular": "Noto Sans Regular",
            "Roboto Italic": "Noto Sans Italic",
            "Roboto Medium": "Noto Sans Bold",
            "Roboto Bold": "Noto Sans Bold",
        }.get(value, value)
    if isinstance(value, list):
        return [renamed_fonts(item) for item in value]
    if isinstance(value, dict):
        return {key: renamed_fonts(item) for key, item in value.items()}
    return value


def replace_poi_icons(value):
    if isinstance(value, str):
        return POI_ICONS.get(value, value)
    if isinstance(value, list):
        return [replace_poi_icons(item) for item in value]
    if isinstance(value, dict):
        return {key: replace_poi_icons(item) for key, item in value.items()}
    return value


def set_paint(layer, **properties):
    paint = layer.setdefault("paint", {})
    paint.update(properties)


def recolor(root, palette):
    layers = root["layers"]
    for layer in layers:
        layer_id = layer["id"]
        if layer_id == "background":
            set_paint(layer, **{"background-color": palette["land"]})
        elif layer_id == "water":
            set_paint(layer, **{"fill-color": palette["water"]})
        elif layer_id in ("waterway_river", "waterway_other", "waterway_tunnel"):
            set_paint(layer, **{"line-color": palette["water"]})
        elif layer_id in ("park", "landcover_grass", "landcover_wood"):
            set_paint(layer, **{"fill-color": palette["green"], "fill-opacity": 1.0})
        elif layer_id in ("landuse_pitch", "landuse_track"):
            set_paint(layer, **{"fill-color": palette["pitch"], "fill-opacity": 1.0})
        elif layer_id == "building":
            set_paint(layer, **{"fill-color": palette["building"],
                                "fill-outline-color": palette["building_line"]})
        elif layer_id == "building-3d":
            set_paint(layer, **{"fill-extrusion-color": palette["building"]})
        elif layer_id.startswith(("landuse_", "landcover_")):
            if layer.get("type") == "fill":
                set_paint(layer, **{"fill-color": palette["land"], "fill-opacity": 0.6})
        elif layer_id in MOTORWAY:
            key = "major_casing" if layer_id.endswith("_casing") else "motorway"
            set_paint(layer, **{"line-color": palette[key]})
        elif layer_id in MAJOR:
            key = "major_casing" if layer_id.endswith("_casing") else "major"
            set_paint(layer, **{"line-color": palette[key]})
        elif layer_id in MINOR:
            key = "minor_casing" if layer_id.endswith("_casing") else "minor"
            set_paint(layer, **{"line-color": palette[key]})
        elif layer_id in SERVICE:
            key = "minor_casing" if layer_id.endswith("_casing") else "service"
            set_paint(layer, **{"line-color": palette[key]})
        elif layer.get("type") == "symbol" and layer_id not in SHIELD_LAYERS \
                and layer_id not in ("vela-housenumber", "vela-exit-shield"):
            set_paint(layer, **{"text-color": palette["label"],
                                "text-halo-color": palette["halo"]})
    return root


def house_number_layer():
    return {
        "id": "vela-housenumber",
        "type": "symbol",
        "source": "openmaptiles",
        "source-layer": "housenumber",
        "minzoom": HOUSE_MIN_ZOOM,
        "layout": {
            "text-field": ["get", "housenumber"],
            "text-font": ["Noto Sans Regular"],
            "text-size": 10,
            "text-max-width": 5,
            "text-ignore-placement": True,
        },
        "paint": {
            "text-color": "#8a8a8a",
            "text-halo-color": "#ffffff",
            "text-halo-width": 1,
            "text-opacity": ["interpolate", ["linear"], ["zoom"],
                             HOUSE_MIN_ZOOM, 0, HOUSE_FADE_ZOOM, 1],
        },
    }


def exit_layer():
    return {
        "id": "vela-exit-shield",
        "type": "symbol",
        "source": "openmaptiles",
        "source-layer": "transportation_name",
        "minzoom": EXIT_MIN_ZOOM,
        "filter": ["all",
                   ["==", ["get", "subclass"], "junction"],
                   ["has", "ref"],
                   ["<=", ["get", "ref_length"], 4]],
        "layout": {
            "icon-image": ["concat", "vela-exit_",
                           ["to-string", ["get", "ref_length"]]],
            "icon-size": 1,
            "icon-rotation-alignment": "viewport",
            "icon-pitch-alignment": "viewport",
            "icon-padding": 4,
            "symbol-placement": "point",
            "text-field": ["to-string", ["get", "ref"]],
            "text-font": ["Noto Sans Bold"],
            "text-size": 9.5,
            "text-rotation-alignment": "viewport",
            "text-pitch-alignment": "viewport",
        },
        "paint": {"text-color": "#ffffff", "text-halo-width": 0},
    }


def add_missing_layers(root):
    layers = root["layers"]
    ids = {layer["id"] for layer in layers}
    if "vela-housenumber" not in ids:
        index = next((i for i, layer in enumerate(layers)
                      if layer["id"] in ("poi_r20", "highway-name-path")), len(layers))
        layers.insert(index, house_number_layer())
    if "vela-exit-shield" not in ids:
        index = next((i for i, layer in enumerate(layers)
                      if layer["id"] == "airport"), len(layers))
        layers.insert(index, exit_layer())
    for layer in layers:
        if layer["id"] == "building":
            layer["minzoom"] = 16
            layer["maxzoom"] = 24
        elif layer["id"] == "building-3d":
            layer["minzoom"] = 17
    return root


def build_style(base, look):
    palette = PALETTES[look]
    root = json.loads(json.dumps(base))
    root["sources"].pop("ne2_shaded", None)
    root["layers"] = [layer for layer in root["layers"] if layer.get("source") != "ne2_shaded"]
    root = replace_poi_icons(root)
    root = renamed_fonts(root)
    add_missing_layers(root)
    recolor(root, palette)
    root["metadata"] = {"vela:look": look,
                        "vela:generator": "scripts/ios/gen-map-styles.py"}
    return root


def generate(out_dir: Path = RESOURCES):
    base = json.loads(BASE.read_text())
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for look in PALETTES:
        style = build_style(base, look)
        target = out_dir / f"style-{look}.json"
        target.write_text(json.dumps(style, ensure_ascii=False, separators=(",", ":")) + "\n")
        written.append(target)
    return written


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=RESOURCES,
                        help="output directory (default: iosApp/Vela/Resources)")
    args = parser.parse_args()
    for target in generate(args.out):
        print(target)


if __name__ == "__main__":
    main()
