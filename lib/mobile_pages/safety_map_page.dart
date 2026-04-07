import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_config.dart';
import '../theme.dart';

class SafetyMapPage extends StatefulWidget {
  const SafetyMapPage({super.key});

  @override
  State<SafetyMapPage> createState() => _SafetyMapPageState();
}

class _SafetyMapPageState extends State<SafetyMapPage> {
  Position? _position;
  bool _loading = true;
  String? _error;
  bool? _isLive;
  DateTime? _updatedAt;
  String _threat = 'Low';
  List<_SafePlace> _safePlaces = const [];
  bool _showSafePlaces = true;
  bool _showDangerZone = true;
  _SafePlace? _selectedPlace;

  @override
  void initState() {
    super.initState();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final predictionFuture = _fetchThreatPrediction(position);
      final placesFuture = _fetchSafePlaces(position);

      final user = Supabase.instance.client.auth.currentUser;
      bool? isLive;
      DateTime? updatedAt;
      if (user != null) {
        final row = await Supabase.instance.client
            .from('tracking')
            .select('is_live, updated_at')
            .eq('user_id', user.id)
            .maybeSingle();
        isLive = row?['is_live'] as bool?;
        final updatedRaw = row?['updated_at']?.toString();
        updatedAt = updatedRaw == null ? null : DateTime.tryParse(updatedRaw);
      }

      final prediction = await predictionFuture;
      final places = await placesFuture;

      if (!mounted) return;
      setState(() {
        _position = position;
        _isLive = isLive;
        _updatedAt = updatedAt;
        _threat = prediction;
        _safePlaces = places;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openMaps() async {
    if (_position == null) return;
    final latitude = _position!.latitude;
    final longitude = _position!.longitude;
    final googleMapsUri = Platform.isIOS
        ? Uri.parse(
            'comgooglemaps://?q=$latitude,$longitude&center=$latitude,$longitude&zoom=16',
          )
        : Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude');
    final webMapsUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );

    try {
      final launched = await launchUrl(
        googleMapsUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    } catch (_) {
      // Fallback below.
    }

    await launchUrl(webMapsUri, mode: LaunchMode.externalApplication);
  }

  Future<String> _fetchThreatPrediction(Position position) async {
    final webUri = AppConfig.webAppUri;
    if (webUri == null) return 'Low';

    final predictUri = webUri.replace(
      path: '${webUri.path.replaceAll(RegExp(r'/$'), '')}/api/predict',
    );

    try {
      final response = await http.post(
        predictUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'district_encoded': _deriveDistrictCode(
            position.latitude,
            position.longitude,
          ),
          'year': DateTime.now().year,
          'murder_with_rape_gang_rape': 0,
          'dowry_deaths': 0,
          'acid_attack': 0,
          'cruelty_by_husband_or_his_relatives': 0,
          'kidnapping_and_abduction': 0,
          'rape_women_above_18': 0,
          'rape_girls_below_18': 0,
          'assault_on_womenabove_18': 0,
          'assault_on_women_below_18': 0,
          'child_rape': 0,
          'sexual_assault_of_children': 0,
          'offences_of_pocso_act': 0,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'Low';
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawThreat = body['threat_level'];
      return _normalizeThreat(rawThreat);
    } catch (_) {
      return 'Low';
    }
  }

  Future<List<_SafePlace>> _fetchSafePlaces(Position position) async {
    final query =
        '''
[out:json][timeout:25];
(
  node(around:5000,${position.latitude},${position.longitude})[amenity=police];
  node(around:5000,${position.latitude},${position.longitude})[amenity=hospital];
  node(around:5000,${position.latitude},${position.longitude})[amenity=fire_station];
);
out body 20;
''';

    final uri = Uri.parse('https://overpass-api.de/api/interpreter');

    try {
      final response = await http.post(uri, body: {'data': query});
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (decoded['elements'] as List?) ?? const [];

      return elements
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => row['lat'] is num && row['lon'] is num)
          .map(_SafePlace.fromOverpass)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  int _deriveDistrictCode(double lat, double lng) {
    final normalized = ((lat.abs() * 100) + (lng.abs() * 100)).round();
    return normalized % 100;
  }

  String _normalizeThreat(dynamic raw) {
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return 'Low';
      return text[0].toUpperCase() + text.substring(1).toLowerCase();
    }
    if (raw is num) {
      switch (raw.toInt()) {
        case 3:
          return 'Critical';
        case 2:
          return 'High';
        case 1:
          return 'Medium';
        default:
          return 'Low';
      }
    }
    return 'Low';
  }

  Color _zoneColor() {
    switch (_threat) {
      case 'Critical':
        return const Color(0xFFEF4444);
      case 'High':
        return const Color(0xFFF97316);
      case 'Medium':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF22C55E);
    }
  }

  double _zoneRadius() {
    switch (_threat) {
      case 'Critical':
        return 2600;
      case 'High':
        return 1700;
      case 'Medium':
        return 1100;
      default:
        return 700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Map')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: SafeHerGradients.pageBackground,
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadMapData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: safeHerGlassDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Personal Safety Companion',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: const Color(0xFF4F336F),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Live map with AI threat prediction and nearby safe places.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF7F5B96),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: safeHerGlassDecoration(),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 36,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Unable to load safety map.',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: SafeHerColors.foreground,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF7F5B96),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _loadMapData,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SafeHerColors.brandStrong,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Container(
                          height: 260,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: SafeHerColors.stroke),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1F5D3D82),
                                blurRadius: 24,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(
                                _position!.latitude,
                                _position!.longitude,
                              ),
                              initialZoom: 15,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.safeher.app',
                              ),
                              if (_showDangerZone)
                                CircleLayer(
                                  circles: [
                                    CircleMarker(
                                      point: LatLng(
                                        _position!.latitude,
                                        _position!.longitude,
                                      ),
                                      radius: _zoneRadius(),
                                      useRadiusInMeter: true,
                                      color: _zoneColor().withValues(
                                        alpha: 0.22,
                                      ),
                                      borderColor: _zoneColor(),
                                      borderStrokeWidth: 1.4,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                      _position!.latitude,
                                      _position!.longitude,
                                    ),
                                    width: 60,
                                    height: 60,
                                    child: Container(
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.location_pin,
                                        color: Color(0xFFE74A8A),
                                        size: 42,
                                      ),
                                    ),
                                  ),
                                  if (_showSafePlaces)
                                    ..._safePlaces.map(
                                      (place) => Marker(
                                        point: LatLng(place.lat, place.lng),
                                        width: 44,
                                        height: 44,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(
                                              () => _selectedPlace = place,
                                            );
                                          },
                                          child: Icon(
                                            place.icon,
                                            color: place.color,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              RichAttributionWidget(
                                attributions: [
                                  TextSourceAttribution(
                                    'OpenStreetMap contributors',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: safeHerGlassDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  FilterChip(
                                    label: const Text('Danger Zone'),
                                    selected: _showDangerZone,
                                    onSelected: (value) =>
                                        setState(() => _showDangerZone = value),
                                  ),
                                  FilterChip(
                                    label: Text(
                                      'Safe Places (${_safePlaces.length})',
                                    ),
                                    selected: _showSafePlaces,
                                    onSelected: (value) =>
                                        setState(() => _showSafePlaces = value),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'AI Threat Level: $_threat',
                                style: TextStyle(
                                  color: _zoneColor(),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (_selectedPlace != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Selected: ${_selectedPlace!.name} • ${_selectedPlace!.phoneLabel}',
                                  style: const TextStyle(
                                    color: Color(0xFF6E5386),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_safePlaces.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: safeHerGlassDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nearby Safe Places',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 8),
                                ..._safePlaces
                                    .take(6)
                                    .map(
                                      (place) => Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: SafeHerColors.surface,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: SafeHerColors.stroke,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              place.icon,
                                              color: place.color,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    place.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: SafeHerColors
                                                          .foreground,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Phone: ${place.phoneLabel}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF7F5B96),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        if (_safePlaces.isNotEmpty) const SizedBox(height: 16),
                        Container(
                          height: 300,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4F336F), Color(0xFFB64F8F)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1F5D3D82),
                                blurRadius: 24,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                right: -16,
                                top: -18,
                                child: Icon(
                                  Icons.map_outlined,
                                  color: Colors.white.withValues(alpha: 0.12),
                                  size: 170,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _Pill(
                                          label: _isLive == true
                                              ? 'Live tracking enabled'
                                              : 'Tracking offline',
                                          background: _isLive == true
                                              ? const Color(0xFFDCF8ED)
                                              : const Color(0xFFFFE2F1),
                                          foreground: _isLive == true
                                              ? const Color(0xFF1F7A5C)
                                              : const Color(0xFFA93975),
                                        ),
                                        const _Pill(
                                          label: 'AI Monitoring',
                                          background: Color(0xFFE7DFFF),
                                          foreground: Color(0xFF5A4AA6),
                                        ),
                                      ],
                                    ),
                                    Center(
                                      child: Column(
                                        children: [
                                          const Icon(
                                            Icons.place_rounded,
                                            color: Colors.white,
                                            size: 72,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'You are here',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _updatedAt == null
                                          ? 'No tracking update has been saved yet.'
                                          : 'Last DB sync: ${_updatedAt!.toLocal()}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _MetricCard(
                                label: 'Latitude',
                                value: _position!.latitude.toStringAsFixed(6),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MetricCard(
                                label: 'Longitude',
                                value: _position!.longitude.toStringAsFixed(6),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openMaps,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: SafeHerColors.brandStrong,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.map_rounded),
                            label: const Text(
                              'Open in Google Maps',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: safeHerGlassDecoration(),
                          child: const Text(
                            'Use this page as a quick map summary while your live tracking stream is active from the Location Sharing screen.',
                            style: TextStyle(
                              color: Color(0xFF6E5386),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SafeHerColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SafeHerColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7F5B96),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: SafeHerColors.foreground,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SafePlace {
  final String name;
  final double lat;
  final double lng;
  final String type;
  final String? phone;

  const _SafePlace({
    required this.name,
    required this.lat,
    required this.lng,
    required this.type,
    this.phone,
  });

  factory _SafePlace.fromOverpass(Map<String, dynamic> row) {
    final tags = Map<String, dynamic>.from(
      row['tags'] as Map? ?? <String, dynamic>{},
    );
    final amenity = tags['amenity']?.toString() ?? 'safe_point';
    final placeName = tags['name']?.toString() ?? 'Safe Point';
    return _SafePlace(
      name: placeName,
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lon'] as num).toDouble(),
      type: amenity,
      phone: tags['phone']?.toString() ?? tags['contact:phone']?.toString(),
    );
  }

  String get phoneLabel {
    final value = phone?.trim() ?? '';
    return value.isEmpty ? 'Not available' : value;
  }

  IconData get icon {
    switch (type) {
      case 'police':
        return Icons.local_police_rounded;
      case 'fire_station':
        return Icons.local_fire_department_rounded;
      default:
        return Icons.local_hospital_rounded;
    }
  }

  Color get color {
    switch (type) {
      case 'police':
        return const Color(0xFFDC2626);
      case 'fire_station':
        return const Color(0xFFEA580C);
      default:
        return const Color(0xFF2563EB);
    }
  }
}
