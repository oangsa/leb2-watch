import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app icon suites use the branded master and adaptive Android icon', () {
    final master = File('assets/branding/app_icon_master.png');
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final foreground = File(
      'android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png',
    );

    expect(_pngSize(master), (1024, 1024));
    expect(_pngSize(foreground), (432, 432));
    expect(adaptive, contains('@color/ic_launcher_background'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));

    for (final path in <String>[
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png',
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      'windows/runner/resources/app_icon.ico',
    ]) {
      expect(File(path).lengthSync(), greaterThan(100));
    }
  });

  test('native launch surfaces follow light and dark app surfaces', () {
    final androidLaunch = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final androidLight = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    final androidDark = File(
      'android/app/src/main/res/values-night/colors.xml',
    ).readAsStringSync();
    final iOSLaunch = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    final iOSColors = File(
      'ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json',
    ).readAsStringSync();

    expect(androidLaunch, contains('@color/launch_background'));
    expect(androidLight, contains('#F7F8FC'));
    expect(androidDark, contains('#111319'));
    expect(iOSLaunch, contains('name="LaunchBackground"'));
    expect(iOSLaunch, isNot(contains('image="LaunchImage"')));
    expect(iOSColors, contains('"value" : "dark"'));
  });
}

(int, int) _pngSize(File file) {
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}
