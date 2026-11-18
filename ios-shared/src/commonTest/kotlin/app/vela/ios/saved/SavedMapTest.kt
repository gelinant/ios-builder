package app.vela.ios.saved

import app.vela.core.model.ListPlace
import app.vela.core.model.MapShape
import app.vela.core.model.ParkedSpot
import app.vela.core.model.PlaceList
import app.vela.core.model.SavedPlace
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** SAV-MARK: the saved map's colours, zoom thresholds, shape conversion and tap selection. */
class SavedMapTest {
    private fun place(id: String, name: String = id, lat: Double = 37.7749, lng: Double = -122.4194,
                      icon: String? = null, color: Long? = null, layer: String? = null) =
        ListPlace(id = id, name = name, lat = lat, lng = lng, icon = icon, color = color, layer = layer)

    private fun list(id: String = "list:1", name: String = "Coffee", icon: String = "star.fill",
                     color: Long = 0xFFE8710AL, places: List<ListPlace> = emptyList(),
                     shapes: List<MapShape> = emptyList(), hidden: List<String> = emptyList()) =
        PlaceList(id = id, name = name, icon = icon, color = color, places = places, shapes = shapes, hiddenLayers = hidden)

    private val lineShape = MapShape(
        name = "Ferry loop", pts = listOf(37.7955, -122.3937, 37.7995, -122.3970), color = 0xFF00897BL, width = 4f)

    private val areaShape = MapShape(
        name = "Park", pts = listOf(37.7749, -122.4194, 37.7760, -122.4180, 37.7750, -122.4160),
        closed = true, color = 0xFF9334E6L, width = 5f, fill = 0x409334E6L)

    @Test fun pinSizeFollowsAndroidZoomThresholds() {
        assertEquals(0.45, SavedMap.zoomFactor(0.0))
        assertEquals(0.45, SavedMap.zoomFactor(3.0))
        assertEquals(1.0, SavedMap.zoomFactor(8.0))
        assertEquals(1.0, SavedMap.zoomFactor(20.0))
        val mid = SavedMap.zoomFactor(5.5)
        assertTrue(mid > 0.45 && mid < 1.0)
        // 1.35 x the 16.7 pt disc at full zoom, 45 % of it out at the far zoom.
        assertEquals(16.7 * 1.35, SavedMap.pinDiameter(8.0), 0.001)
        assertEquals(16.7 * 1.35 * 0.45, SavedMap.pinDiameter(3.0), 0.001)
        assertTrue(SavedMap.pinDiameter(7.0) > SavedMap.pinDiameter(5.0))
        assertFalse(SavedMap.showsNames(13.99))
        assertTrue(SavedMap.showsNames(14.0))
        assertFalse(SavedMap.showsShapeNames(11.99))
        assertTrue(SavedMap.showsShapeNames(12.0))
    }

    @Test fun pinsUseListColourAndIconAndThePlacesOwnFirst() {
        val state = SavedState(
            lists = listOf(list(places = listOf(place("a"), place("b", icon = "emoji:🍕", color = 0xFFD93025L)))),
            saved = listOf(SavedPlace(id = "q", name = "Quick", lat = 37.0, lng = -122.0, icon = "favorite")),
            parking = ParkedSpot(37.5, -122.5, 1_000L),
        )
        val pins = state.mapPins()
        assertEquals(listOf("list:list:1:a", "list:list:1:b", "saved:q", "parking"), pins.map { it.key })
        // A list's place draws its list's colour and icon...
        assertEquals(0xFFE8710A.toInt(), pins[0].color)
        assertEquals("star.fill", pins[0].icon)
        // ...unless the place carries its own, and a quick save falls back to Google blue.
        assertEquals(0xFFD93025.toInt(), pins[1].color)
        assertEquals("emoji:🍕", pins[1].icon)
        assertEquals(SavedMap.DEFAULT_COLOR, pins[2].color)
        assertEquals("favorite", pins[2].icon)
        assertEquals(SavedMap.PARKING_COLOR, pins[3].color)
        assertTrue(pins[3].parking)
        // markers() keeps the same order, which is what a tap's index means.
        assertEquals(pins.map { it.key }, state.markers().map { it.id })
    }

    @Test fun aPlaceInSeveralListsDrawsOnceInTheFirstListAndHiddenLayersDrawNothing() {
        val shared = place("coop")
        val state = SavedState(lists = listOf(
            list(id = "list:new", color = 0xFFD93025L, places = listOf(shared)),
            list(id = "list:old", color = 0xFF00897BL, places = listOf(shared, place("hid", layer = "Layer 2"),
                place("shown", layer = "Layer 1"))),
        ).map { if (it.id == "list:old") it.copy(hiddenLayers = listOf("Layer 2")) else it })
        val pins = state.mapPins()
        // The shared place draws under the first list that holds it; the hidden layer's pin does not.
        assertEquals(listOf("list:list:new:coop", "list:list:old:shown"), pins.map { it.key })
        assertEquals(0xFFD93025.toInt(), pins[0].color)
        assertEquals(0xFF00897B.toInt(), pins[1].color)
    }

