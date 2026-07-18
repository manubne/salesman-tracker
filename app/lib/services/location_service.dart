import 'package:geolocator/geolocator.dart';

class LocationFix {
  final double lat;
  final double lng;
  final double accuracyM;
  final bool mockLocation;
  LocationFix(this.lat, this.lng, this.accuracyM, this.mockLocation);
}

class LocationService {
  /// Gets a fresh GPS fix. Retries up to [maxWaitSeconds] for accuracy <= [targetAccuracyM].
  static Future<LocationFix> getFix({
    double targetAccuracyM = 50,
    int maxWaitSeconds = 30,
  }) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied. Enable it in settings.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on GPS / location services.');
    }

    Position? best;
    final deadline = DateTime.now().add(Duration(seconds: maxWaitSeconds));
    while (DateTime.now().isBefore(deadline)) {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      if (best == null || pos.accuracy < best.accuracy) best = pos;
      if (pos.accuracy <= targetAccuracyM) break;
    }
    final p = best!;
    return LocationFix(p.latitude, p.longitude, p.accuracy, p.isMocked);
  }
}
