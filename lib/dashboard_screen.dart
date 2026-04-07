import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'sos_service.dart';
import 'mobile_pages/articles_page.dart';
import 'mobile_pages/contacts_page.dart';
import 'mobile_pages/helplines_page.dart';
import 'mobile_pages/location_share_page.dart';
import 'mobile_pages/safety_map_page.dart';
import 'theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  bool _isRecording = false;
  String _sosStatus = 'Ready';
  final List<String> _sosLogs = [];
  final List<_HelplineItem> _helplines = [];
  final List<_ArticleItem> _articles = [];
  Position? _currentPosition;
  String _mapThreat = 'Low';
  List<_MapSafePlace> _mapSafePlaces = const [];
  bool _showDangerZone = true;
  bool _showSafePlaces = true;
  bool _loadingLocation = true;
  String? _locationError;
  bool _loadingDashboardData = true;
  String? _dashboardDataError;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadLocationPreview();
  }

  void _addSosLog(String message) {
    if (!mounted) return;
    setState(() {
      _sosLogs.insert(
        0,
        '${DateTime.now().toLocal().toString().substring(11, 19)}  $message',
      );
    });
  }

  Future<void> _loadDashboardData() async {
    try {
      final helplineRows = await Supabase.instance.client
          .from('helplines')
          .select('name,number,category')
          .order('name', ascending: true);

      final articleRows = await Supabase.instance.client
          .from('safety_content')
          .select('title,content,image_url,created_at')
          .eq('type', 'ARTICLE')
          .order('created_at', ascending: false)
          .limit(3);

      if (!mounted) return;
      setState(() {
        _helplines
          ..clear()
          ..addAll(
            (helplineRows as List).map(
              (row) => _HelplineItem.fromRow(Map<String, dynamic>.from(row)),
            ),
          );
        _articles
          ..clear()
          ..addAll(
            (articleRows as List).map(
              (row) => _ArticleItem.fromRow(Map<String, dynamic>.from(row)),
            ),
          );
        _loadingDashboardData = false;
        _dashboardDataError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDashboardData = false;
        _dashboardDataError = e.toString();
      });
    }
  }

  Future<void> _loadLocationPreview() async {
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

      final prediction = await predictionFuture;
      final places = await placesFuture;

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _mapThreat = prediction;
        _mapSafePlaces = places;
        _loadingLocation = false;
        _locationError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _locationError = e.toString();
      });
    }
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
      return _normalizeThreat(body['threat_level']);
    } catch (_) {
      return 'Low';
    }
  }

  Future<List<_MapSafePlace>> _fetchSafePlaces(Position position) async {
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
          .map(_MapSafePlace.fromOverpass)
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
    switch (_mapThreat) {
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
    switch (_mapThreat) {
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

  Future<void> _startSOS() async {
    try {
      if (mounted) {
        setState(() {
          _isRecording = true;
          _sosStatus =
              'Starting mobile SOS: back + front cameras (30s each)...';
        });
      }

      await SOSService.startDualCameraSOSRecording(
        context: context,
        onStatusChanged: (status) {
          if (!mounted) return;
          setState(() => _sosStatus = status);
        },
        onLog: _addSosLog,
        onRecordingChanged: (value) {
          if (!mounted) return;
          setState(() => _isRecording = value);
        },
      );

      if (mounted) {
        setState(() {
          _isRecording = false;
          _sosStatus = 'Completed: both cameras recorded for 30 seconds.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Both front and back camera videos uploaded.'),
          ),
        );
      }
    } catch (e) {
      debugPrint("SOS Error: $e");
      if (mounted) {
        setState(() {
          _isRecording = false;
          _sosStatus = 'SOS failed.';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Critical Error: $e")));
      }
      _addSosLog('SOS failed: $e');
    }
  }

  Future<void> _callHelpline(String number) async {
    final uri = Uri.parse('tel:$number');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialer for $number')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final foregroundColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : SafeHerColors.foreground;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: surfaceColor.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/icon/app_icon.jpeg',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SafeHer Dashboard',
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                Text(
                  Theme.of(context).brightness == Brightness.dark
                      ? 'Dark mode active'
                      : 'Light mode active',
                  style: TextStyle(
                    color: foregroundColor.withValues(alpha: 0.68),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _isRecording ? null : _startSOS,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB4235A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              icon: const Icon(Icons.sos_rounded, size: 18),
              label: const Text('Quick SOS'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: SafeHerGradients.pageBackground,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: safeHerGlassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Personal Safety Companion",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRecording
                            ? _sosStatus
                            : "Stay prepared with trusted contacts, live location sharing, and one-tap SOS.",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF7F5B96),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Pill(
                            label: _isRecording ? _sosStatus : '$_sosStatus',
                            background: _isRecording
                                ? const Color(0xFFFFE2F1)
                                : const Color(0xFFDCF8ED),
                            foreground: _isRecording
                                ? const Color(0xFFA93975)
                                : const Color(0xFF1F7A5C),
                          ),
                          const _Pill(
                            label: "User App",
                            background: Color(0xFFE7DFFF),
                            foreground: Color(0xFF5A4AA6),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE9F1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF4BCD0)),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.shield_moon_rounded,
                      color: Color(0xFFB4235A),
                    ),
                    title: const Text(
                      'Start SOS Recording Now',
                      style: TextStyle(
                        color: Color(0xFF4A2640),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: const Text(
                      'Runs with background protection enabled.',
                      style: TextStyle(
                        color: Color(0xFF7A4361),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: FilledButton(
                      onPressed: _isRecording ? null : _startSOS,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB4235A),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isRecording ? 'Recording' : 'Start'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SafeHerColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SafeHerColors.stroke),
                  ),
                  child: const Text(
                    'Mobile SOS records both back and front cameras for 30 seconds each. The web version keeps its own single-camera flow.',
                    style: TextStyle(
                      color: Color(0xFF6E5386),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: safeHerGlassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location Preview',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A quick snapshot of your current location before you open the safety map.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7F5B96),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingLocation)
                        const Center(child: CircularProgressIndicator())
                      else if (_locationError != null)
                        Text(
                          _locationError!,
                          style: const TextStyle(
                            color: Color(0xFF9A2D2D),
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (_currentPosition != null)
                        Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: SizedBox(
                                height: 180,
                                width: double.infinity,
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter: LatLng(
                                      _currentPosition!.latitude,
                                      _currentPosition!.longitude,
                                    ),
                                    initialZoom: 14.5,
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
                                              _currentPosition!.latitude,
                                              _currentPosition!.longitude,
                                            ),
                                            radius: _zoneRadius(),
                                            useRadiusInMeter: true,
                                            color: _zoneColor().withValues(
                                              alpha: 0.2,
                                            ),
                                            borderColor: _zoneColor(),
                                            borderStrokeWidth: 1.2,
                                          ),
                                        ],
                                      ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: LatLng(
                                            _currentPosition!.latitude,
                                            _currentPosition!.longitude,
                                          ),
                                          width: 46,
                                          height: 46,
                                          child: const Icon(
                                            Icons.location_pin,
                                            color: Color(0xFFE74A8A),
                                            size: 34,
                                          ),
                                        ),
                                        if (_showSafePlaces)
                                          ..._mapSafePlaces.map(
                                            (place) => Marker(
                                              point: LatLng(
                                                place.lat,
                                                place.lng,
                                              ),
                                              width: 42,
                                              height: 42,
                                              child: Icon(
                                                place.icon,
                                                color: place.color,
                                                size: 26,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
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
                                    'Safe Places (${_mapSafePlaces.length})',
                                  ),
                                  selected: _showSafePlaces,
                                  onSelected: (value) =>
                                      setState(() => _showSafePlaces = value),
                                ),
                                _Pill(
                                  label: 'AI: $_mapThreat',
                                  background: _zoneColor().withValues(
                                    alpha: 0.18,
                                  ),
                                  foreground: _zoneColor(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _MetricCard(
                                    label: 'Latitude',
                                    value: _currentPosition!.latitude
                                        .toStringAsFixed(6),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _MetricCard(
                                    label: 'Longitude',
                                    value: _currentPosition!.longitude
                                        .toStringAsFixed(6),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.06,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _FeatureTile(
                      icon: Icons.contact_phone,
                      title: "Emergency Contacts",
                      subtitle: "Call and alert trusted people fast",
                      onTap: () => _openContactsPage(context),
                    ),
                    _FeatureTile(
                      icon: Icons.map_rounded,
                      title: "Safety Map",
                      subtitle: "See your live location summary",
                      onTap: () => _openSafetyMapPage(context),
                    ),
                    _FeatureTile(
                      icon: Icons.location_on_rounded,
                      title: "Location Sharing",
                      subtitle: "Sync tracking data to the DB",
                      onTap: () => _openLocationSharePage(context),
                    ),
                    _FeatureTile(
                      icon: Icons.videocam_rounded,
                      title: "SOS Recording",
                      subtitle: "Upload 30s front + back clips",
                      onTap: _startSOS,
                    ),
                    _FeatureTile(
                      icon: Icons.support_agent,
                      title: "Helplines",
                      subtitle: "Quick access to emergency support",
                      onTap: () => _openHelplinesPage(context),
                    ),
                    _FeatureTile(
                      icon: Icons.article_outlined,
                      title: "Articles",
                      subtitle: "Practical safety guidance",
                      onTap: () => _openArticlesPage(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: SafeHerGradients.brand,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: SafeHerColors.brand.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isRecording ? null : _startSOS,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white,
                      disabledBackgroundColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: Icon(
                      _isRecording ? Icons.shield : Icons.warning_amber_rounded,
                      color: Colors.white,
                    ),
                    label: Text(
                      _isRecording
                          ? "SECURED - Recording 30s safety log"
                          : "Start SOS Recording",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_sosLogs.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SafeHerColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: SafeHerColors.stroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SOS Activity',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: SafeHerColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._sosLogs
                            .take(6)
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  entry,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6E5386),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: safeHerGlassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency Numbers',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Verified support numbers from your web dashboard.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7F5B96),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loadingDashboardData)
                        const Center(child: CircularProgressIndicator())
                      else if (_dashboardDataError != null)
                        Text(
                          _dashboardDataError!,
                          style: const TextStyle(
                            color: Color(0xFF9A2D2D),
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (_helplines.isEmpty)
                        const Text(
                          'No helplines available.',
                          style: TextStyle(
                            color: Color(0xFF6E5386),
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _helplines.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _helplines[index];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: SafeHerColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: SafeHerColors.stroke),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.service,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: SafeHerColors.foreground,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.scopeLabel,
                                          style: const TextStyle(
                                            color: Color(0xFF7F5B96),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    item.number,
                                    style: const TextStyle(
                                      color: SafeHerColors.brandStrong,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _callHelpline(item.number),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(78, 38),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      backgroundColor: SafeHerColors.accent,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.call_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Call',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: safeHerGlassDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Safety Articles',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Short reads to help you stay alert and prepared.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7F5B96),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loadingDashboardData)
                        const Center(child: CircularProgressIndicator())
                      else if (_dashboardDataError != null)
                        Text(
                          _dashboardDataError!,
                          style: const TextStyle(
                            color: Color(0xFF9A2D2D),
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (_articles.isEmpty)
                        const Text(
                          'No articles available.',
                          style: TextStyle(
                            color: Color(0xFF6E5386),
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _articles.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final article = _articles[index];
                            return InkWell(
                              onTap: () => _openArticlesPage(context),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: SafeHerColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: SafeHerColors.stroke,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: SafeHerColors.accentSoft,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.menu_book_rounded,
                                        color: SafeHerColors.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            article.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: SafeHerColors.foreground,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${article.category} • ${article.readTime}',
                                            style: const TextStyle(
                                              color: Color(0xFF7F5B96),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openContactsPage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ContactsPage()));
  }

  void _openHelplinesPage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HelplinesPage()));
  }

  void _openSafetyMapPage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SafetyMapPage()));
  }

  void _openLocationSharePage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LocationSharePage()));
  }

  void _openArticlesPage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ArticlesPage()));
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: SafeHerColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: SafeHerColors.accent),
              ),
              const Spacer(),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF7F5B96)),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: SafeHerColors.brand,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Open',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
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

class _HelplineItem {
  final String service;
  final String number;
  final String availability;
  final String scope;

  const _HelplineItem({
    required this.service,
    required this.number,
    required this.availability,
    required this.scope,
  });

  factory _HelplineItem.fromRow(Map<String, dynamic> row) {
    final name = (row['name']?.toString() ?? '').trim();
    final category = (row['category']?.toString() ?? '').trim();
    return _HelplineItem(
      service: name.isEmpty ? 'Helpline' : name,
      number: (row['number']?.toString() ?? '').trim(),
      availability: '24/7',
      scope: category.isEmpty ? 'General support' : category,
    );
  }

  String get scopeLabel => '$availability • $scope';
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

class _ArticleItem {
  final String title;
  final String category;
  final String readTime;
  final String summary;
  final String content;
  final String? imageUrl;

  const _ArticleItem({
    required this.title,
    required this.category,
    required this.readTime,
    required this.summary,
    required this.content,
    this.imageUrl,
  });

  factory _ArticleItem.fromRow(Map<String, dynamic> row) {
    final title = (row['title']?.toString() ?? '').trim();
    final content = (row['content']?.toString() ?? '').trim();
    final category = _deriveCategory(title, content);
    return _ArticleItem(
      title: title,
      category: category,
      readTime: _deriveReadTime(content),
      summary: _deriveSummary(content),
      content: content,
      imageUrl: row['image_url']?.toString(),
    );
  }

  static String _deriveCategory(String title, String content) {
    final text = '$title $content'.toLowerCase();
    if (text.contains('digital') || text.contains('privacy')) {
      return 'Digital Safety';
    }
    if (text.contains('travel') ||
        text.contains('commute') ||
        text.contains('night')) {
      return 'Travel';
    }
    if (text.contains('sos') ||
        text.contains('plan') ||
        text.contains('prepared')) {
      return 'Preparedness';
    }
    if (text.contains('response') || text.contains('alert')) {
      return 'Response';
    }
    return 'Safety';
  }

  static String _deriveReadTime(String content) {
    final words = content
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
    final minutes = (words / 180).ceil().clamp(1, 15);
    return '$minutes min';
  }

  static String _deriveSummary(String content) {
    final collapsed = content
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (collapsed.length <= 120) return collapsed;
    return '${collapsed.substring(0, 117)}...';
  }
}

class _MapSafePlace {
  final double lat;
  final double lng;
  final String type;

  const _MapSafePlace({
    required this.lat,
    required this.lng,
    required this.type,
  });

  factory _MapSafePlace.fromOverpass(Map<String, dynamic> row) {
    final tags = Map<String, dynamic>.from(
      row['tags'] as Map? ?? <String, dynamic>{},
    );
    return _MapSafePlace(
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lon'] as num).toDouble(),
      type: tags['amenity']?.toString() ?? 'safe_point',
    );
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
