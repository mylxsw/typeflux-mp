#ifndef TYPEFLUX_DICTATION_BRIDGE_H_
#define TYPEFLUX_DICTATION_BRIDGE_H_
#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>

class DictationBridge {
 public:
  DictationBridge(HWND window, flutter::BinaryMessenger* messenger);
  ~DictationBridge();
  bool HandleMessage(UINT message, WPARAM parameter);
 private:
  HWND window_;
  HWND overlay_ = nullptr;
  HWND target_ = nullptr;
  DWORD target_process_ = 0;
  bool registered_ = false;
  bool recording_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool Insert(const std::string& text);
};
#endif
