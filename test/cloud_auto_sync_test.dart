import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/cloud_storage/cloud_profiles.dart';

void main() {
  test('explicit cloud switch overrides a still-enabled legacy switch', () {
    expect(
      cloudAutoSyncEnabled({'cloudAutoSync': false, 'webdavAutoSync': true}),
      false,
    );
    expect(
      cloudAutoSyncEnabled({'cloudAutoSync': true, 'webdavAutoSync': false}),
      true,
    );
  });
  test('old installations still use the legacy automatic sync switch', () {
    expect(cloudAutoSyncEnabled({'webdavAutoSync': true}), true);
    expect(cloudAutoSyncEnabled({}), false);
  });
}
