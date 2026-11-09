#!/usr/bin/env bash
# Simulator helpers for scripts/ios/ci-ipa.sh and the UI scenarios (docs/ios/TESTING-IOS.md).
# Source this file; every function takes the simulator UDID first. Points are fixtures only
# (San Francisco, Davis, Sacramento).

# The point of a fixture name (sf, davis, sacramento), or the argument itself when it is already
# "lat,lng".
sim_fixture_point() {
  case "$1" in
    sf) echo "37.7749,-122.4194" ;;
    davis) echo "38.5449,-121.7405" ;;
    sacramento) echo "38.5816,-121.4944" ;;
    *) echo "$1" ;;
  esac
}

# The waypoints of a fixture drive, space separated, in the order driven.
#   sf-market: Market Street from Van Ness to the Ferry Building, about 2.6 km.
#   davis-covell: West Covell Boulevard east, then south on F Street to downtown, about 3 km.
sim_route_points() {
  case "$1" in
    sf-market) echo "37.7749,-122.4194 37.7765,-122.4172 37.7793,-122.4136 37.7826,-122.4094 37.7857,-122.4054 37.7886,-122.4017 37.7915,-122.3980 37.7942,-122.3946" ;;
    davis-covell) echo "38.5610,-121.7630 38.5610,-121.7550 38.5609,-121.7470 38.5600,-121.7405 38.5530,-121.7405 38.5449,-121.7405" ;;
    *) return 1 ;;
  esac
}

# Grants location to the app and sets a fixed simulated position.
sim_location_set() {
  local udid="$1" point
  point="$(sim_fixture_point "$2")"
  xcrun simctl location "$udid" set "$point"
}

# Grants the location permission to a bundle id without the system prompt.
sim_location_grant() {
  xcrun simctl privacy "$1" grant location "$2"
}

# Replays a fixture drive: the simulated position moves along the waypoints at SPEED meters per
# second, one update every INTERVAL seconds (default 1). Returns at once; the replay runs in the
# simulator until it reaches the last point or sim_location_clear.
sim_route_start() {
  local udid="$1" route="$2" speed="${3:-15}" interval="${4:-1}" points
  points="$(sim_route_points "$route")" || { echo "unknown route $route" >&2; return 1; }
  # shellcheck disable=SC2086 # one argument per waypoint
  xcrun simctl location "$udid" start --speed="$speed" --interval="$interval" $points
}

# Stops a replay and clears the simulated position.
sim_location_clear() {
  xcrun simctl location "$1" clear
}

# Saves a screenshot of the simulator screen to FILE.
sim_shot() {
  xcrun simctl io "$1" screenshot "$2" > /dev/null
}

# Keeps the app's info and debug lines in the simulator's log store, which by default only
# persists notices and above, so sim_collect_logs finds them. Needs a booted simulator.
sim_log_persist() {
  xcrun simctl spawn "$1" log config --mode "level:debug,persist:debug" --subsystem app.vela.ios
}

# Writes the app's unified log of the last MINUTES (default 15) to DIR: app-log.txt for the whole
# process, velacore-log.txt for the app's own subsystem (Kotlin and Swift lines).
sim_collect_logs() {
  local udid="$1" dir="$2" minutes="${3:-15}"
  xcrun simctl spawn "$udid" log show --last "${minutes}m" --style compact --predicate 'process == "Vela"' 2> /dev/null \
    | tail -n 2000 > "$dir/app-log.txt" || true
  xcrun simctl spawn "$udid" log show --last "${minutes}m" --style compact --info --debug \
    --predicate 'subsystem == "app.vela.ios"' 2> /dev/null > "$dir/velacore-log.txt" || true
}

# Arms a fixture replay for NavUITests. The app logs "nav replay: start" when its drive begins and
# "nav replay: end" after End. The watcher starts the replay on the first line and restores the
# fixed San Francisco location on the second, so later scenarios are isolated. Sets SIM_ROUTE_ARM_PID.
sim_route_arm() {
  local udid="$1" route="$2" speed="${3:-15}" interval="${4:-1}"
  (
    xcrun simctl spawn "$udid" log stream --style compact --info --debug \
      --predicate 'subsystem == "app.vela.ios"' 2> /dev/null \
      | while IFS= read -r line; do
        case "$line" in
          *"nav replay: start"*)
            sim_route_start "$udid" "$route" "$speed" "$interval"
            ;;
          *"nav replay: end"*)
            sim_location_clear "$udid" || true
            sim_location_set "$udid" sf || true
            ;;
        esac
      done
  ) &
  SIM_ROUTE_ARM_PID=$!
}

# Stops the watcher and both sides of its log-stream pipeline.
sim_route_disarm() {
  local pid="$1"
  pkill -P "$pid" 2> /dev/null || true
  kill "$pid" 2> /dev/null || true
}
