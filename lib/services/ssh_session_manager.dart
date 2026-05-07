import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_connection.dart';

class SshSessionManager extends ChangeNotifier {
  SshSessionManager._();

  static final SshSessionManager instance = SshSessionManager._();

  final Map<String, ManagedSession> _sessions = {};

  ManagedSession sessionFor(String connectionId) {
    return _sessions.putIfAbsent(connectionId, ManagedSession.new);
  }

  bool isConnected(String connectionId) {
    return _sessions[connectionId]?.isConnected ?? false;
  }

  bool get hasActiveConnections =>
      _sessions.values.any((session) => session.isConnected);

  List<String> get activeConnectionIds => _sessions.entries
      .where((entry) => entry.value.isConnected)
      .map((entry) => entry.key)
      .toList();

  Future<ManagedSession> connect({
    required SshConnection connection,
    required FutureOr<String?> Function() requestPassword,
    required bool Function(String type, Uint8List fingerprint) verifyHostKey,
    VoidCallback? onTerminalActivity,
  }) async {
    final managedSession = sessionFor(connection.id);
    if (managedSession.isConnected) {
      return managedSession;
    }

    final savedPassword = connection.password;
    final password = savedPassword != null && savedPassword.isNotEmpty
        ? savedPassword
        : await requestPassword();
    if (password == null || password.isEmpty) {
      throw const ConnectionCancelledException();
    }

    await managedSession.connect(
      connection: connection,
      password: password,
      verifyHostKey: verifyHostKey,
      onTerminalActivity: onTerminalActivity,
    );
    notifyListeners();
    return managedSession;
  }

  Future<void> disconnect(String connectionId) async {
    final managedSession = _sessions.remove(connectionId);
    if (managedSession == null) return;
    await managedSession.disconnect();
    notifyListeners();
  }

  Future<void> disconnectAll() async {
    final ids = activeConnectionIds;
    if (ids.isEmpty) return;

    await Future.wait(ids.map(disconnect));
  }
}

class ManagedSession {
  final Terminal terminal = Terminal(maxLines: 10000);
  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Timer? _flushTimer;
  final StringBuffer _pendingOutput = StringBuffer();
  bool _isFlushing = false;

  bool get isConnected => _session != null;

  Future<void> connect({
    required SshConnection connection,
    required String password,
    required bool Function(String type, Uint8List fingerprint) verifyHostKey,
    VoidCallback? onTerminalActivity,
  }) async {
    final socket = await SSHSocket.connect(connection.host, connection.port);
    _client = SSHClient(
      socket,
      username: connection.username,
      onPasswordRequest: () => password,
      onVerifyHostKey: verifyHostKey,
    );

    await _client!.authenticated;
    _session = await _client!.shell();
    attachTerminal(onOutput: onTerminalActivity);

    _stdoutSubscription = _session!.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_queueOutput);

    _stderrSubscription = _session!.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_queueOutput);

    _session!.done.then((_) {
      _queueOutput('\r\nConnection closed.\r\n');
      unawaited(disconnect());
    });
  }

  void detachTerminal() {
    terminal.onOutput = null;
    terminal.onResize = null;
  }

  void attachTerminal({VoidCallback? onOutput}) {
    terminal.onOutput = (data) {
      onOutput?.call();
      _session?.stdin.add(utf8.encode(data));
    };
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      _session?.resizeTerminal(width, height);
    };
  }

  void syncTerminalSize() {
    terminal.resize(
      terminal.viewWidth,
      terminal.viewHeight,
      0,
      0,
    );
  }

  Future<void> disconnect() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushPendingOutput();
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
    detachTerminal();
  }

  void _queueOutput(String data) {
    if (data.isEmpty) return;
    _pendingOutput.write(data);
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(milliseconds: 8), () {
      _flushTimer = null;
      _flushPendingOutput();
    });
  }

  void _flushPendingOutput() {
    if (_isFlushing) return;
    if (_pendingOutput.isEmpty) return;

    _isFlushing = true;
    try {
      terminal.write(_pendingOutput.toString());
      _pendingOutput.clear();
    } finally {
      _isFlushing = false;
    }
  }
}

class ConnectionCancelledException implements Exception {
  const ConnectionCancelledException();
}
