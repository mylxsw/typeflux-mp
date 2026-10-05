import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import 'realtime_endpoint.dart';
import 'transcript.dart';

enum VoicePhase { idle, starting, recording, finishing, failed }

class VoiceController extends ChangeNotifier {
  VoiceController(this.api);
  final TypefluxApi api;
  final _recorder = AudioRecorder();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _incoming;
  StreamSubscription<Uint8List>? _audio;
  Completer<void>? _closed;
  Transcript transcript = Transcript();
  VoicePhase phase = VoicePhase.idle;
  String? error;
  bool _disposed = false, _stopping = false;
  int _generation = 0;
  bool get active => [
    VoicePhase.starting,
    VoicePhase.recording,
    VoicePhase.finishing,
  ].contains(phase);
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> start({String scenario = 'ask-anything'}) async {
    if (active) return;
    final generation = ++_generation;
    transcript = Transcript();
    error = null;
    phase = VoicePhase.starting;
    _stopping = false;
    notifyListeners();
    try {
      if (!await _recorder.hasPermission()) {
        throw const ApiError('MICROPHONE_DENIED');
      }
      if (generation != _generation) return;
      final ticket = await api.request(
        'POST',
        '/asr/token',
        scenario: scenario,
      ) as Map<String, dynamic>;
      if (generation != _generation) return;
      final origins = (ticket['server'] as List).cast<String>();
      if (origins.isEmpty) throw const ApiError('ASR_UNAVAILABLE');
      WebSocket? socket;
      for (final origin in origins) {
        try {
          socket = await WebSocket.connect(
            realtimeWebSocketUri(origin).toString(),
            headers: {'Authorization': 'Bearer ${ticket['token']}'},
          ).timeout(const Duration(seconds: 12));
          break;
        } catch (_) {
          /* Fail over before any audio has been transmitted. */
        }
      }
      if (socket == null) throw const ApiError('ASR_UNAVAILABLE');
      if (generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      _closed = Completer<void>();
      _incoming = socket.listen(
        (dynamic raw) {
          if (generation != _generation) return;
          try {
            final event = jsonDecode(raw as String) as Map<String, dynamic>;
            if (event['type'] == 'error') {
              error = 'ASR_FAILED';
              unawaited(cancel(failed: true));
              return;
            }
            transcript.accept(event);
            notifyListeners();
          } catch (_) {
            error = 'ASR_FAILED';
            unawaited(cancel(failed: true));
          }
        },
        onDone: () {
          if (!(_closed?.isCompleted ?? true)) _closed!.complete();
          if (!_stopping && generation == _generation) {
            error = 'ASR_INTERRUPTED';
            unawaited(cancel(failed: true));
          }
        },
        onError: (Object _) {
          if (generation == _generation) {
            error = 'ASR_FAILED';
            unawaited(cancel(failed: true));
          }
        },
      );
      socket.add(
        jsonEncode({
          'type': 'start',
          'config': {
            'audio': {
              'format': 'pcm',
              'sample_rate': 16000,
              'channel': 1,
              'lang': 'auto',
            },
            'input_mode': 'realtime',
          },
        }),
      );
      final audio = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      if (generation != _generation) {
        await _recorder.stop();
        return;
      }
      _audio = audio.listen(
        (bytes) {
          if (generation == _generation) socket!.add(bytes);
        },
        onError: (Object _) {
          error = 'MICROPHONE_FAILED';
          unawaited(cancel(failed: true));
        },
      );
      phase = VoicePhase.recording;
      notifyListeners();
    } catch (e) {
      if (generation == _generation) {
        error = e is ApiError ? e.code : 'ASR_FAILED';
        await cancel(failed: true);
      }
    }
  }

  Future<String?> stop() async {
    if (phase != VoicePhase.recording) return null;
    final generation = _generation;
    _stopping = true;
    phase = VoicePhase.finishing;
    notifyListeners();
    try {
      await _recorder.stop();
      await _audio?.cancel();
      _audio = null;
      _socket?.add(jsonEncode({'type': 'stop'}));
      await _closed!.future.timeout(const Duration(seconds: 20));
      if (generation != _generation) return null;
      if (!transcript.hasFinal || transcript.partial.isNotEmpty) {
        throw const ApiError('ASR_INCOMPLETE');
      }
      final result = transcript.committed;
      await cancel();
      return result;
    } catch (e) {
      if (generation == _generation) {
        error = e is ApiError ? e.code : 'ASR_INCOMPLETE';
        await cancel(failed: true);
      }
      return null;
    }
  }

  Future<void> cancel({bool failed = false}) async {
    _generation++;
    _stopping = true;
    await _audio?.cancel();
    _audio = null;
    await _recorder.stop();
    await _incoming?.cancel();
    _incoming = null;
    await _socket?.close();
    _socket = null;
    if (!(_closed?.isCompleted ?? true)) _closed!.complete();
    phase = failed ? VoicePhase.failed : VoicePhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel().whenComplete(_recorder.dispose));
    super.dispose();
  }
}
