import 'package:flutter_secure_storage/flutter_secure_storage.dart';

FlutterSecureStorage createSecureStorage() {
  return const FlutterSecureStorage(
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      usesDataProtectionKeychain: false,
    ),
  );
}
