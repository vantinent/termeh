import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:termeh/services/mac_local_store.dart';
import 'package:termeh/services/master_key_service.dart';

Future<void> _useIsolatedMacState() async {
  if (!Platform.isMacOS) return;

  final dir = await Directory.systemTemp.createTemp('termeh-test-');
  MacLocalStore.testBaseDirectoryPath = dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('A fresh macOS vault starts without a master key', () async {
    await _useIsolatedMacState();
    final service = MasterKeyService();

    expect(await service.hasMasterKey(), isFalse);
  });

  test('Clearing the unlock record disables grace-period bypass', () async {
    await _useIsolatedMacState();

    final service = MasterKeyService();
    await service.setMasterKey('secret123');

    expect(await service.canBypassUnlockPrompt(5), isTrue);

    await service.clearSuccessfulUnlockRecord();

    expect(await service.canBypassUnlockPrompt(5), isFalse);
  });

  test('Grace bypass ignores the stored unlock timestamp in-session', () async {
    await _useIsolatedMacState();

    final service = MasterKeyService();
    await service.setMasterKey('secret123');
    const storage = FlutterSecureStorage();

    await storage.write(
      key: 'master_key_last_unlock_at',
      value: '0',
    );

    expect(await service.canBypassUnlockPrompt(5), isTrue);

    await service.clearSuccessfulUnlockRecord();

    expect(await service.canBypassUnlockPrompt(5), isFalse);
  });
}
