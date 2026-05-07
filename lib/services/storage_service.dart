import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import '../models/ssh_connection.dart';
import '../theme/adwaita_theme.dart';
import 'master_key_service.dart';
import 'mac_local_store.dart';
import 'secure_storage_factory.dart';

class StorageService {
  final _storage = createSecureStorage();
  final _macStore = MacLocalStore.instance;
  static const _keyConnections = 'ssh_connections';
  static const _keyPasswordPrefix = 'ssh_connection_password_';
  static const _keyFontSize = 'terminal_font_size';
  static const _keyBackgroundColor = 'terminal_background_color';
  static const _keyWindowWidth = 'window_width';
  static const _keyWindowHeight = 'window_height';
  static const _keyMasterUnlockGraceMinutes = 'master_unlock_grace_minutes';
  static const _keyAutoLockMinutes = 'auto_lock_minutes';
  static const _encryptedExportFormat = 'termeh-encrypted-server-list';
  static const _encryptedExportVersion = 1;
  static const _kdfIterations = 210000;
  static const _saltLength = 32;
  static const _keyLength = 32;

  String _passwordKey(String id) => '$_keyPasswordPrefix$id';

  Future<double> getFontSize() async {
    if (Platform.isMacOS) return _macStore.getFontSize();
    try {
      final value = await _storage.read(key: _keyFontSize);
      if (value == null) return 17.0;
      return double.tryParse(value) ?? 17.0;
    } catch (e) {
      return 17.0;
    }
  }

  Future<void> saveFontSize(double fontSize) async {
    if (Platform.isMacOS) {
      await _macStore.saveFontSize(fontSize);
      return;
    }
    try {
      await _storage.write(key: _keyFontSize, value: fontSize.toString());
    } catch (e) {
      debugPrint('Error saving font size: $e');
    }
  }

  Future<int> getBackgroundColor() async {
    if (Platform.isMacOS) return _macStore.getBackgroundColor();
    try {
      final value = await _storage.read(key: _keyBackgroundColor);
      if (value == null) return AdwaitaColors.darkView.toARGB32();
      return int.tryParse(value) ?? AdwaitaColors.darkView.toARGB32();
    } catch (e) {
      return AdwaitaColors.darkView.toARGB32();
    }
  }

  Future<void> saveBackgroundColor(int color) async {
    if (Platform.isMacOS) {
      await _macStore.saveBackgroundColor(color);
      return;
    }
    try {
      await _storage.write(key: _keyBackgroundColor, value: color.toString());
    } catch (e) {
      debugPrint('Error saving background color: $e');
    }
  }

  Future<double> getWindowWidth() async {
    if (Platform.isMacOS) return _macStore.getWindowWidth();
    try {
      final value = await _storage.read(key: _keyWindowWidth);
      if (value == null) return 1000.0;
      return double.tryParse(value) ?? 1000.0;
    } catch (e) {
      return 1000.0;
    }
  }

  Future<void> saveWindowWidth(double width) async {
    if (Platform.isMacOS) {
      await _macStore.saveWindowWidth(width);
      return;
    }
    try {
      await _storage.write(key: _keyWindowWidth, value: width.toString());
    } catch (e) {
      debugPrint('Error saving window width: $e');
    }
  }

  Future<double> getWindowHeight() async {
    if (Platform.isMacOS) return _macStore.getWindowHeight();
    try {
      final value = await _storage.read(key: _keyWindowHeight);
      if (value == null) return 700.0;
      return double.tryParse(value) ?? 700.0;
    } catch (e) {
      return 700.0;
    }
  }

  Future<void> saveWindowHeight(double height) async {
    if (Platform.isMacOS) {
      await _macStore.saveWindowHeight(height);
      return;
    }
    try {
      await _storage.write(key: _keyWindowHeight, value: height.toString());
    } catch (e) {
      debugPrint('Error saving window height: $e');
    }
  }

