// Console front end of the headless CLI (doc/cli-design.md). mqttstudio.exe is a GUI program, so a shell would not
// wait for it and would lose its exit code. This console program starts "mqttstudio.exe --cli <arguments>", waits for
// it and returns its exit code. Ctrl+C reaches the app through the shared console.
// The app's output goes through pipes and is copied to the launcher's own handles: Dart cannot write to a console
// from a GUI process (its writes never complete), while pipes work.
#include <windows.h>

#include <cstdio>
#include <string>
#include <thread>

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

// Length of the start of text that ends with a complete UTF-8 character, the rest waits for the next read.
size_t CompleteUtf8Length(const std::string& text) {
  size_t end = text.size();
  for (size_t back = 1; back <= 3 && back <= end; back++) {
    unsigned char byte = static_cast<unsigned char>(text[end - back]);
    if ((byte & 0xC0) == 0x80) {
      continue;
    }
    size_t needed = (byte & 0xE0) == 0xC0 ? 2 : (byte & 0xF0) == 0xE0 ? 3 : (byte & 0xF8) == 0xF0 ? 4 : 1;
    return back < needed ? end - back : end;
  }
  return end;
}

void WriteAll(HANDLE target, const char* data, DWORD length) {
  while (length > 0) {
    DWORD written = 0;
    if (!::WriteFile(target, data, length, &written, nullptr) || written == 0) {
      return;
    }
    data += written;
    length -= written;
  }
}

// Copies what the app writes to a pipe to one of the launcher's standard handles until the app closes the pipe. The
// app writes UTF-8, a console gets UTF-16 so the text shows correctly whatever its code page is.
void Relay(HANDLE pipe, HANDLE target) {
  DWORD mode = 0;
  bool console = ::GetConsoleMode(target, &mode) != 0;
  std::string pending;
  char buffer[4096];
  DWORD read = 0;
  while (::ReadFile(pipe, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
    if (!console) {
      WriteAll(target, buffer, read);
      continue;
    }
    pending.append(buffer, read);
    int complete = static_cast<int>(CompleteUtf8Length(pending));
    if (complete == 0) {
      continue;
    }
    int length = ::MultiByteToWideChar(CP_UTF8, 0, pending.data(), complete, nullptr, 0);
    std::wstring text(static_cast<size_t>(length), L'\0');
    ::MultiByteToWideChar(CP_UTF8, 0, pending.data(), complete, text.data(), length);
    DWORD written = 0;
    ::WriteConsoleW(target, text.data(), static_cast<DWORD>(text.size()), &written, nullptr);
    pending.erase(0, static_cast<size_t>(complete));
  }
  ::CloseHandle(pipe);
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
  // for --version, the app takes it off again
  command_line += L" --app-version=" WIDEN(FLUTTER_VERSION);
#endif
  for (int i = 1; i < argc; i++) {
    command_line += L" " + QuoteArgument(argv[i]);
  }

  // the app inherits the write ends, the launcher keeps the read ends
  SECURITY_ATTRIBUTES inheritable = {sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
  HANDLE out_read = nullptr, out_write = nullptr, err_read = nullptr, err_write = nullptr;
  if (!::CreatePipe(&out_read, &out_write, &inheritable, 0) || !::CreatePipe(&err_read, &err_write, &inheritable, 0)) {
    fwprintf(stderr, L"Cannot create the output pipes (error %lu)\n", ::GetLastError());
    return 1;
  }
  ::SetHandleInformation(out_read, HANDLE_FLAG_INHERIT, 0);
  ::SetHandleInformation(err_read, HANDLE_FLAG_INHERIT, 0);
  HANDLE input = ::GetStdHandle(STD_INPUT_HANDLE);
  if (input != nullptr && input != INVALID_HANDLE_VALUE) {
    ::SetHandleInformation(input, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  }

  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESTDHANDLES;
  startup_info.hStdInput = input;
  startup_info.hStdOutput = out_write;
  startup_info.hStdError = err_write;

  PROCESS_INFORMATION process_info = {};
  if (!::CreateProcessW(nullptr, command_line.data(), nullptr, nullptr, TRUE, 0, nullptr, nullptr, &startup_info,
                        &process_info)) {
    fwprintf(stderr, L"Cannot start %s (error %lu)\n", app_path.c_str(), ::GetLastError());
    return 1;
  }
  // only the app may hold the write ends, otherwise the pipes never report their end
  ::CloseHandle(out_write);
  ::CloseHandle(err_write);
  ::SetConsoleCtrlHandler(IgnoreCtrlEvent, TRUE);

  std::thread error_relay(Relay, err_read, ::GetStdHandle(STD_ERROR_HANDLE));
  Relay(out_read, ::GetStdHandle(STD_OUTPUT_HANDLE));
  error_relay.join();

  ::WaitForSingleObject(process_info.hProcess, INFINITE);
  DWORD exit_code = 1;
  ::GetExitCodeProcess(process_info.hProcess, &exit_code);
  ::CloseHandle(process_info.hThread);
  ::CloseHandle(process_info.hProcess);
  return static_cast<int>(exit_code);
}
