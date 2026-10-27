#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// Hosts the Flutter view and the desktop shell: tray icon, close-to-tray,
// selection hotkey, lookup popup and start with Windows. Dart drives it over
// the "vocabapp/desktop" channel.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Keeps the window hidden after the first frame (launch at sign-in).
  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }

  // Message another instance posts to bring this one to the front.
  static UINT ShowMessage();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Notify(const std::string& method, flutter::EncodableValue value = {});
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void ShowHint();
  void ShowMain();
  void ShowPopup(int width, int height);
  void EndPopup(bool show);
  bool RegisterSelectionHotkey(UINT key);
  void Quit();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  HWND hwnd_ = nullptr;
  bool start_hidden_ = false;
  bool quitting_ = false;
  bool hint_shown_ = false;
  bool popup_ = false;
  bool was_visible_ = false;
  WINDOWPLACEMENT placement_{};
  UINT hotkey_ = 0;
  HICON tray_icon_ = nullptr;
  UINT taskbar_created_ = 0;
  std::wstring open_label_ = L"Open VocabApp";
  std::wstring quit_label_ = L"Quit";
  std::wstring hint_title_ = L"VocabApp is still running";
  std::wstring hint_text_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
