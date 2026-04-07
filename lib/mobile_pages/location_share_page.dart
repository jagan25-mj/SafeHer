import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_config.dart';
import '../theme.dart';

class LocationSharePage extends StatefulWidget {
  const LocationSharePage({super.key});

  @override
  State<LocationSharePage> createState() => _LocationSharePageState();
}

class _LocationSharePageState extends State<LocationSharePage> {
  bool _sharing = false;
  bool _loading = true;
  bool _requestingPermission = false;
  String? _error;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;
  String _status = 'Signal dormant';

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final position = await _getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
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

  Future<Position> _getCurrentPosition() async {
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

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _syncTracking(Position position, {required bool isLive}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await Supabase.instance.client.from('tracking').upsert({
      'user_id': user.id,
      'lat': position.latitude,
      'lng': position.longitude,
      'is_live': isLive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _toggleSharing() async {
    if (_requestingPermission) return;

    setState(() => _requestingPermission = true);
    try {
      if (_sharing) {
        final position = _currentPosition;
        if (position != null) {
          await _syncTracking(position, isLive: false);
        }
        await _positionSubscription?.cancel();
        _positionSubscription = null;
        if (!mounted) return;
        setState(() {
          _sharing = false;
          _status = 'Signal dormant';
        });
        return;
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Please login first.');
      }

      final position = await _getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _sharing = true;
        _status = 'Signal active and syncing to tracking table';
      });
      await _syncTracking(position, isLive: true);

      final stream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      _positionSubscription = stream.listen((nextPosition) async {
        if (!mounted) return;
        setState(() => _currentPosition = nextPosition);
        await _syncTracking(nextPosition, isLive: true);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingPermission = false);
    }
  }

  Future<void> _copyShareLink() async {
    final user = Supabase.instance.client.auth.currentUser;
    final uri = AppConfig.webAppUri;
    if (user == null || uri == null) return;

    final shareUrl =
        '${uri.toString().replaceAll(RegExp(r'/$'), '')}/track/${user.id}';
    await Clipboard.setData(ClipboardData(text: shareUrl));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Share link copied to clipboard.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final uri = AppConfig.webAppUri;
    final shareUrl = user == null || uri == null
        ? null
        : '${uri.toString().replaceAll(RegExp(r'/$'), '')}/track/${user.id}';

    return Scaffold(
      appBar: AppBar(title: const Text('Location Sharing')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: SafeHerGradients.pageBackground,
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadCurrentPosition,
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
                              'Broadcast Orbit',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: const Color(0xFF4F336F),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Mirror your live tracking state into the tracking table and share your safety link from the web app.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
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
                                  label: _sharing
                                      ? 'Sharing active'
                                      : 'Sharing stopped',
                                  background: _sharing
                                      ? const Color(0xFFDCF8ED)
                                      : const Color(0xFFFFE2F1),
                                  foreground: _sharing
                                      ? const Color(0xFF1F7A5C)
                                      : const Color(0xFFA93975),
                                ),
                                _Pill(
                                  label: _currentPosition == null
                                      ? 'Locating...'
                                      : 'GPS synced',
                                  background: const Color(0xFFE7DFFF),
                                  foreground: const Color(0xFF5A4AA6),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE2E2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.redAccent.shade100,
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFF9A2D2D),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: safeHerGlassDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live Coordinates',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: const Color(0xFF4F336F),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            if (_currentPosition == null)
                              const Text(
                                'Waiting for location...',
                                style: TextStyle(
                                  color: Color(0xFF7F5B96),
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else
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
                            const SizedBox(height: 12),
                            Text(
                              _status,
                              style: const TextStyle(
                                color: Color(0xFF6E5386),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _requestingPermission
                              ? null
                              : _toggleSharing,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: _sharing
                                ? Colors.redAccent
                                : SafeHerColors.brandStrong,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(
                            _sharing
                                ? Icons.stop_circle_outlined
                                : Icons.radar_rounded,
                          ),
                          label: Text(
                            _sharing ? 'Stop Sharing' : 'Start Sharing',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (shareUrl != null)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _copyShareLink,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy Web Tracking Link'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFF5F3F81),
                              side: const BorderSide(
                                color: SafeHerColors.stroke,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: SafeHerColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: SafeHerColors.stroke),
                        ),
                        child: Text(
                          shareUrl ??
                              'Set SAFEHER_WEB_URL to generate the share link.',
                          style: const TextStyle(
                            color: Color(0xFF6E5386),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: safeHerGlassDecoration(),
                        child: const Text(
                          'When sharing is active, location updates are written to the tracking table so the web dashboard can show live state.',
                          style: TextStyle(
                            color: Color(0xFF6E5386),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
