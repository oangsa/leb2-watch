import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktop native configuration', () {
    test('Linux reuses its unique GApplication window', () {
      final source = File('linux/runner/my_application.cc').readAsStringSync();

      expect(source, contains('GtkWindow* window;'));
      expect(source, contains('gtk_window_present(self->window);'));
      expect(source, contains('"application-id", APPLICATION_ID'));
      expect(source, contains('G_APPLICATION_DEFAULT_FLAGS'));
      expect(source, isNot(contains('G_APPLICATION_NON_UNIQUE')));
      expect(source, isNot(contains('socket')));
      expect(source, isNot(contains('daemon')));
    });

    test('Windows uses a safe fallback and one instance per session', () {
      final main = File('windows/runner/main.cpp').readAsStringSync();
      final header = File('windows/runner/win32_window.h').readAsStringSync();
      final implementation = File(
        'windows/runner/win32_window.cpp',
      ).readAsStringSync();

      expect(main, contains('Local\\\\dev.oangsa.leb2watch.instance.v1'));
      expect(main, contains('::CreateMutexW'));
      expect(main, contains('ERROR_ALREADY_EXISTS'));
      expect(main, contains('::FindWindowW(Win32Window::GetWindowClassName()'));
      expect(main, contains('::ShowWindow(existing_window, SW_RESTORE)'));
      expect(main, contains('::SetForegroundWindow(existing_window)'));
      expect(main, contains('window.SetQuitOnClose(true)'));
      expect(main, isNot(contains('window.SetQuitOnClose(false)')));
      expect(main, contains('::CloseHandle(instance_mutex)'));
      expect(
        main.indexOf('::CreateMutexW'),
        lessThan(main.indexOf('flutter::DartProject')),
      );
      expect(header, contains('static const wchar_t* GetWindowClassName();'));
      expect(implementation, contains('LEB2WATCH_MAIN_WINDOW_V1'));
      expect(main, isNot(contains('HKEY_LOCAL_MACHINE')));
      expect(main, isNot(contains('CreateService')));
      expect(main, isNot(contains('CreateTimerQueue')));
    });

    test('Windows CI compiles the complete unpackaged Release directory', () {
      final workflow = File('.github/workflows/ci.yml').readAsStringSync();

      expect(workflow, contains('windows-build:'));
      expect(workflow, contains('runs-on: windows-2022'));
      expect(workflow, contains('flutter-version: \'3.44.8\''));
      expect(workflow, contains('flutter config --enable-windows-desktop'));
      expect(workflow, contains('flutter doctor -v'));
      expect(
        workflow,
        contains('Microsoft.VisualStudio.Component.VC.Tools.x86.x64'),
      );
      expect(workflow, contains('Microsoft.VisualStudio.Component.VC.ATL'));
      expect(workflow, contains('flutter build windows --release'));
      expect(workflow, contains('--dart-define=APP_ENV=production'));
      expect(
        workflow,
        contains('--dart-define=BACKEND_BASE_URL=https://api.example.org'),
      );
      expect(
        workflow,
        contains("Test-Path 'build/windows/x64/runner/Release'"),
      );
      expect(workflow, isNot(contains('secrets.')));
    });

    test('macOS keeps tray lifecycle and pins legacy start-at-login', () {
      final delegate = File(
        'macos/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final window = File(
        'macos/Runner/MainFlutterWindow.swift',
      ).readAsStringSync();
      final info = File('macos/Runner/Info.plist').readAsStringSync();
      final menu = File(
        'macos/Runner/Base.lproj/MainMenu.xib',
      ).readAsStringSync();
      final project = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final debugEntitlements = File(
        'macos/Runner/DebugProfile.entitlements',
      ).readAsStringSync();
      final releaseEntitlements = File(
        'macos/Runner/Release.entitlements',
      ).readAsStringSync();

      expect(
        delegate,
        contains(
          'applicationShouldTerminateAfterLastWindowClosed'
          '(_ sender: NSApplication) -> Bool {\n'
          '    return false',
        ),
      );
      expect(delegate, contains('applicationShouldHandleReopen'));
      expect(delegate, contains('sender.windows.first?.makeKeyAndOrderFront'));
      expect(delegate, contains('@IBAction func openSettings'));
      expect(delegate, contains('name: "app_navigation"'));
      expect(delegate, contains('invokeMethod("openSettings"'));
      expect(menu, contains('title="Settings…" keyEquivalent=","'));
      expect(menu, contains('selector="openSettings:"'));
      expect(info, contains('<key>LSMultipleInstancesProhibited</key>'));
      expect(info, contains('<true/>'));
      expect(window, contains('import LaunchAtLogin'));
      expect(window, contains('FlutterMethodChannel('));
      expect(window, contains('name: "launch_at_startup"'));
      expect(window, contains('launchAtStartupIsEnabled'));
      expect(window, contains('launchAtStartupSetEnabled'));
      expect(window, contains('setEnabledValue'));
      expect(
        project,
        contains('https://github.com/sindresorhus/LaunchAtLogin-Legacy'),
      );
      expect(project, contains('kind = exactVersion;'));
      expect(project, contains('version = 5.0.2;'));
      expect(project, contains('productName = LaunchAtLogin;'));
      expect(project, contains('copy-helper-swiftpm.sh'));
      expect(project, contains('ENABLE_USER_SCRIPT_SANDBOXING = NO;'));
      expect(project, contains('MACOSX_DEPLOYMENT_TARGET = 10.15;'));
      expect(
        project.indexOf('33CC10EB2044A3C60003C045 /* Resources */'),
        lessThan(project.indexOf('Copy LaunchAtLogin Helper')),
      );
      expect(
        debugEntitlements,
        contains('<key>com.apple.security.app-sandbox</key>'),
      );
      expect(
        debugEntitlements,
        contains(
          '<key>com.apple.security.network.client</key>\n'
          '\t<true/>',
        ),
      );
      expect(
        debugEntitlements,
        contains(
          '<key>com.apple.security.network.server</key>\n'
          '\t<true/>',
        ),
      );
      expect(
        debugEntitlements,
        contains(
          '<key>com.apple.security.cs.allow-jit</key>\n'
          '\t<true/>',
        ),
      );
      expect(
        releaseEntitlements,
        contains('<key>com.apple.security.app-sandbox</key>'),
      );
      expect(
        releaseEntitlements,
        contains(
          '<key>com.apple.security.network.client</key>\n'
          '\t<true/>',
        ),
      );
      expect(
        releaseEntitlements,
        isNot(contains('com.apple.security.network.server')),
      );
      expect(
        releaseEntitlements,
        isNot(contains('com.apple.security.cs.allow-jit')),
      );
    });

    test('tray asset files use the expected native formats', () {
      final linux = File(
        'assets/desktop/tray_icon_linux.png',
      ).readAsBytesSync();
      final macOS = File(
        'assets/desktop/tray_icon_macos.png',
      ).readAsBytesSync();
      final windows = File(
        'assets/desktop/tray_icon_windows.ico',
      ).readAsBytesSync();
      const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

      expect(linux.take(8), pngSignature);
      expect(macOS.take(8), pngSignature);
      expect(windows.take(6), [0, 0, 1, 0, 5, 0]);
      expect(_pngSize(linux), (64, 64));
      expect(_pngSize(macOS), (36, 36));
    });
  });
}

(int, int) _pngSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}
