// The main map's renderer: MapLibre GL JS in the one WKWebView of `MLNMapView` (WebMapView.swift).
// Swift owns the style model, the camera and every annotation; this page mirrors what it is told
// and reports camera changes, touches and data requests back. It never fetches a style on its own.
(function () {
  "use strict";

  var DEM_TILES = "vela-nets://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png";
  var TERRAIN_SOURCE = "vela-terrain-dem";
  var SHAPES_SOURCE = "vela-annotation-shapes";
  var SHAPES_FILL = "vela-annotation-fill";
  var SHAPES_LINE = "vela-annotation-line";
  // Layers this page adds by itself. They are never reported to Swift as tapped features.
  var INTERNAL = {};
  INTERNAL[SHAPES_FILL] = true;
  INTERNAL[SHAPES_LINE] = true;

  var map = null;
  var seq = 0;
  // The running eased camera command, so a padding change can carry it to its end.
  var easing = null;
  var styleGen = 0;
  var terrain = { on: true, exaggeration: 1.2 };
  var shapesData = { type: "FeatureCollection", features: [] };
  var markers = {};
  var markerImages = {};
  var popup = null;
  var puck = null;
  var puckState = null;
  var pending = {};
  var requestSequence = 0;
  var lastError = 0;

  function post(payload) {
    try {
      window.webkit.messageHandlers.vela.postMessage(payload);
    } catch (error) {
      // The Swift side has gone away.
    }
  }

  function base64ToBuffer(base64) {
    var binary = atob(base64 || "");
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i += 1) { bytes[i] = binary.charCodeAt(i); }
    return bytes.buffer;
  }

  // ---- Data requests -----------------------------------------------------------------------
  // `fetch` refuses the schemes of a WKURLSchemeHandler, so every local file, PMTiles tile and
  // proxied host goes through `addProtocol` and URLSession. Swift answers with base64.

  function swiftRequest(params, abortController) {
    return new Promise(function (resolve, reject) {
      var id = "q" + (++requestSequence);
      pending[id] = { resolve: resolve, reject: reject, type: params.type };
      if (abortController && abortController.signal) {
        abortController.signal.addEventListener("abort", function () {
          if (pending[id]) {
            delete pending[id];
            post({ e: "cancel", id: id });
            reject(new Error("aborted"));
          }
        });
      }
      post({ e: "fetch", id: id, url: params.url, type: params.type || "" });
    });
  }

  ["vela-file", "vela-nets", "vela-net", "vela-pmtiles"].forEach(function (scheme) {
    maplibregl.addProtocol(scheme, swiftRequest);
  });

  function resolveRequest(id, base64) {
    var request = pending[id];
    if (!request) { return; }
    delete pending[id];
    try {
      var buffer = base64ToBuffer(base64);
      if (request.type === "json") {
        request.resolve({ data: JSON.parse(new TextDecoder().decode(buffer)) });
      } else if (request.type === "string") {
        request.resolve({ data: new TextDecoder().decode(buffer) });
      } else {
        request.resolve({ data: buffer });
      }
    } catch (error) {
      request.reject(error);
    }
  }

  function rejectRequest(id, status) {
    var request = pending[id];
    if (!request) { return; }
    delete pending[id];
    request.reject(new Error("request failed " + (status || "")));
  }

  // ---- Filters -----------------------------------------------------------------------------
  // A Swift predicate can wrap a style's own filter in "all" with an expression. GL JS refuses a
  // legacy filter inside an expression, so every filter is normalized to the expression form.

  function isExpressionFilter(filter) {
    if (filter === true || filter === false) { return true; }
    if (!Array.isArray(filter) || filter.length === 0) { return false; }
    switch (filter[0]) {
      case "has":
        return filter.length >= 2 && filter[1] !== "$id" && filter[1] !== "$type";
      case "in":
        return filter.length >= 3 && (typeof filter[1] !== "string" || Array.isArray(filter[2]));
      case "!in":
      case "!has":
      case "none":
        return false;
      case "==":
      case "!=":
      case ">":
      case ">=":
      case "<":
      case "<=":
        return filter.length !== 3 || Array.isArray(filter[1]) || Array.isArray(filter[2]);
      case "any":
      case "all":
        for (var i = 1; i < filter.length; i += 1) {
          if (!isExpressionFilter(filter[i]) && typeof filter[i] !== "boolean") { return false; }
        }
        return true;
      default:
        return true;
    }
  }

  function legacyGetter(key) {
    if (key === "$type") { return ["geometry-type"]; }
    if (key === "$id") { return ["id"]; }
    return ["get", key];
  }

  function normalizeFilter(filter) {
    if (filter === null || filter === undefined) { return filter; }
    if (!Array.isArray(filter) || filter.length === 0) { return filter; }
    var op = filter[0];
    if (op === "all" || op === "any") {
      return [op].concat(filter.slice(1).map(normalizeFilter));
    }
    if (op === "none") {
      return ["!", ["any"].concat(filter.slice(1).map(normalizeFilter))];
    }
    if (isExpressionFilter(filter)) { return filter; }
    var key = filter[1];
    switch (op) {
      case "==": case "!=": case ">": case ">=": case "<": case "<=":
        if (key === "$type" && (op === "==" || op === "!=")) {
          var types = filter[2] === "Point" ? ["Point", "MultiPoint"]
            : filter[2] === "LineString" ? ["LineString", "MultiLineString"]
            : ["Polygon", "MultiPolygon"];
          var match = ["match", ["geometry-type"], types, true, false];
          return op === "==" ? match : ["!", match];
        }
        return [op, legacyGetter(key), filter[2]];
      case "in":
      case "!in":
        var values = filter.slice(2);
        var test = values.length === 0 ? false
          : ["match", legacyGetter(key), values, true, false];
        if (key === "$type") {
          test = ["match", ["geometry-type"], values, true, false];
        }
        return op === "in" ? test : ["!", test];
      case "has":
        return ["has", key];
      case "!has":
        return ["!", ["has", key]];
      default:
        return filter;
    }
  }

  function prepareLayer(spec) {
    if (spec && spec.filter !== undefined && spec.filter !== null) {
      spec.filter = normalizeFilter(spec.filter);
    }
    return spec;
  }

  function prepareStyle(style) {
    if (style && Array.isArray(style.layers)) {
      style.layers.forEach(prepareLayer);
    }
    return style;
  }

  // ---- Style extras: terrain, sky, annotation shapes ---------------------------------------

  function isDarkStyle() {
    try {
      var layer = map.getStyle().layers.find(function (l) { return l.type === "background"; });
      var color = layer && layer.paint && layer.paint["background-color"];
      if (typeof color !== "string") { return false; }
      var parsed = maplibregl.Color.parse(color);
      if (!parsed) { return false; }
      return (0.299 * parsed.r + 0.587 * parsed.g + 0.114 * parsed.b) < 0.4;
    } catch (error) {
      return false;
    }
  }

  function skySpec(dark) {
    return dark ? {
      "sky-color": "#0b1520",
      "sky-horizon-blend": 0.6,
      "horizon-color": "#26323d",
      "horizon-fog-blend": 0.6,
      "fog-color": "#121a22",
      "fog-ground-blend": 0.35,
      "atmosphere-blend": ["interpolate", ["linear"], ["zoom"], 0, 1, 10, 1, 12, 0]
    } : {
      "sky-color": "#8cc4ef",
      "sky-horizon-blend": 0.55,
      "horizon-color": "#e4eef6",
      "horizon-fog-blend": 0.6,
      "fog-color": "#eef3f7",
      "fog-ground-blend": 0.35,
      "atmosphere-blend": ["interpolate", ["linear"], ["zoom"], 0, 1, 10, 1, 12, 0]
    };
  }

  function applyTerrain() {
    if (!map || !map.style || !map.style._loaded) { return; }
    try {
      if (terrain.on) {
        if (!map.getSource(TERRAIN_SOURCE)) {
          map.addSource(TERRAIN_SOURCE, {
            type: "raster-dem",
            tiles: [DEM_TILES],
            tileSize: 256,
            encoding: "terrarium",
            minzoom: 0,
            maxzoom: 15
          });
        }
        map.setTerrain({ source: TERRAIN_SOURCE, exaggeration: terrain.exaggeration });
      } else {
        map.setTerrain(null);
      }
    } catch (error) {
      reportError("terrain", error);
    }
    try {
      if (typeof map.setSky === "function") { map.setSky(skySpec(isDarkStyle())); }
    } catch (error) {
      reportError("sky", error);
    }
  }

  function applyShapes() {
    if (!map || !map.style || !map.style._loaded) { return; }
    try {
      var source = map.getSource(SHAPES_SOURCE);
      if (source) {
        source.setData(shapesData);
      } else {
        map.addSource(SHAPES_SOURCE, { type: "geojson", data: shapesData });
      }
      if (!map.getLayer(SHAPES_FILL)) {
        map.addLayer({
          id: SHAPES_FILL, type: "fill", source: SHAPES_SOURCE,
          filter: ["==", ["geometry-type"], "Polygon"],
          paint: {
            "fill-color": ["coalesce", ["get", "fill"], "rgba(0,122,255,0.2)"],
            "fill-opacity": ["coalesce", ["get", "alpha"], 1]
          }
        });
      }
      if (!map.getLayer(SHAPES_LINE)) {
        map.addLayer({
          id: SHAPES_LINE, type: "line", source: SHAPES_SOURCE,
          layout: { "line-cap": "round", "line-join": "round" },
          paint: {
            "line-color": ["coalesce", ["get", "stroke"], "#007aff"],
            "line-width": ["coalesce", ["get", "width"], 3],
            "line-opacity": ["coalesce", ["get", "alpha"], 1]
          }
        });
      }
    } catch (error) {
      reportError("shapes", error);
    }
  }

  function raiseShapes() {
    if (!map) { return; }
    [SHAPES_FILL, SHAPES_LINE].forEach(function (id) {
      if (map.getLayer(id)) { try { map.moveLayer(id); } catch (error) { /* gone */ } }
    });
  }

  // ---- Camera ------------------------------------------------------------------------------

  function cameraMessage(kind) {
    var center = map.getCenter();
    return {
      e: kind,
      seq: seq,
      lng: center.lng,
      lat: center.lat,
      zoom: map.getZoom(),
      bearing: map.getBearing(),
      pitch: map.getPitch()
    };
  }

  // ---- Feature snapshot --------------------------------------------------------------------
  // UIKit decides what a tap means, synchronously. Swift asks for the features as soon as a finger
  // lands, so the recognizer that fires on lift reads features that already arrived.

  function serializeFeatures(list) {
    var out = [];
    for (var i = 0; i < list.length && out.length < 150; i += 1) {
      var feature = list[i];
      var layerId = feature.layer && feature.layer.id;
      if (!layerId || INTERNAL[layerId]) { continue; }
      var geometry = null;
      try { geometry = feature.geometry; } catch (error) { geometry = null; }
      out.push({
        l: layerId,
        id: feature.id === undefined ? null : feature.id,
        p: feature.properties || {},
        g: geometry
      });
    }
    return out;
  }

  function query(x, y) {
    var result = {};
    try {
      result["0"] = serializeFeatures(map.queryRenderedFeatures([x, y]));
      [10, 22].forEach(function (half) {
        result[String(half)] = serializeFeatures(
          map.queryRenderedFeatures([[x - half, y - half], [x + half, y + half]]));
      });
    } catch (error) {
      reportError("query", error);
    }
    return result;
  }

  function snapshotMessage(kind, x, y, id) {
    var lngLat = map.unproject([x, y]);
    return {
      e: kind,
      id: id || null,
      x: x,
      y: y,
      lng: lngLat.lng,
      lat: lngLat.lat,
      f: query(x, y)
    };
  }

  // ---- Markers, callout, location puck -----------------------------------------------------

  function markerImageURL(key) {
    var base64 = markerImages[key];
    return base64 ? "data:image/png;base64," + base64 : "";
  }

  function upsertMarker(c) {
    var entry = markers[c.id];
    if (!entry) {
      var element = document.createElement("div");
      element.className = "vela-marker";
      var image = document.createElement("img");
      image.alt = "";
      element.appendChild(image);
      var marker = new maplibregl.Marker({
        element: element,
        anchor: "center",
        offset: [c.ox || 0, c.oy || 0],
        pitchAlignment: "viewport",
        rotationAlignment: "viewport"
      });
      entry = { marker: marker, element: element, image: image, key: null };
      markers[c.id] = entry;
      marker.setLngLat([c.lng, c.lat]).addTo(map);
    } else {
      entry.marker.setLngLat([c.lng, c.lat]);
      entry.marker.setOffset([c.ox || 0, c.oy || 0]);
    }
    entry.element.style.width = c.w + "px";
    entry.element.style.height = c.h + "px";
    entry.element.style.zIndex = String(c.z || 0);
    entry.element.style.display = c.hidden ? "none" : "block";
    if (entry.key !== c.key) {
      entry.key = c.key;
      entry.image.src = markerImageURL(c.key);
    }
  }

  function removeMarker(id) {
    var entry = markers[id];
    if (!entry) { return; }
    entry.marker.remove();
    delete markers[id];
  }

  function showPopup(c) {
    closePopup();
    var content = document.createElement("div");
    var title = document.createElement("div");
    title.textContent = c.title || "";
    content.appendChild(title);
    if (c.subtitle) {
      var subtitle = document.createElement("div");
      subtitle.className = "vela-callout-subtitle";
      subtitle.textContent = c.subtitle;
      content.appendChild(subtitle);
    }
    popup = new maplibregl.Popup({
      closeButton: false, closeOnClick: true, closeOnMove: false,
      className: "vela-callout", offset: [0, c.oy || 0], maxWidth: "260px"
    }).setLngLat([c.lng, c.lat]).setDOMContent(content).addTo(map);
  }

  function closePopup() {
    if (popup) {
      popup.remove();
      popup = null;
    }
  }

  function metersPerPixel(latitude, zoom) {
    return 40075016.686 * Math.cos(latitude * Math.PI / 180) / (512 * Math.pow(2, zoom));
  }

  function updatePuck() {
    if (!map) { return; }
    if (!puckState || !puckState.visible) {
      if (puck) { puck.marker.remove(); puck = null; }
      return;
    }
    if (!puck) {
      var element = document.createElement("div");
      element.className = "vela-puck";
      var halo = document.createElement("div");
      halo.className = "vela-puck-halo";
      var cone = document.createElement("div");
      cone.className = "vela-puck-cone";
      var dot = document.createElement("div");
      dot.className = "vela-puck-dot";
      element.appendChild(halo);
      element.appendChild(cone);
      element.appendChild(dot);
      var marker = new maplibregl.Marker({
        element: element, anchor: "center", rotationAlignment: "map", pitchAlignment: "viewport"
      }).setLngLat([puckState.lng, puckState.lat]).addTo(map);
      puck = { marker: marker, halo: halo, cone: cone };
    }
    puck.marker.setLngLat([puckState.lng, puckState.lat]);
    var accuracy = puckState.acc > 0 ? puckState.acc : 0;
    var radius = accuracy / metersPerPixel(puckState.lat, map.getZoom());
    var diameter = Math.max(0, Math.min(radius * 2, 4000));
    puck.halo.style.width = diameter + "px";
    puck.halo.style.height = diameter + "px";
    puck.halo.style.display = diameter > 22 ? "block" : "none";
    if (typeof puckState.heading === "number" && puckState.heading >= 0) {
      puck.cone.style.display = "block";
      puck.marker.setRotation(puckState.heading);
    } else {
      puck.cone.style.display = "none";
      puck.marker.setRotation(0);
    }
  }

  // ---- Commands ----------------------------------------------------------------------------

  function reportError(where, error) {
    var now = Date.now();
    if (now - lastError < 250) { return; }
    lastError = now;
    post({ e: "error", where: where, message: String((error && error.message) || error) });
  }

  function hasWebGL() {
    try {
      var canvas = document.createElement("canvas");
      return !!(canvas.getContext("webgl2") || canvas.getContext("webgl"));
    } catch (error) {
      return false;
    }
  }

  function createMap(c) {
    if (map) { return; }
    if (!hasWebGL()) {
      post({ e: "fatal", reason: "webgl" });
      return;
    }
    var options = c.options || {};
    try {
      map = new maplibregl.Map({
        container: "map",
        style: { version: 8, sources: {}, layers: [] },
        center: [c.lng, c.lat],
        zoom: c.zoom,
        bearing: c.bearing || 0,
        pitch: c.pitch || 0,
        minZoom: options.minZoom !== undefined ? options.minZoom : 0,
        maxZoom: options.maxZoom !== undefined ? options.maxZoom : 22,
        minPitch: options.minPitch || 0,
        maxPitch: options.maxPitch !== undefined ? options.maxPitch : 60,
        bearingSnap: options.bearingSnap !== undefined ? options.bearingSnap : 7,
        attributionControl: false,
        pitchWithRotate: true,
        dragRotate: true,
        touchPitch: true,
        refreshExpiredTiles: false,
        pixelRatio: Math.min(window.devicePixelRatio || 1, 3),
        canvasContextAttributes: { antialias: true, powerPreference: "high-performance" },
        maxTileCacheSize: 120,
        localIdeographFontFamily: "-apple-system, 'PingFang SC', 'Hiragino Sans', sans-serif"
      });
    } catch (error) {
      post({ e: "fatal", reason: "webgl", message: String(error && error.message || error) });
      return;
    }
    if (c.padding) { map.setPadding(c.padding); }
    terrain.on = c.terrain !== false;
    if (typeof c.exaggeration === "number") { terrain.exaggeration = c.exaggeration; }
    applyOptions(options);

    var movePending = false;
    map.on("move", function () {
      if (movePending) { return; }
      movePending = true;
      requestAnimationFrame(function () {
        movePending = false;
        if (map) { post(cameraMessage("move")); }
      });
    });
    map.on("moveend", function () { post(cameraMessage("moveend")); });
    map.on("zoom", function () { if (puckState) { updatePuck(); } });
    ["dragstart", "rotatestart", "pitchstart", "zoomstart"].forEach(function (name) {
      map.on(name, function (event) {
        if (event && event.originalEvent) { post({ e: "gesture", kind: name }); }
      });
    });
    map.on("style.load", function () {
      applyTerrain();
      applyShapes();
      post({ e: "styleLoaded", gen: styleGen });
    });
    map.on("error", function (event) {
      reportError((event && event.sourceId) || "map", event && event.error);
    });
    var firstFrame = false;
    map.on("render", function () {
      if (!firstFrame) {
        firstFrame = true;
        post({ e: "frame" });
      }
    });
    post({ e: "created" });
  }

  function applyOptions(o) {
    if (!map || !o) { return; }
    if (o.minZoom !== undefined) { map.setMinZoom(o.minZoom); }
    if (o.maxZoom !== undefined) { map.setMaxZoom(o.maxZoom); }
    if (o.minPitch !== undefined) { map.setMinPitch(o.minPitch); }
    if (o.maxPitch !== undefined) { map.setMaxPitch(o.maxPitch); }
    if (o.bearingSnap !== undefined) { map._bearingSnap = o.bearingSnap; }
    if (o.rotate !== undefined) {
      if (o.rotate) {
        map.dragRotate.enable();
        map.touchZoomRotate.enableRotation();
      } else {
        map.dragRotate.disable();
        map.touchZoomRotate.disableRotation();
      }
    }
    if (o.pitch !== undefined) {
      if (o.pitch) { map.touchPitch.enable(); } else { map.touchPitch.disable(); }
    }
    if (o.scroll !== undefined) {
      if (o.scroll) { map.dragPan.enable(); } else { map.dragPan.disable(); }
    }
    if (o.zoom !== undefined) {
      if (o.zoom) {
        map.scrollZoom.enable();
        map.touchZoomRotate.enable();
        map.doubleClickZoom.enable();
      } else {
        map.scrollZoom.disable();
        map.touchZoomRotate.disable();
        map.doubleClickZoom.disable();
      }
    }
  }

  var handlers = {
    init: createMap,
    res: function (c) { resolveRequest(c.id, c.b64); },
    rej: function (c) { rejectRequest(c.id, c.status); },
    style: function (c) {
      if (!map) { return; }
      styleGen = c.gen;
      closePopup();
      // Terrain is detached across the reload and set again on style.load: a projection change
      // with terrain still attached draws one frame without its depth program.
      try { if (map.getTerrain()) { map.setTerrain(null); } } catch (error) { /* no style yet */ }
      map.setStyle(prepareStyle(c.style), { diff: false });
    },
    options: function (c) { applyOptions(c.options); },
    terrain: function (c) {
      terrain.on = !!c.on;
      if (typeof c.exaggeration === "number") { terrain.exaggeration = c.exaggeration; }
      applyTerrain();
    },
    camera: function (c) {
      if (!map) { return; }
      // The interrupted animation reports its end under the old sequence, which Swift ignores.
      map.stop();
      seq = c.seq;
      var target = {};
      if (c.lng !== undefined) { target.center = [c.lng, c.lat]; }
      if (c.zoom !== undefined) { target.zoom = c.zoom; }
      if (c.bearing !== undefined) { target.bearing = c.bearing; }
      if (c.pitch !== undefined) { target.pitch = c.pitch; }
      if (c.padding) { target.padding = c.padding; }
      if (c.duration > 0) {
        target.duration = c.duration;
        target.essential = true;
        easing = { target: target, end: Date.now() + c.duration };
        map.easeTo(target);
      } else {
        easing = null;
        map.jumpTo(target);
      }
    },
    padding: function (c) {
      if (!map) { return; }
      seq = c.seq;
      // setPadding stops a running ease; finish it with the new padding instead.
      var left = easing && map.isEasing() ? easing.end - Date.now() : 0;
      if (left > 16) {
        map.easeTo(Object.assign({}, easing.target, { padding: c.padding, duration: left }));
      } else {
        map.setPadding(c.padding);
      }
    },
    stop: function () { if (map) { map.stop(); } },
    resize: function () { if (map) { map.resize(); } },
    addSource: function (c) {
      if (!map || map.getSource(c.id)) { return; }
      map.addSource(c.id, c.spec);
    },
    removeSource: function (c) {
      if (!map || !map.getSource(c.id)) { return; }
      var used = map.getStyle().layers.some(function (l) { return l.source === c.id; });
      if (!used) { map.removeSource(c.id); }
    },
    setData: function (c) {
      var source = map && map.getSource(c.id);
      if (source && typeof source.setData === "function") { source.setData(c.data); }
    },
    addLayer: function (c) {
      if (!map) { return; }
      if (map.getLayer(c.spec.id)) { map.removeLayer(c.spec.id); }
      var before = c.before && map.getLayer(c.before) ? c.before : undefined;
      map.addLayer(prepareLayer(c.spec), before);
      if (!before) { raiseShapes(); }
    },
    removeLayer: function (c) {
      if (map && map.getLayer(c.id)) { map.removeLayer(c.id); }
    },
    moveLayer: function (c) {
      if (!map || !map.getLayer(c.id)) { return; }
      var before = c.before && map.getLayer(c.before) ? c.before : undefined;
      map.moveLayer(c.id, before);
      if (!before) { raiseShapes(); }
    },
    paint: function (c) {
      if (map && map.getLayer(c.id)) { map.setPaintProperty(c.id, c.k, c.v === null ? undefined : c.v); }
    },
    layout: function (c) {
      if (map && map.getLayer(c.id)) { map.setLayoutProperty(c.id, c.k, c.v === null ? undefined : c.v); }
    },
    filter: function (c) {
      if (map && map.getLayer(c.id)) { map.setFilter(c.id, c.f === null ? null : normalizeFilter(c.f)); }
    },
    zoomRange: function (c) {
      if (map && map.getLayer(c.id)) { map.setLayerZoomRange(c.id, c.min, c.max); }
    },
    image: function (c) {
      if (!map) { return; }
      var data = new Uint8Array(base64ToBuffer(c.b64));
      var image = { width: c.w, height: c.h, data: data };
      var options = { pixelRatio: c.ratio || 1, sdf: !!c.sdf };
      if (map.hasImage(c.name)) {
        map.removeImage(c.name);
      }
      map.addImage(c.name, image, options);
    },
    removeImage: function (c) {
      if (map && map.hasImage(c.name)) { map.removeImage(c.name); }
    },
    markerImage: function (c) { markerImages[c.key] = c.b64; },
    marker: function (c) { if (map) { upsertMarker(c); } },
    markerRemove: function (c) { removeMarker(c.id); },
    popup: function (c) { if (map) { showPopup(c); } },
    popupClose: closePopup,
    user: function (c) {
      puckState = c;
      updatePuck();
    },
    shapes: function (c) {
      shapesData = c.data;
      applyShapes();
    },
    query: function (c) {
      if (!map) {
        post({ e: "queryResult", id: c.id, x: c.x, y: c.y, f: {} });
        return;
      }
      post(snapshotMessage("queryResult", c.x, c.y, c.id));
    }
  };

  window.vela = {
    // The live map, for the Web Inspector of a Debug build.
    map: function () { return map; },
    run: function (commands) {
      for (var i = 0; i < commands.length; i += 1) {
        var command = commands[i];
        var handler = handlers[command.op];
        if (!handler) { continue; }
        try {
          handler(command);
        } catch (error) {
          reportError(command.op, error);
        }
      }
    }
  };

  window.addEventListener("error", function (event) {
    reportError("script", event && event.message);
  });

  post({ e: "ready" });
})();