    @Test fun shapesCarryAndroidColoursOpacitiesAndAreaRule() {
        val state = SavedState(lists = listOf(list(shapes = listOf(lineShape, areaShape))))
        val shapes = state.mapShapes()
        assertEquals(2, shapes.size)
        val line = shapes[0]
        assertEquals("list:1:0", line.key)
        assertFalse(line.closed)
        assertEquals("Ferry loop", line.name)
        assertEquals(0xFF00897B.toInt(), line.lineColor)
        assertEquals(1.0, line.lineOpacity, 0.001)
        assertEquals(4.0, line.width, 0.001)
        assertNull(line.fillColor)
        val area = shapes[1]
        assertTrue(area.closed)
        assertEquals(0xFF9334E6.toInt(), area.lineColor)
        assertEquals(0x409334E6.toInt(), area.fillColor)
        assertEquals(0x40 / 255.0, area.fillOpacity, 0.001)
        assertEquals(6, area.points.size)
    }

    @Test fun hiddenLayersAndShortShapesDoNotDraw() {
        val hiddenArea = areaShape.copy(layer = "Areas")
        val shortLine = lineShape.copy(pts = listOf(37.0, -122.0, 37.01, -122.01))
        val state = SavedState(lists = listOf(
            list(shapes = listOf(hiddenArea, shortLine), hidden = listOf("Areas")),
        ))
        val shapes = state.mapShapes()
        assertEquals(1, shapes.size)
        assertEquals(1, shapes[0].index)
        assertFalse(shapes[0].closed)
        // A closed shape with one point stays a line, so nothing is filled from it.
        val closedLine = MapShape(name = "open", pts = listOf(1.0, 2.0, 3.0, 4.0), closed = true)
        val line = SavedState(lists = listOf(list(shapes = listOf(closedLine)))).mapShapes().single()
        assertFalse(line.closed)
        assertNull(line.fillColor)
    }

    @Test fun lowAlphaColoursAreLiftedLikeAndroid() {
        val faint = MapShape(name = "Faint", pts = listOf(37.0, -122.0, 37.1, -122.1), color = 0x201A73E8L)
        val shape = SavedState(lists = listOf(list(shapes = listOf(faint)))).mapShapes().single()
        assertEquals(0.35, shape.lineOpacity, 0.0001)
        assertEquals(0.0, shape.fillOpacity, 0.0)
        assertEquals(0x401A73E8L, SavedMap.defaultFill(0xFF1A73E8L))
    }

    @Test fun projectionCentresTheCameraAndPointsEastAndNorth() {
        val camera = SavedMapCamera(centerLat = 37.7749, centerLng = -122.4194, zoom = 12.0, width = 390.0, height = 844.0)
        val centre = SavedMap.project(37.7749, -122.4194, camera)
        assertEquals(195.0, centre.x, 0.001)
        assertEquals(422.0, centre.y, 0.001)
        val east = SavedMap.project(37.7749, -122.41, camera)
        assertTrue(east.x > centre.x)
        assertEquals(centre.y, east.y, 0.001)
        val north = SavedMap.project(37.78, -122.4194, camera)
        assertTrue(north.y < centre.y)
        assertEquals(centre.x, north.x, 0.001)
        // One zoom level doubles the screen distance for the same ground offset.
        val near = SavedMapCamera(37.7749, -122.4194, 12.0, 390.0, 844.0)
        val far = near.copy(zoom = 13.0)
        val a = SavedMap.project(37.78, -122.4194, near).y - centre.y
        val b = SavedMap.project(37.78, -122.4194, far).y - 422.0
        assertEquals(a * 2, b, 0.001)
    }

    @Test fun nearestPicksTheClosestPinInsideTheTouchRadius() {
        val camera = SavedMapCamera(37.7749, -122.4194, 15.0, 390.0, 844.0)
        val pins = listOf(
            SavedMapPin("a", "a", null, "A", 37.7749, -122.4194, SavedMap.DEFAULT_COLOR, "bookmark", false),
            SavedMapPin("b", "b", null, "B", 37.7800, -122.4194, SavedMap.DEFAULT_COLOR, "bookmark", false),
        )
        val centre = SavedMap.project(37.7749, -122.4194, camera)
        assertEquals(0, SavedMap.nearest(pins, camera, centre.x + 4, centre.y - 3))
        assertEquals(-1, SavedMap.nearest(pins, camera, centre.x + 40, centre.y))
        val b = SavedMap.project(37.7800, -122.4194, camera)
        assertEquals(1, SavedMap.nearest(pins, camera, b.x, b.y))
        assertEquals(-1, SavedMap.nearest(emptyList(), camera, centre.x, centre.y))
    }

    @Test fun markersOfEveryListMatchThePinKeys() {
        val state = SavedState(
            lists = listOf(list(id = "list:a", places = listOf(place("x"))), list(id = "list:b", places = listOf(place("y")))),
            saved = listOf(SavedPlace(id = "z", name = "Z", lat = 1.0, lng = 2.0)))
        assertEquals(listOf("list:list:a:x", "list:list:b:y", "saved:z"), state.markers().map { it.id })
        assertFalse(state.markers().single { it.placeId == "z" }.parking)
        assertNotNull(state.markers().firstOrNull { it.id == "list:list:b:y" })
    }
}
