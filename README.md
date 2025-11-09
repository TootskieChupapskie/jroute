# JRoute

J-Route is a jeepney routing service based in Davao City that promotes cultural public transportation alternatives to taxis.

## Overview
- Two main user roles: Conductor and Commuter.
- Conductor page: input the route you are driving and the maximum passengers you can carry.
- Commuter page: detects the nearest route from your location and pairs it with up to three nearby routes that get you to your destination. Duplicate routes are removed.

## Development
- Project path: d:\Code\j_route\jroute
- Flutter + Google Maps + Geolocator + Lottie used in app.

## Project history
- Initial prototype was developed using .NET MAUI.
- Due to limitations encountered with MAUI (ecosystem and compatibility with Supabase and Google APIs), the project was migrated to Flutter to better support Supabase integration and Google Maps/Places APIs, and to accelerate cross-platform development.

## Current features
- Conductor and commuter pages.
- Nearest-route detection and pairing (up to 3 routes).
- Built-in list of 52 jeepney routes.
- Basic UI for route selection, fare estimation, and sakay flow.

## Current limitations
- UI needs optimization.
- Android-only testing (limited iOS testing/devices).
- Limited spatial awareness for routes (no obstacle handling).
- Route selection currently uses nearest-route heuristics and may ignore real-world constraints (homes, rivers, one-way lanes).
- Route switching mid-trip may not respect actual direction/lanes.
- Fallbacks can trigger prematurely (falls back instead of trying less-efficient routes).
- Some route data may be outdated.

## Future recommendations
- Integrate GeoJSON route files and use QGIS for better mapping and spatial analysis.
- Add spatial filtering for obstacles and directionality.
- Support multiple vehicle types (jeepney, tricycle, bus) and their stops/stations.
- Improve routing algorithm to prefer rideability (even if less efficient) before falling back.
- Improve UI/UX and add iOS testing.

## Development
- Project path: d:\Code\j_route\jroute
- Flutter + Google Maps + Geolocator + Lottie used in app.