  Future<int> getMasterUnlockGraceMinutes() async {
    if (Platform.isMacOS) return _macStore.getMasterUnlockGraceMinutes();
    try {
      final value = await _storage.read(key: _keyMasterUnlockGraceMinutes);
      return int.tryParse(value ?? '') ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> saveMasterUnlockGraceMinutes(int minutes) async {
    if (Platform.isMacOS) {
      await _macStore.saveMasterUnlockGraceMinutes(minutes);
      return;
    }
    try {
      await _storage.write(
        key: _keyMasterUnlockGraceMinutes,
        value: minutes.toString(),
      );
    } catch (e) {
      debugPrint('Error saving master unlock grace period: $e');
    }
  }

  Future<int> getAutoLockMinutes() async {
    if (Platform.isMacOS) return _macStore.getAutoLockMinutes();
    try {
      final value = await _storage.read(key: _keyAutoLockMinutes);
      return int.tryParse(value ?? '') ?? 15;
    } catch (e) {
      return 15;
    }
  }

  Future<void> saveAutoLockMinutes(int minutes) async {
    if (Platform.isMacOS) {
      await _macStore.saveAutoLockMinutes(minutes);
      return;
    }
    try {
      await _storage.write(
        key: _keyAutoLockMinutes,
        value: minutes.toString(),
      );
    } catch (e) {
      debugPrint('Error saving auto-lock period: $e');
    }
  }

  Future<List<SshConnection>> getConnections() async {
    if (Platform.isMacOS) {
      final masterKey = MasterKeyService.macUnlockedMasterKey;
      if (masterKey == null) return [];
      try {
        return await _macStore.getConnections(masterKey);
      } catch (e) {
        debugPrint('Error reading macOS connections: $e');
        return [];
      }
    }
    try {
      final value = await _storage.read(key: _keyConnections);
      if (value == null) return [];

      final decoded = json.decode(value);
      if (decoded is! List) return [];

      final connections = <SshConnection>[];
      var migratedLegacyPasswords = false;

      for (final entry in decoded.whereType<Map<String, dynamic>>()) {
        final metadata = SshConnection.fromMap(entry);
        final storedPassword =
            await _storage.read(key: _passwordKey(metadata.id));
        final legacyPassword = entry['password'] as String?;
        final password = storedPassword ?? legacyPassword;

        if (storedPassword == null &&
            legacyPassword != null &&
            legacyPassword.isNotEmpty) {
          await _storage.write(
            key: _passwordKey(metadata.id),
            value: legacyPassword,
          );
          migratedLegacyPasswords = true;
        }

        connections.add(
          SshConnection(
            id: metadata.id,
            name: metadata.name,
            host: metadata.host,
            port: metadata.port,
            username: metadata.username,
            group: metadata.group,
            password: password,
            hostKeyType: metadata.hostKeyType,
            hostKeyFingerprint: metadata.hostKeyFingerprint,
          ),
        );
      }

      if (migratedLegacyPasswords) {
        await _saveConnectionMetadata(connections);
      }

      return connections;
    } catch (e) {
      debugPrint('Error reading connections: $e');
      return [];
    }
  }

  Future<void> saveConnections(List<SshConnection> connections) async {
    try {
      if (Platform.isMacOS) {
        final masterKey = MasterKeyService.macUnlockedMasterKey;
        if (masterKey == null) {
          throw StateError('Master key is not unlocked.');
        }
        await _macStore.saveConnections(connections, masterKey);
        return;
      }
      await _saveConnectionMetadata(connections);
      await Future.wait(connections.map(_saveConnectionPassword));
    } catch (e) {
      debugPrint('Error saving connections: $e');
      rethrow;
    }
  }

  Future<void> _saveConnectionMetadata(List<SshConnection> connections) async {
    if (Platform.isMacOS) return;
    final value = json.encode(connections.map((e) => e.toMap()).toList());
    await _storage.write(key: _keyConnections, value: value);
  }

  Future<void> _saveConnectionPassword(SshConnection connection) async {
    if (Platform.isMacOS) return;
    final password = connection.password;
    final key = _passwordKey(connection.id);

    if (password == null || password.isEmpty) {
      await _storage.delete(key: key);
      return;
    }

    await _storage.write(key: key, value: password);
  }

  Future<void> addConnection(SshConnection connection) async {
    if (Platform.isMacOS) {
      final masterKey = MasterKeyService.macUnlockedMasterKey;
      if (masterKey == null) {
        throw StateError('Master key is not unlocked.');
      }
      await _macStore.addConnection(connection, masterKey);
      return;
    }
    final connections = await getConnections();
    // Check for duplicate ID to be safe
    connections.removeWhere((e) => e.id == connection.id);
    connections.add(connection);
    await saveConnections(connections);
  }

  Future<void> deleteConnection(String id) async {
    if (Platform.isMacOS) {
      final masterKey = MasterKeyService.macUnlockedMasterKey;
      if (masterKey == null) {
        throw StateError('Master key is not unlocked.');
      }
      await _macStore.deleteConnection(id, masterKey);
      return;
    }
    final connections = await getConnections();
    connections.removeWhere((element) => element.id == id);
    await _storage.delete(key: _passwordKey(id));
    await saveConnections(connections);
  }

  Future<void> updateConnection(SshConnection connection) async {
    if (Platform.isMacOS) {
      final masterKey = MasterKeyService.macUnlockedMasterKey;
      if (masterKey == null) {
        throw StateError('Master key is not unlocked.');
      }
      await _macStore.updateConnection(connection, masterKey);
      return;
    }
    final connections = await getConnections();
    final index = connections.indexWhere((e) => e.id == connection.id);
    if (index != -1) {
      connections[index] = connection;
      await saveConnections(connections);
    }
  }

  Future<String> exportConnectionsEncrypted(String masterKey) async {
    if (Platform.isMacOS) {
      final connections = await getConnections();
      return _macStore.exportConnectionsEncrypted(connections, masterKey);
    }
    final connections = await getConnections();
    final plaintext = json.encode({
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
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
    final keyMaterial = MasterKeyService().deriveKeyBytes(
      masterKey,
      salt,
      _kdfIterations,
      _keyLength,
    );
    final secretKey = SecretKey(Uint8List.fromList(keyMaterial));
    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    final saltText = base64Encode(salt);
    final payload = {
      'format': _encryptedExportFormat,
      'version': _encryptedExportVersion,
      'kdf': 'pbkdf2-sha256',
      'iterations': _kdfIterations,
      'salt': saltText,
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };

    return json.encode(payload);
  }

  Future<void> importConnectionsEncrypted(
    String contents,
    String masterKey,
  ) async {
    if (Platform.isMacOS) {
      await _macStore.importConnectionsEncrypted(contents, masterKey);
      return;
    }
    final decoded = json.decode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid encrypted server list file.');
    }

    if (decoded['format'] != _encryptedExportFormat) {
      throw const FormatException('Invalid encrypted server list file.');
    }

    final saltText = decoded['salt'] as String?;
    final nonceText = decoded['nonce'] as String?;
    final ciphertextText = decoded['ciphertext'] as String?;
    final macText = decoded['mac'] as String?;
    final iterations =
        int.tryParse('${decoded['iterations']}') ?? _kdfIterations;

    if (saltText == null ||
        nonceText == null ||
        ciphertextText == null ||
        macText == null) {
      throw const FormatException('Invalid encrypted server list file.');
    }

    final salt = base64Decode(saltText);
    final nonce = base64Decode(nonceText);
    final keyMaterial = MasterKeyService().deriveKeyBytes(
      masterKey,
      salt,
      iterations,
      _keyLength,
    );
    final algorithm = AesGcm.with256bits();
    final secretBox = SecretBox(
      base64Decode(ciphertextText),
      nonce: nonce,
      mac: Mac(base64Decode(macText)),
    );
    late final List<int> plaintextBytes;
    try {
      plaintextBytes = await algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(Uint8List.fromList(keyMaterial)),
      );
    } catch (_) {
      throw const FormatException('Incorrect master key or corrupted file.');
    }

    final plainDecoded = json.decode(utf8.decode(plaintextBytes));
    final entries = plainDecoded is Map<String, dynamic>
        ? plainDecoded['connections']
        : plainDecoded;

    if (entries is! List) {
      throw const FormatException('Invalid encrypted server list file.');
    }

    final importedConnections = entries.whereType<Map>().map((entry) {
      final map = Map<String, dynamic>.from(entry);
      return SshConnection.fromMap(map).copyWith(
        password: map['password'] as String?,
      );
    }).toList();
    await saveConnections(importedConnections);
  }

  Future<void> migrateMacVault(
    String oldMasterKey,
    String newMasterKey,
  ) async {
    if (!Platform.isMacOS) return;
    await _macStore.migrateConnections(oldMasterKey, newMasterKey);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
