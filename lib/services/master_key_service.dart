import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'mac_local_store.dart';
import 'pbkdf2_utils.dart';
import 'secure_storage_factory.dart';
import 'unlock_grace_tracker.dart';

class MasterKeyService {
  MasterKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? createSecureStorage();

  final FlutterSecureStorage _storage;
  static String? _macUnlockedMasterKey;

  static const _keySalt = 'master_key_salt';
  static const _keyVerifier = 'master_key_verifier';
  static const _keyIterations = 'master_key_iterations';
  static const _keyLastSuccessfulUnlockAt = 'master_key_last_unlock_at';
  static const _iterations = 210000;
  static const _saltLength = 32;
  static const _hashLength = 32;

  static String? get macUnlockedMasterKey => _macUnlockedMasterKey;

  static void clearMacUnlockedMasterKey() {
    _macUnlockedMasterKey = null;
  }

  Future<bool> hasMasterKey() async {
    if (Platform.isMacOS) {
      return MacLocalStore.instance.hasMasterKey();
    }
    final salt = await _storage.read(key: _keySalt);
    final verifier = await _storage.read(key: _keyVerifier);
    return salt != null && verifier != null;
  }

  Future<void> setMasterKey(String masterKey) async {
    if (Platform.isMacOS) {
      await MacLocalStore.instance.setMasterKey(masterKey);
      _macUnlockedMasterKey = masterKey;
      await recordSuccessfulUnlock();
      return;
    }
    final salt = _createSalt();
    final verifier = deriveKeyBytes(masterKey, salt, _iterations, _hashLength);

    await _storage.write(key: _keySalt, value: base64Encode(salt));
    await _storage.write(key: _keyVerifier, value: base64Encode(verifier));
    await _storage.write(key: _keyIterations, value: _iterations.toString());
    await recordSuccessfulUnlock();
  }

  Future<bool> verifyMasterKey(String masterKey) async {
    try {
      if (Platform.isMacOS) {
        final verified =
            await MacLocalStore.instance.verifyMasterKey(masterKey);
        if (verified) {
          _macUnlockedMasterKey = masterKey;
        }
        return verified;
      }
      final saltValue = await _storage.read(key: _keySalt);
      final verifierValue = await _storage.read(key: _keyVerifier);
      if (saltValue == null || verifierValue == null) return false;

      final iterationsValue = await _storage.read(key: _keyIterations);
      final iterations = int.tryParse(iterationsValue ?? '') ?? _iterations;
      final salt = base64Decode(saltValue);
      final verifier = base64Decode(verifierValue);
      final candidate =
          deriveKeyBytes(masterKey, salt, iterations, verifier.length);

      return _constantTimeEquals(candidate, verifier);
    } catch (e) {
      debugPrint('Error verifying master key: $e');
      return false;
    }
  }

  Future<bool> changeMasterKey(
    String currentKey,
    String newKey, {
    Future<void> Function(String currentKey, String newKey)? onMacVaultMigrated,
  }) async {
    if (Platform.isMacOS) {
      final changed = await MacLocalStore.instance.verifyMasterKey(currentKey);
      if (!changed) return false;
      try {
        if (onMacVaultMigrated != null) {
          await onMacVaultMigrated(currentKey, newKey);
        }
        await MacLocalStore.instance.setMasterKey(newKey);
        _macUnlockedMasterKey = newKey;
        return true;
      } catch (e) {
        debugPrint('Error changing macOS master key: $e');
        return false;
      }
    }
    final verified = await verifyMasterKey(currentKey);
    if (!verified) return false;
    await setMasterKey(newKey);
    return true;
  }

  Future<void> recordSuccessfulUnlock() async {
    if (Platform.isMacOS) {
      await MacLocalStore.instance.recordSuccessfulUnlock();
    } else {
      await _storage.write(
        key: _keyLastSuccessfulUnlockAt,
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      );
    }
    UnlockGraceTracker.markUnlocked();
  }

  Future<void> clearSuccessfulUnlockRecord() async {
    UnlockGraceTracker.clear();
    if (Platform.isMacOS) {
      await MacLocalStore.instance.clearSuccessfulUnlockRecord();
      return;
    }
    await _storage.delete(key: _keyLastSuccessfulUnlockAt);
  }

  Future<DateTime?> getLastSuccessfulUnlockAt() async {
    try {
      if (Platform.isMacOS) {
        return MacLocalStore.instance.getLastSuccessfulUnlockAt();
      }
      final value = await _storage.read(key: _keyLastSuccessfulUnlockAt);
      final millis = int.tryParse(value ?? '');
      if (millis == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (e) {
      debugPrint('Error reading last successful unlock time: $e');
      return null;
    }
  }

  Future<bool> canBypassUnlockPrompt(int gracePeriodMinutes) async {
    if (gracePeriodMinutes <= 0) return false;
    if (!await hasMasterKey()) return false;
    return UnlockGraceTracker.canBypass(gracePeriodMinutes);
  }

  Uint8List _createSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => random.nextInt(256)),
    );
  }

  Uint8List deriveKeyBytes(
    String password,
    List<int> salt,
    int iterations,
    int length,
  ) {
    return derivePbkdf2Sha256Key(password, salt, iterations, length);
  }

  bool _constantTimeEquals(List<int> a, List<int> b) =>
      constantTimeEquals(a, b);

  Future<bool> hasCompletedMacSetup() async {
    if (!Platform.isMacOS) return true;
    return MacLocalStore.instance.isSetupCompleted();
  }

  Future<bool> hasMacVaultData() async {
    if (!Platform.isMacOS) return false;
    return MacLocalStore.instance.hasVault();
  }

  Future<void> resetStaleMacSetup() async {
    if (!Platform.isMacOS) return;
    await MacLocalStore.instance.resetStaleMacSetup();
    clearMacUnlockedMasterKey();
  }
}
