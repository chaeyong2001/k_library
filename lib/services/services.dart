import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

class DistanceService {
  double metersBetween(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  List<LibraryBranch> rankLibraries(
    List<LibraryBranch> source, {
    double? userLat,
    double? userLon,
  }) {
    if (userLat == null || userLon == null) return source;
    final ranked = source.map((library) {
      final lat = library.latitude;
      final lon = library.longitude;
      if (lat == null || lon == null) return library;
      return library.copyWith(
        distanceMeters: metersBetween(userLat, userLon, lat, lon),
      );
    }).toList();
    ranked.sort(
      (a, b) => (a.distanceMeters ?? double.infinity).compareTo(
        b.distanceMeters ?? double.infinity,
      ),
    );
    return ranked;
  }

  List<LibraryHolding> rankNearbyHoldings(
    List<LibraryHolding> source, {
    required String selectedRegion,
    double? userLat,
    double? userLon,
  }) {
    final available = source
        .where((e) => e.status == LoanStatus.available)
        .toList();
    var ranked = available;
    if (userLat != null && userLon != null) {
      ranked =
          available.map((h) {
            final lat = h.library.latitude;
            final lon = h.library.longitude;
            final distance = lat == null || lon == null
                ? null
                : metersBetween(userLat, userLon, lat, lon);
            return LibraryHolding(
              library: h.library.copyWith(distanceMeters: distance),
              status: h.status,
              checkedAt: h.checkedAt,
            );
          }).toList()..sort(
            (a, b) => (a.library.distanceMeters ?? double.infinity).compareTo(
              b.library.distanceMeters ?? double.infinity,
            ),
          );
    }
    final sameRegion = ranked
        .where((h) => h.library.region == selectedRegion)
        .take(5)
        .toList();
    final otherLimit = sameRegion.length >= 5 ? 0 : 2;
    final otherRegion = ranked
        .where((h) => h.library.region != selectedRegion)
        .take(otherLimit)
        .toList();
    return [...sameRegion, ...otherRegion];
  }

  String distanceLabel(LibraryBranch library) {
    final meters = library.distanceMeters;
    if (meters == null) return '거리 확인 불가';
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)}km';
  }

  double _rad(double degrees) => degrees * pi / 180;
}

class DeviceLocationService {
  Future<Position?> currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 8),
      ),
    );
  }

  Future<void> openSettings() => Geolocator.openAppSettings();
}

class ExternalLinkService {
  Future<void> openWebsite(String? url) async {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> call(String? phone) async {
    final cleaned = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: cleaned));
  }

  Future<void> directions(LibraryBranch library) async {
    final encoded = Uri.encodeComponent(library.address);
    await launchUrl(
      Uri.parse('https://map.naver.com/v5/search/$encoded'),
      mode: LaunchMode.externalApplication,
    );
  }
}
