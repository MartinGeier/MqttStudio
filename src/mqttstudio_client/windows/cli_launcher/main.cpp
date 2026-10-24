// Console front end of the headless CLI (doc/cli-design.md). mqttstudio.exe is a GUI program, so a shell would not
// wait for it and would lose its exit code. This console program starts "mqttstudio.exe --cli <arguments>" with its
// own standard handles, waits for it and returns its exit code. Ctrl+C reaches the app through the shared console.
#include <windows.h>

#include <cstdio>
#include <string>

#define WIDEN_LITERAL(text) L##text
#define WIDEN(text) WIDEN_LITERAL(text)

namespace {

// Quotes an argument so CommandLineToArgvW in the app splits it back the same way.
std::wstring QuoteArgument(const std::wstring& argument) {
  if (!argument.empty() && argument.find_first_of(L" \t\n\v\"") == std::wstring::npos) {
    return argument;
  }
  std::wstring quoted = L"\"";
  for (auto it = argument.begin();; ++it) {
    size_t backslashes = 0;
    while (it != argument.end() && *it == L'\\') {
      ++it;
      ++backslashes;
    }
    if (it == argument.end()) {
      quoted.append(backslashes * 2, L'\\');
      break;
    }
    if (*it == L'"') {
      quoted.append(backslashes * 2 + 1, L'\\');
    } else {
      quoted.append(backslashes, L'\\');
    }
    quoted.push_back(*it);
  }
  quoted.push_back(L'"');
  return quoted;
}

// The app handles Ctrl+C itself and ends with an exit code, the launcher only waits for it.
BOOL WINAPI IgnoreCtrlEvent(DWORD) {
  return TRUE;
}

void MakeInheritable(DWORD std_handle) {
  HANDLE handle = ::GetStdHandle(std_handle);
  if (handle != nullptr && handle != INVALID_HANDLE_VALUE) {
    ::SetHandleInformation(handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  }
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  wchar_t module_path[MAX_PATH];
  DWORD length = ::GetModuleFileNameW(nullptr, module_path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    fwprintf(stderr, L"Cannot find the MQTT Studio folder\n");
    return 1;
  }
  std::wstring app_path(module_path, length);
  app_path = app_path.substr(0, app_path.find_last_of(L"\\/") + 1) + L"mqttstudio.exe";

  std::wstring command_line = QuoteArgument(app_path) + L" --cli";
#ifdef FLUTTER_VERSION
  // for --version, the app takes it off again. The Flutter engine reads the real command line of the app, so the
  // runner cannot add it.
  command_line += L" --app-version=" WIDEN(FLUTTER_VERSION);
#endif
  for (int i = 1; i < argc; i++) {
    command_line += L" " + QuoteArgument(argv[i]);
  }

  MakeInheritable(STD_INPUT_HANDLE);
  MakeInheritable(STD_OUTPUT_HANDLE);
  MakeInheritable(STD_ERROR_HANDLE);

  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESTDHANDLES;
  startup_info.hStdInput = ::GetStdHandle(STD_INPUT_HANDLE);
  startup_info.hStdOutput = ::GetStdHandle(STD_OUTPUT_HANDLE);
  startup_info.hStdError = ::GetStdHandle(STD_ERROR_HANDLE);

  PROCESS_INFORMATION process_info = {};
  if (!::CreateProcessW(nullptr, command_line.data(), nullptr, nullptr, TRUE, 0, nullptr, nullptr, &startup_info,
                        &process_info)) {
    fwprintf(stderr, L"Cannot start %s (error %lu)\n", app_path.c_str(), ::GetLastError());
    return 1;
  }
  ::SetConsoleCtrlHandler(IgnoreCtrlEvent, TRUE);

  ::WaitForSingleObject(process_info.hProcess, INFINITE);
  DWORD exit_code = 1;
  ::GetExitCodeProcess(process_info.hProcess, &exit_code);
  ::CloseHandle(process_info.hThread);
  ::CloseHandle(process_info.hProcess);
  return static_cast<int>(exit_code);
}
