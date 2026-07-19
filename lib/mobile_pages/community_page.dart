import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

/// Safety Community page — shows nearby SafeHer users on a map
/// who have opted in to share their live location.
/// Users can see exact positions of other community members.
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  Position? _myPosition;
  bool _loading = true;
  String? _error;
  bool _sharingMyLocation = false;
  Timer? _locationUpdateTimer;
  List<_CommunityMember> _nearbyMembers = [];

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Location request timed out. Please allow location access and try again.'),
      );

      if (!mounted) return;
      setState(() {
        _myPosition = position;
        _loading = false;
      });

      // Check if user is already sharing
      await _checkSharingStatus();

      // Fetch nearby members
      await _fetchNearbyMembers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _checkSharingStatus() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final result = await _supabase
          .from('community_locations')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _sharingMyLocation = result != null;
      });
    } catch (_) {
      // Table might not exist yet
    }
  }

  Future<void> _toggleLocationSharing() async {
    final user = _supabase.auth.currentUser;
    if (user == null || _myPosition == null) return;

    try {
      if (_sharingMyLocation) {
        // Stop sharing
        await _supabase
            .from('community_locations')
            .delete()
            .eq('user_id', user.id);

        _locationUpdateTimer?.cancel();
        _locationUpdateTimer = null;

        if (!mounted) return;
        setState(() => _sharingMyLocation = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location sharing stopped.'),
            ),
          );
        }
      } else {
        // Start sharing — upsert current location
        await _upsertMyLocation();

        // Start periodic updates every 30 seconds
        _locationUpdateTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => _upsertMyLocation(),
        );

        if (!mounted) return;
        setState(() => _sharingMyLocation = true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Now sharing your location with the community.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _upsertMyLocation() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      await _supabase.from('community_locations').upsert({
        'user_id': user.id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'display_name': user.email?.split('@').first ?? 'SafeHer User',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');

      if (mounted) {
        setState(() => _myPosition = position);
      }
    } catch (e) {
      debugPrint('Failed to update location: $e');
    }
  }

  Future<void> _fetchNearbyMembers() async {
    if (_myPosition == null) return;

    final user = _supabase.auth.currentUser;

    try {
      final rows = await _supabase
          .from('community_locations')
          .select('user_id,latitude,longitude,display_name,updated_at');

      final members = <_CommunityMember>[];
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row);
        final memberId = map['user_id']?.toString() ?? '';

        // Skip self
        if (memberId == user?.id) continue;

        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final distanceMeters = Geolocator.distanceBetween(
          _myPosition!.latitude,
          _myPosition!.longitude,
          lat,
          lng,
        );

        // Only show users within 10 km
        if (distanceMeters <= 10000) {
          members.add(_CommunityMember(
            userId: memberId,
            displayName: map['display_name']?.toString() ?? 'SafeHer User',
            latitude: lat,
            longitude: lng,
            distanceMeters: distanceMeters,
            updatedAt: map['updated_at']?.toString() ?? '',
          ));
        }
      }

      // Sort by distance
      members.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

      if (!mounted) return;
      setState(() => _nearbyMembers = members);
    } catch (e) {
      debugPrint('Failed to fetch community members: $e');
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _timeAgo(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final diff = DateTime.now().toUtc().difference(dt);
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Safety Community',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchNearbyMembers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: SafeHerGradients.pageBackground,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFF9A2D2D),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sharing toggle card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: safeHerGlassDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _sharingMyLocation
                            ? const Color(0xFFDCF8ED)
                            : SafeHerColors.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _sharingMyLocation
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: _sharingMyLocation
                            ? SafeHerColors.success
                            : SafeHerColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Share My Location',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: SafeHerColors.foreground,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _sharingMyLocation
                                ? 'Your location is visible to nearby SafeHer users'
                                : 'Turn on to let nearby SafeHer users see you',
                            style: const TextStyle(
                              color: Color(0xFF7F5B96),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _sharingMyLocation,
                      onChanged: (_) => _toggleLocationSharing(),
                      activeThumbColor: SafeHerColors.success,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Map showing nearby members
          if (_myPosition != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: safeHerGlassDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nearby SafeHer Users',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_nearbyMembers.length} member${_nearbyMembers.length == 1 ? '' : 's'} within 10 km',
                    style: const TextStyle(
                      color: Color(0xFF7F5B96),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 280,
                      width: double.infinity,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(
                            _myPosition!.latitude,
                            _myPosition!.longitude,
                          ),
                          initialZoom: 13.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.safeher.app',
                          ),
                          // My location marker
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(
                                  _myPosition!.latitude,
                                  _myPosition!.longitude,
                                ),
                                width: 50,
                                height: 50,
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_pin_circle_rounded,
                                      color: Color(0xFFE74A8A),
                                      size: 36,
                                    ),
                                    Text(
                                      'You',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFE74A8A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Other community members
                              ..._nearbyMembers.map(
                                (member) => Marker(
                                  point: LatLng(
                                    member.latitude,
                                    member.longitude,
                                  ),
                                  width: 60,
                                  height: 50,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.person_pin_circle_rounded,
                                        color: Color(0xFF6F5BB6),
                                        size: 30,
                                      ),
                                      Text(
                                        member.displayName,
                                        style: const TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF6F5BB6),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Members list
          if (_nearbyMembers.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: safeHerGlassDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Community Members Nearby',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: SafeHerColors.foreground,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _nearbyMembers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final member = _nearbyMembers[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SafeHerColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: SafeHerColors.stroke),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: SafeHerColors.accentSoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  member.displayName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: SafeHerColors.accent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: SafeHerColors.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_formatDistance(member.distanceMeters)} away • ${_timeAgo(member.updatedAt)}',
                                    style: const TextStyle(
                                      color: Color(0xFF7F5B96),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCF8ED),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _formatDistance(member.distanceMeters),
                                style: const TextStyle(
                                  color: Color(0xFF1F7A5C),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
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
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: safeHerGlassDecoration(),
              child: Column(
                children: [
                  const Icon(
                    Icons.people_outline_rounded,
                    size: 48,
                    color: Color(0xFFB8A0D0),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No nearby community members yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: SafeHerColors.foreground,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Share your location and invite friends to join the SafeHer community for mutual safety.',
                    style: TextStyle(
                      color: Color(0xFF7F5B96),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommunityMember {
  final String userId;
  final String displayName;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final String updatedAt;

  const _CommunityMember({
    required this.userId,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.updatedAt,
  });
}
