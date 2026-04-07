import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class SOSService {
  static CameraController? _controller;
  static bool _isRecording = false;
  static bool _backgroundConfigured = false;

  static Future<void> startSOSRecording(BuildContext context) async {
    await startDualCameraSOSRecording(context: context);
  }

  static Future<void> startDualCameraSOSRecording({
    required BuildContext context,
    void Function(String status)? onStatusChanged,
    void Function(String message)? onLog,
    void Function(bool isRecording)? onRecordingChanged,
  }) async {
    if (_isRecording) return;

    onRecordingChanged?.call(true);
    onStatusChanged?.call('Requesting camera and microphone permissions...');

    try {
      final permissions = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      if (!permissions[Permission.camera]!.isGranted ||
          !permissions[Permission.microphone]!.isGranted) {
        throw Exception(
          'Camera and microphone access is required for SOS recording.',
        );
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Please login first.');
      }

      final position = await _getCurrentPosition();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera hardware detected.');
      }

      final backCamera = _cameraByLens(cameras, CameraLensDirection.back);
      final frontCamera = _cameraByLens(cameras, CameraLensDirection.front);

      if (backCamera == null || frontCamera == null) {
        throw Exception(
          'Both front and back cameras are required for this SOS flow.',
        );
      }

      _isRecording = true;
      await _startBackgroundProtection();
      onStatusChanged?.call('Background protection active. Starting SOS...');
      onLog?.call('SOS started.');

      final backFile = await _recordClip(
        camera: backCamera,
        label: 'Back',
        onStatusChanged: onStatusChanged,
        onLog: onLog,
      );
      await _uploadClip(
        user: user,
        file: backFile,
        label: 'back',
        position: position,
        onStatusChanged: onStatusChanged,
        onLog: onLog,
      );

      final frontFile = await _recordClip(
        camera: frontCamera,
        label: 'Front',
        onStatusChanged: onStatusChanged,
        onLog: onLog,
      );
      await _uploadClip(
        user: user,
        file: frontFile,
        label: 'front',
        position: position,
        onStatusChanged: onStatusChanged,
        onLog: onLog,
      );

      onStatusChanged?.call('Completed: both cameras recorded for 30 seconds.');
      onLog?.call('SOS completed successfully.');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Both front and back camera videos uploaded.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      rethrow;
    } finally {
      _isRecording = false;
      onRecordingChanged?.call(false);
      await _controller?.dispose();
      _controller = null;
      await _stopBackgroundProtection();
    }
  }

  static CameraDescription? _cameraByLens(
    List<CameraDescription> cameras,
    CameraLensDirection direction,
  ) {
    for (final camera in cameras) {
      if (camera.lensDirection == direction) return camera;
    }
    return null;
  }

  static Future<File> _recordClip({
    required CameraDescription camera,
    required String label,
    required void Function(String status)? onStatusChanged,
    required void Function(String message)? onLog,
  }) async {
    await _controller?.dispose();
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    await _controller!.initialize();
    await _controller!.startVideoRecording();
    onLog?.call('$label recording started (30s).');
    onStatusChanged?.call('Recording $label camera (30s)...');

    await Future.delayed(const Duration(seconds: 30));
    final xFile = await _controller!.stopVideoRecording();
    onLog?.call('$label recording finished.');

    return File(xFile.path);
  }

  static Future<void> _uploadClip({
    required User user,
    required File file,
    required String label,
    required Position? position,
    required void Function(String status)? onStatusChanged,
    required void Function(String message)? onLog,
  }) async {
    onStatusChanged?.call('Uploading $label camera video...');

    final fileName =
        'sos_${label}_${DateTime.now().microsecondsSinceEpoch}.mp4';
    final storagePath = '${user.id}/$fileName';

    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await Supabase.instance.client.storage
            .from('sos-vault')
            .upload(
              storagePath,
              file,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: false,
              ),
            );

        final publicUrl = Supabase.instance.client.storage
            .from('sos-vault')
            .getPublicUrl(storagePath);

        onStatusChanged?.call('Saving $label evidence to database...');
        await Supabase.instance.client.from('sos_vault').insert({
          'user_id': user.id,
          'video_url': publicUrl,
          'location_snapshot': position == null
              ? null
              : {
                  'lat': position.latitude,
                  'lng': position.longitude,
                  'accuracy': position.accuracy,
                  'timestamp': DateTime.now().toUtc().toIso8601String(),
                },
          'status': 'PENDING',
        });

        onLog?.call('$label video uploaded and DB row inserted.');
        return;
      } catch (error) {
        lastError = error;
        onLog?.call('Upload attempt $attempt for $label failed: $error');
        if (attempt == 1) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    throw Exception('Failed to store $label evidence: $lastError');
  }

  static Future<void> _startBackgroundProtection() async {
    await _ensureBackgroundServiceConfigured();
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    }
    service.invoke('setAsForeground');
    service.invoke('update', {
      'title': 'SafeHer SOS Active',
      'content': 'Recording in progress with background protection.',
    });
  }

  static Future<void> _stopBackgroundProtection() async {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) return;
    service.invoke('update', {
      'title': 'SafeHer SOS Completed',
      'content': 'Recording finished and evidence secured.',
    });
    service.invoke('stopService');
  }

  static Future<void> _ensureBackgroundServiceConfigured() async {
    if (_backgroundConfigured) return;

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundServiceStart,
        autoStart: false,
        isForegroundMode: true,
        autoStartOnBoot: false,
        initialNotificationTitle: 'SafeHer SOS Guard',
        initialNotificationContent: 'Background safety service is ready.',
        foregroundServiceNotificationId: 2211,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onBackgroundServiceStart,
        onBackground: _onIosBackground,
      ),
    );

    _backgroundConfigured = true;
  }

  static Future<Position?> _getCurrentPosition() async {
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
}

@pragma('vm:entry-point')
void _onBackgroundServiceStart(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'SafeHer SOS Guard',
      content: 'Background protection enabled.',
    );

    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  service.on('update').listen((event) {
    if (service is AndroidServiceInstance) {
      final title = event?['title']?.toString() ?? 'SafeHer SOS';
      final content =
          event?['content']?.toString() ?? 'Background protection enabled.';
      service.setForegroundNotificationInfo(title: title, content: content);
    }
  });

  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}
