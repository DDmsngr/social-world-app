import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/update/update_policy.dart';

void main() {
  test('без разрешения качаем только по Wi-Fi', () {
    expect(UpdatePolicy.shouldAutoDownload(onWifi: true, allowMobile: false), isTrue);
    expect(UpdatePolicy.shouldAutoDownload(onWifi: false, allowMobile: false), isFalse);
    expect(UpdatePolicy.shouldAutoDownload(onWifi: false, allowMobile: true), isTrue);
  });

  test('старые APK удаляются, ждущий установки и чужие файлы — нет', () {
    final stale = UpdatePolicy.staleApks([
      '/files/social-world-5071.apk',
      '/files/social-world-5135-arm64.apk',
      '/files/social-world-5151.apk',
      '/files/mapkit',
      '/files/notes.apk',
    ], keep: '/files/social-world-5151.apk');
    expect(stale, ['/files/social-world-5071.apk', '/files/social-world-5135-arm64.apk']);
  });
}
