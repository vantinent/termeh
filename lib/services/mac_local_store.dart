import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../models/ssh_connection.dart';
import '../theme/adwaita_theme.dart';
import 'pbkdf2_utils.dart';
import 'unlock_grace_tracker.dart';

class MacLocalStore {
  MacLocalStore._();

  static final MacLocalStore instance = MacLocalStore._();
  static String? testBaseDirectoryPath;

  static const _settingsFileName = 'settings.json';
  static const _masterFileName = 'master.json';
  static const _vaultFileName = 'connections.vault';
  static const _stateFileName = 'state.json';
  static const _masterIterations = 210000;
  static const _kdfIterations = 210000;
  static const _saltLength = 32;
  static const _keyLength = 32;
  static const _masterFormat = 'termeh-master-metadata';
  static const _vaultFormat = 'termeh-mac-vault';

  Directory get _baseDirectory {
    final overridePath = testBaseDirectoryPath;
    if (overridePath != null && overridePath.isNotEmpty) {
      return Directory(overridePath);
    }

    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is not set.');
    }
    return Directory('$home/Library/Application Support/Termeh');
  }

  File get _settingsFile => File('${_baseDirectory.path}/$_settingsFileName');
  File get _masterFile => File('${_baseDirectory.path}/$_masterFileName');
  File get _vaultFile => File('${_baseDirectory.path}/$_vaultFileName');
  File get _stateFile => File('${_baseDirectory.path}/$_stateFileName');

  Future<void> _ensureDirectory() async {
    await _baseDirectory.create(recursive: true);
  }

  Future<Map<String, dynamic>> _readJsonFile(
    File file, {
    Map<String, dynamic> fallback = const {},
  }) async {
    try {
      if (!await file.exists()) return Map<String, dynamic>.from(fallback);
      final contents = await file.readAsString();
      final decoded = json.decode(contents);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return Map<String, dynamic>.from(fallback);
    } catch (e) {
      debugPrint('Error reading ${file.path}: $e');
      return Map<String, dynamic>.from(fallback);
    }
  }

  Future<void> _writeJsonFile(File file, Map<String, dynamic> value) async {
    await _ensureDirectory();
    await file.writeAsString(
      json.encode(value),
      flush: true,
    );
  }

  Future<Map<String, dynamic>> _readSettings() async {
    return _readJsonFile(_settingsFile);
  }

  Future<void> _writeSettings(Map<String, dynamic> value) async {
    await _writeJsonFile(_settingsFile, value);
  }

  Future<Map<String, dynamic>> _readMasterMetadata() async {
    return _readJsonFile(_masterFile);
  }

  Future<void> _writeMasterMetadata(Map<String, dynamic> value) async {
    await _writeJsonFile(_masterFile, value);
  }

  Future<Map<String, dynamic>> _readState() async {
    return _readJsonFile(_stateFile);
  }

  Future<void> _writeState(Map<String, dynamic> value) async {
    await _writeJsonFile(_stateFile, value);
  }

  Future<Map<String, dynamic>?> _readVault() async {
    try {
      if (!await _vaultFile.exists()) return null;
      final contents = await _vaultFile.readAsString();
      final decoded = json.decode(contents);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (e) {
      debugPrint('Error reading macOS vault: $e');
      return null;
    }
  }

  Future<void> _writeVault(Map<String, dynamic> value) async {
    await _writeJsonFile(_vaultFile, value);
  }

  Future<Uint8List> _deriveKey(
    String masterKey,
    List<int> salt, {
    int iterations = _kdfIterations,
  }) async {
    return derivePbkdf2Sha256Key(masterKey, salt, iterations, _keyLength);
  }

  Future<List<SshConnection>> _decryptConnections(
    Map<String, dynamic> payload,
    String masterKey,
  ) async {
    final saltText = payload['salt'] as String?;
    final nonceText = payload['nonce'] as String?;
    final ciphertextText = payload['ciphertext'] as String?;
    final macText = payload['mac'] as String?;
    final iterations =
        int.tryParse('${payload['iterations']}') ?? _kdfIterations;

    if (saltText == null ||
        nonceText == null ||
        ciphertextText == null ||
        macText == null) {
      return [];
    }

    final salt = base64Decode(saltText);
    final keyMaterial = await _deriveKey(
      masterKey,
      salt,
      iterations: iterations,
    );
    final algorithm = AesGcm.with256bits();
    final secretBox = SecretBox(
      base64Decode(ciphertextText),
      nonce: base64Decode(nonceText),
      mac: Mac(base64Decode(macText)),
    );

    late final List<int> plaintextBytes;
    try {
      plaintextBytes = await algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(keyMaterial),
      );
    } catch (_) {
      return [];
    }

    final decoded = json.decode(utf8.decode(plaintextBytes));
    final entries =
        decoded is Map<String, dynamic> ? decoded['connections'] : decoded;
    if (entries is! List) return [];

    return entries.whereType<Map>().map((entry) {
      final map = Map<String, dynamic>.from(entry);
      return SshConnection.fromMap(map).copyWith(
        password: map['password'] as String?,
      );
    }).toList();
  }

  Future<Map<String, dynamic>> _encryptConnections(
    List<SshConnection> connections,
    String masterKey, {
    int iterations = _kdfIterations,
  }) async {
    final plaintext = json.encode({
      'version': 1,
      'connections': connections
          .map(
            (connection) => {
              ...connection.toMap(),
              'password': connection.password,
            },
          )
          .toList(),
    });

    final algorithm = AesGcm.with256bits();
    final salt = _randomBytes(_saltLength);
    final nonce = algorithm.newNonce();
    final keyMaterial = await _deriveKey(
      masterKey,
      salt,
      iterations: iterations,
    );
    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(keyMaterial),
      nonce: nonce,
    );

    return {
      'format': _vaultFormat,
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  Future<bool> hasMasterKey() async {
    final metadata = await _readMasterMetadata();
    final format = metadata['format'] as String?;
    final version = int.tryParse('${metadata['version']}');
    return format == _masterFormat &&
        version == 1 &&
        metadata['salt'] is String &&
        metadata['verifier'] is String;
  }

  Future<bool> hasVault() async {
    return _vaultFile.exists();
  }

  Future<bool> isSetupCompleted() async {
    final state = await _readState();
    return state['setupCompleted'] == true;
  }

  Future<void> markSetupCompleted() async {
    final state = await _readState();
    state['setupCompleted'] = true;
    await _writeState(state);
  }

  Future<void> clearSetupCompleted() async {
    final state = await _readState();
    state.remove('setupCompleted');
    if (state.isEmpty) {
      if (await _stateFile.exists()) {
        await _stateFile.delete();
      }
      return;
    }
    await _writeState(state);
  }

  Future<void> resetStaleMacSetup() async {
    if (await _masterFile.exists()) {
      await _masterFile.delete();
    }
    if (await _vaultFile.exists()) {
      await _vaultFile.delete();
    }
    await clearSetupCompleted();
  }

  Future<void> setMasterKey(String masterKey) async {
    final salt = _randomBytes(_saltLength);
    final verifier =
        derivePbkdf2Sha256Key(masterKey, salt, _masterIterations, _keyLength);

    await _writeMasterMetadata({
      'format': _masterFormat,
      'version': 1,
      'salt': base64Encode(salt),
      'verifier': base64Encode(verifier),
      'iterations': _masterIterations,
      'lastSuccessfulUnlockAt': DateTime.now().millisecondsSinceEpoch,
    });
    await markSetupCompleted();
  }

  Future<bool> verifyMasterKey(String masterKey) async {
    try {
      final metadata = await _readMasterMetadata();
      final saltText = metadata['salt'] as String?;
      final verifierText = metadata['verifier'] as String?;
      if (saltText == null || verifierText == null) return false;

      final iterations =
          int.tryParse('${metadata['iterations']}') ?? _masterIterations;
      final salt = base64Decode(saltText);
      final verifier = base64Decode(verifierText);
      final candidate =
          derivePbkdf2Sha256Key(masterKey, salt, iterations, verifier.length);
      return constantTimeEquals(candidate, verifier);
    } catch (e) {
      debugPrint('Error verifying macOS master key: $e');
      return false;
    }
  }

  Future<void> recordSuccessfulUnlock() async {
    final metadata = await _readMasterMetadata();
    if (metadata.isEmpty) return;
    metadata['lastSuccessfulUnlockAt'] = DateTime.now().millisecondsSinceEpoch;
    await _writeMasterMetadata(metadata);
    UnlockGraceTracker.markUnlocked();
  }

  Future<void> clearSuccessfulUnlockRecord() async {
    UnlockGraceTracker.clear();
    final metadata = await _readMasterMetadata();
    if (metadata.isEmpty) return;
    metadata.remove('lastSuccessfulUnlockAt');
    await _writeMasterMetadata(metadata);
  }

  Future<DateTime?> getLastSuccessfulUnlockAt() async {
    try {
      final metadata = await _readMasterMetadata();
      final millis = int.tryParse('${metadata['lastSuccessfulUnlockAt']}');
      if (millis == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (e) {
      debugPrint('Error reading macOS unlock time: $e');
      return null;
    }
  }

  Future<bool> canBypassUnlockPrompt(int gracePeriodMinutes) async {
    if (gracePeriodMinutes <= 0) return false;
    if (!await hasMasterKey()) return false;
    return UnlockGraceTracker.canBypass(gracePeriodMinutes);
  }

  Future<List<SshConnection>> getConnections(String masterKey) async {
    final payload = await _readVault();
    if (payload == null) return [];
    return _decryptConnections(payload, masterKey);
  }

  Future<void> saveConnections(
    List<SshConnection> connections,
    String masterKey,
  ) async {
    final payload = await _encryptConnections(connections, masterKey);
    await _writeVault(payload);
  }

  Future<void> addConnection(
    SshConnection connection,
    String masterKey,
  ) async {
    final connections = await getConnections(masterKey);
    connections.removeWhere((e) => e.id == connection.id);
    connections.add(connection);
    await saveConnections(connections, masterKey);
  }

  Future<void> deleteConnection(String id, String masterKey) async {
    final connections = await getConnections(masterKey);
    connections.removeWhere((element) => element.id == id);
    await saveConnections(connections, masterKey);
  }

  Future<void> updateConnection(
    SshConnection connection,
    String masterKey,
  ) async {
    final connections = await getConnections(masterKey);
    final index = connections.indexWhere((e) => e.id == connection.id);
    if (index != -1) {
      connections[index] = connection;
      await saveConnections(connections, masterKey);
    }
  }

  Future<void> migrateConnections(
    String oldMasterKey,
    String newMasterKey,
  ) async {
    final connections = await getConnections(oldMasterKey);
    await saveConnections(connections, newMasterKey);
  }

  Future<String> exportConnectionsEncrypted(
    List<SshConnection> connections,
    String masterKey,
  ) async {
    final payload = await _encryptConnections(
      connections,
      masterKey,
      iterations: _kdfIterations,
    );
    payload['format'] = 'termeh-encrypted-server-list';
    payload['exportedAt'] = DateTime.now().toUtc().toIso8601String();
    return json.encode(payload);
  }

  Future<void> importConnectionsEncrypted(
    String contents,
    String masterKey,
  ) async {
    final decoded = json.decode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid encrypted server list file.');
    }

    final connections = await _decryptConnections(decoded, masterKey);
    if (connections.isEmpty && decoded['ciphertext'] != null) {
      throw const FormatException('Incorrect master key or corrupted file.');
    }

    await saveConnections(connections, masterKey);
  }

  Future<double> getFontSize() async {
    final value = await _readSettings();
    return double.tryParse('${value['fontSize']}') ?? 17.0;
  }

  Future<void> saveFontSize(double fontSize) async {
    final value = await _readSettings();
    value['fontSize'] = fontSize;
    await _writeSettings(value);
  }

  Future<int> getBackgroundColor() async {
    final value = await _readSettings();
    return int.tryParse('${value['backgroundColor']}') ??
        AdwaitaColors.darkView.toARGB32();
  }

  Future<void> saveBackgroundColor(int color) async {
    final value = await _readSettings();
    value['backgroundColor'] = color;
    await _writeSettings(value);
  }

  Future<double> getWindowWidth() async {
    final value = await _readSettings();
    return double.tryParse('${value['windowWidth']}') ?? 1000.0;
  }

  Future<void> saveWindowWidth(double width) async {
    final value = await _readSettings();
    value['windowWidth'] = width;
    await _writeSettings(value);
  }

  Future<double> getWindowHeight() async {
    final value = await _readSettings();
    return double.tryParse('${value['windowHeight']}') ?? 700.0;
  }

  Future<void> saveWindowHeight(double height) async {
    final value = await _readSettings();
    value['windowHeight'] = height;
    await _writeSettings(value);
  }

  Future<int> getMasterUnlockGraceMinutes() async {
    final value = await _readSettings();
    return int.tryParse('${value['masterUnlockGraceMinutes']}') ?? 0;
  }

  Future<void> saveMasterUnlockGraceMinutes(int minutes) async {
    final value = await _readSettings();
    value['masterUnlockGraceMinutes'] = minutes;
    await _writeSettings(value);
  }

  Future<int> getAutoLockMinutes() async {
    final value = await _readSettings();
    return int.tryParse('${value['autoLockMinutes']}') ?? 15;
  }

  Future<void> saveAutoLockMinutes(int minutes) async {
    final value = await _readSettings();
    value['autoLockMinutes'] = minutes;
    await _writeSettings(value);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
