import 'dart:io';

import 'package:flutter/services.dart';

class WindowsBridge {
  static const _channel = MethodChannel('typeflux/desktop');
  bool get available => Platform.isWindows;
  Future<void> enable(Future<void> Function() toggle) async {
    if (!available) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'toggleDictation') await toggle();
    });
    await _channel.invokeMethod<void>('registerHotkey');
  }

  Future<bool> insert(String text) async {
    if (!available) return false;
    return await _channel.invokeMethod<bool>('insertText', {'text': text}) ??
        false;
  }

  Future<void> showStatus(String text) async {
    if (available) {
      await _channel.invokeMethod<void>('showStatus', {'text': text});
    }
  }

  Future<void> reset() async {
    if (available) await _channel.invokeMethod<void>('resetCapture');
  }

  Future<void> disable() async {
    if (!available) return;
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod<void>('unregisterHotkey');
  }
}
