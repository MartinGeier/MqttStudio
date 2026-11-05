#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include "flutter_window.h"
#include "run_loop.h"
#include "utils.h"

// Full HD when the work area of the monitor the window opens on has room for it, else HD. The sizes are logical
// pixels, Win32Window scales them with the DPI of that monitor.
Win32Window::Size InitialWindowSize(const Win32Window::Point& origin) {
  const Win32Window::Size full_hd(1920, 1080);
  const POINT target_point = {static_cast<LONG>(origin.x), static_cast<LONG>(origin.y)};
  HMONITOR monitor = ::MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  if (::GetMonitorInfo(monitor, &monitor_info)) {
    double scale_factor = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
    const RECT& work_area = monitor_info.rcWork;
    if ((origin.x + full_hd.width) * scale_factor <= work_area.right &&
        (origin.y + full_hd.height) * scale_factor <= work_area.bottom) {
      return full_hd;
    }
  }
  return Win32Window::Size(1280, 720);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  RunLoop run_loop;

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Started by the console launcher mqttstudio-cli.exe: the window stays hidden and Dart ends the process with the
  // exit code of the command.
  bool headless = !command_line_arguments.empty() && command_line_arguments[0] == "--cli";

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(&run_loop, project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size = InitialWindowSize(origin);
  if (!window.CreateAndShow(L"MQTT Studio", origin, size, !headless)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(!headless);

  run_loop.Run();

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
