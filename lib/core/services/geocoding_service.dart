import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Reverse geocoding service with local JSON cache.
/// GPS coordinates → city, country, state.
class GeocodingService {
  static final _dio = Dio();
  static Map<String, Map<String, String>>? _cache;
  static String? _cachePath;

  /// Resolves GPS coordinates to city/country/state.
  /// Checks local cache first, then queries Nominatim.
  static Future<({String? city, String? country, String? state})> resolve(
    double? lat,
    double? lon,
  ) async {
    if (lat == null || lon == null) {
      return (city: null, country: null, state: null);
    }

    // Round to 2 decimal places (~1.1 km precision) for cache key
    final key = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

    // Check cache
    await _ensureCacheLoaded();
    if (_cache!.containsKey(key)) {
      final cached = _cache![key]!;
      return (
        city: cached['city'],
        country: cached['country'],
        state: cached['state'],
      );
    }

    // Query Nominatim
    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lon,
          'format': 'json',
          'accept-language': 'en',
          'zoom': 10,
        },
        options: Options(
          headers: {'User-Agent': 'StockFlou/1.0 (stock photo metadata tool)'},
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>? ?? {};

        final city =
            (address['city'] ??
                    address['town'] ??
                    address['village'] ??
                    address['municipality'])
                as String?;
        final country = address['country'] as String?;
        final state = address['state'] as String?;

        // Save to cache
        _cache![key] = {
          if (city != null) 'city': city,
          if (country != null) 'country': country,
          if (state != null) 'state': state,
        };
        await _saveCache();

        return (city: city, country: country, state: state);
      }
    } catch (e) {
      debugPrint('Nominatim error: $e');
    }

    return (city: null, country: null, state: null);
  }

  static Future<void> _ensureCacheLoaded() async {
    if (_cache != null) return;

    _cachePath ??= p.join(
      (await getApplicationSupportDirectory()).path,
      'geocache.json',
    );

    final file = File(_cachePath!);
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _cache = decoded.map(
          (k, v) => MapEntry(k, Map<String, String>.from(v as Map)),
        );
      } catch (e) {
        debugPrint('Failed to load geocache: $e');
        _cache = {};
      }
    } else {
      _cache = {};
    }
  }

  static Future<void> _saveCache() async {
    if (_cache == null || _cachePath == null) return;
    try {
      final file = File(_cachePath!);
      await file.writeAsString(jsonEncode(_cache));
    } catch (e) {
      debugPrint('Failed to save geocache: $e');
    }
  }
}
