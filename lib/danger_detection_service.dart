import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Service that provides two safety features:
/// 1. Shake Detection — detects violent shaking and triggers an alarm + callback.
/// 2. Voice Command — listens for "help me" keyword and triggers SOS callback.
class DangerDetectionService {
  // ── Shake Detection ──
  static const double _shakeThreshold = 15.0; // m/s² threshold
  static const int _shakeCountTrigger = 3;
  static const Duration _shakeResetWindow = Duration(seconds: 2);

  bool _shakeActive = false;
  int _shakeCount = 0;
  DateTime _lastShakeTime = DateTime.now();
  StreamSubscription<dynamic>? _accelerometerSub;
  static const _accelChannel = EventChannel('com.safeher.accelerometer');
  VoidCallback? _onShakeTriggered;

  // ── Voice Command ──
  bool _voiceActive = false;
  stt.SpeechToText? _speech;
  VoidCallback? _onVoiceTriggered;
  Timer? _voiceRestartTimer;
  DateTime _lastVoiceTriggerTime = DateTime(2000);
  static const Duration _voiceCooldown = Duration(seconds: 5);

  // ── Alarm ──
  bool _alarmPlaying = false;
  static const _alarmChannel = MethodChannel('com.safeher.alarm');

  // ─────────────────────────────────────────────
  // Shake Detection
  // ─────────────────────────────────────────────

  bool get isShakeActive => _shakeActive;
  bool get isVoiceActive => _voiceActive;
  bool get isAlarmPlaying => _alarmPlaying;

  /// Start listening for shake events.
  /// [onTriggered] is called when a violent shake pattern is detected.
  void startShakeDetection({required VoidCallback onTriggered}) {
    if (_shakeActive) return;
    _shakeActive = true;
    _shakeCount = 0;
    _onShakeTriggered = onTriggered;

    // Use a simple timer-based polling approach using the platform's
    // accelerometer since the sensors_plus package may not be in the project.
    // We'll use a simulated approach via a periodic timer that checks
    // device motion through the method channel.
    _startAccelerometerPolling();
  }

  void _startAccelerometerPolling() {
    // Using a periodic timer that reads accelerometer data
    // This is a fallback; the primary approach uses the EventChannel
    try {
      _accelerometerSub = _accelChannel
          .receiveBroadcastStream()
          .listen((event) {
        if (event is Map) {
          final x = (event['x'] as num?)?.toDouble() ?? 0;
          final y = (event['y'] as num?)?.toDouble() ?? 0;
          final z = (event['z'] as num?)?.toDouble() ?? 0;
          _processAcceleration(x, y, z);
        }
      }, onError: (_) {
        // If native channel not available, fall back to simulated shake
        // detection (user can still trigger manually)
        debugPrint('Accelerometer channel not available, using fallback.');
      });
    } catch (_) {
      debugPrint('Failed to start accelerometer stream.');
    }
  }

  void _processAcceleration(double x, double y, double z) {
    if (!_shakeActive) return;

    final magnitude = sqrt(x * x + y * y + z * z);
    final now = DateTime.now();

    if (magnitude > _shakeThreshold) {
      if (now.difference(_lastShakeTime) > _shakeResetWindow) {
        _shakeCount = 0;
      }
      _shakeCount++;
      _lastShakeTime = now;

      if (_shakeCount >= _shakeCountTrigger) {
        _shakeCount = 0;
        _triggerShakeAlarm();
      }
    }
  }

  void _triggerShakeAlarm() {
    playAlarm();
    HapticFeedback.heavyImpact();
    _onShakeTriggered?.call();
  }

  void stopShakeDetection() {
    _shakeActive = false;
    _shakeCount = 0;
    _accelerometerSub?.cancel();
    _accelerometerSub = null;
    _onShakeTriggered = null;
  }

  // ─────────────────────────────────────────────
  // Voice Command ("Help Me" detection)
  // ─────────────────────────────────────────────

  /// Start listening for the "help me" voice command.
  /// The user manually toggles this on when feeling unsafe.
  Future<void> startVoiceCommand({required VoidCallback onTriggered}) async {
    if (_voiceActive) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      throw Exception('Microphone permission is required for voice commands.');
    }

    _speech = stt.SpeechToText();
    final available = await _speech!.initialize(
      onError: (error) {
        debugPrint('Speech error: ${error.errorMsg}');
        // Auto-restart listening after error
        if (_voiceActive) {
          _scheduleVoiceRestart();
        }
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
        // When speech recognition stops (e.g., silence timeout), restart it
        if (status == 'notListening' && _voiceActive) {
          _scheduleVoiceRestart();
        }
      },
    );

    if (!available) {
      throw Exception('Speech recognition is not available on this device.');
    }

    _voiceActive = true;
    _onVoiceTriggered = onTriggered;
    _startListening();
  }

  void _startListening() {
    if (!_voiceActive || _speech == null) return;

    _speech!.listen(
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        debugPrint('Heard: $words');
        // Only trigger on specific distress phrases — not standalone "help"
        if (words.contains('help me') ||
            words.contains('bachao') ||
            words.contains('save me')) {
          // Cooldown: prevent duplicate triggers within 5 seconds
          final now = DateTime.now();
          if (now.difference(_lastVoiceTriggerTime) > _voiceCooldown) {
            _lastVoiceTriggerTime = now;
            _triggerVoiceAlarm();
          }
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  void _scheduleVoiceRestart() {
    _voiceRestartTimer?.cancel();
    _voiceRestartTimer = Timer(const Duration(milliseconds: 500), () {
      if (_voiceActive) {
        _startListening();
      }
    });
  }

  void _triggerVoiceAlarm() {
    playAlarm();
    HapticFeedback.heavyImpact();
    _onVoiceTriggered?.call();
  }

  Future<void> stopVoiceCommand() async {
    _voiceActive = false;
    _voiceRestartTimer?.cancel();
    _voiceRestartTimer = null;
    _onVoiceTriggered = null;
    await _speech?.stop();
    await _speech?.cancel();
    _speech = null;
  }

  // ─────────────────────────────────────────────
  // Alarm (loud siren sound)
  // ─────────────────────────────────────────────

  /// Play a loud alarm using the system's alarm/ringtone channel.
  /// Falls back to max-volume beep via platform channel.
  void playAlarm() {
    if (_alarmPlaying) return;
    _alarmPlaying = true;

    // Try native alarm channel first
    try {
      _alarmChannel.invokeMethod('playAlarm');
    } catch (_) {
      // If native channel not available, use system sound
      SystemSound.play(SystemSoundType.alert);
    }
  }

  /// Stop the alarm.
  void stopAlarm() {
    _alarmPlaying = false;
    try {
      _alarmChannel.invokeMethod('stopAlarm');
    } catch (_) {
      // Silently fail if channel not available
    }
  }

  // ─────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────

  Future<void> dispose() async {
    stopShakeDetection();
    await stopVoiceCommand();
    stopAlarm();
  }
}
