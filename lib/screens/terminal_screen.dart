// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:xterm/xterm.dart';
import '../models/ssh_connection.dart';
import '../services/ssh_session_manager.dart';
import '../services/storage_service.dart';
import '../theme/adwaita_theme.dart';

class TerminalScreen extends StatefulWidget {
  final SshConnection connection;
  final VoidCallback onUserActivity;
  final VoidCallback onLockRequested;

  const TerminalScreen({
    super.key,
    required this.connection,
    required this.onUserActivity,
    required this.onLockRequested,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  final _storageService = StorageService();
  final _sessionManager = SshSessionManager.instance;
  late SshConnection _connection;
  late final ManagedSession _sessionState;
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  bool _connecting = true;
  double _fontSize = 17;
  Color _backgroundColor = AdwaitaColors.darkView;
  String? _verifiedHostKeyType;
  String? _verifiedHostKeyFingerprint;
  String? _pendingHostKeyType;
  String? _pendingHostKeyFingerprint;
  bool _awaitingHostKeyApproval = false;
  Timer? _fontSizeSaveTimer;

  @override
  void initState() {
    super.initState();
    _connection = widget.connection;
    WidgetsBinding.instance.addObserver(this);
    _sessionState = _sessionManager.sessionFor(_connection.id);
    _terminal = _sessionState.terminal;
    _terminalController = TerminalController();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshConnection().then((_) {
        if (mounted) {
          connect();
        }
      });
    });
  }

  Future<void> _disconnect() async {
    _fontSizeSaveTimer?.cancel();
    await _sessionManager.disconnect(_connection.id);
  }

  Future<void> _loadSettings() async {
    final fontSize = await _storageService.getFontSize();
    final bgColorValue = await _storageService.getBackgroundColor();
    if (mounted) {
      setState(() {
        _fontSize = fontSize;
        _backgroundColor = Color(bgColorValue);
      });
    }
  }

  Future<void> _refreshConnection() async {
    final connections = await _storageService.getConnections();
    final storedConnection = connections.firstWhere(
      (connection) => connection.id == _connection.id,
      orElse: () => _connection,
    );

    if (!mounted) return;
    setState(() {
      _connection = storedConnection;
    });
  }

  Future<void> connect() async {
    _pendingHostKeyType = null;
    _pendingHostKeyFingerprint = null;
    _awaitingHostKeyApproval = false;

    try {
      if (!_sessionState.isConnected) {
        await _sessionManager.connect(
          connection: _connection,
          requestPassword: _resolveConnectionPassword,
          verifyHostKey: _verifyHostKey,
          onTerminalActivity: widget.onUserActivity,
        );
        await _rememberVerifiedHostKey();
      }

      if (!mounted) return;
      _sessionState.attachTerminal(onOutput: widget.onUserActivity);
      _sessionState.syncTerminalSize();
      setState(() {
        _connecting = false;
      });
    } catch (e) {
      if (e is ConnectionCancelledException) {
        if (mounted) {
          setState(() {
            _connecting = false;
          });
        }
        _sessionState.detachTerminal();
        _terminal.write('\r\nConnection cancelled.\r\n');
        return;
      }

      if (_awaitingHostKeyApproval &&
          _pendingHostKeyType != null &&
          _pendingHostKeyFingerprint != null) {
        final approved = await _promptToTrustUnknownHostKey();
        if (!mounted) return;

        if (approved) {
          final updatedConnection = _connection.copyWith(
            hostKeyType: _pendingHostKeyType,
            hostKeyFingerprint: _pendingHostKeyFingerprint,
          );
          _connection = updatedConnection;
          await _storageService.updateConnection(updatedConnection);
          await _sessionState.disconnect();
          await connect();
          return;
        }

        setState(() {
          _connecting = false;
        });
        _terminal.write('\r\nHost key not trusted.\r\n');
        return;
      }

      if (mounted) {
        setState(() {
          _connecting = false;
        });
        _terminal.write('\r\nError: $e\r\n');
      }
    }
  }

  Future<String?> _resolveConnectionPassword() async {
    final savedPassword = _connection.password;
    if (savedPassword != null && savedPassword.isNotEmpty) {
      return savedPassword;
    }

    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _PasswordPromptDialog(
          title: _connection.name,
          subtitle: _connection.host,
        );
      },
    );
  }

  bool _verifyHostKey(String type, Uint8List fingerprint) {
    final fingerprintText = _formatFingerprint(fingerprint);
    final savedType = _connection.hostKeyType;
    final savedFingerprint = _connection.hostKeyFingerprint;

    if (savedFingerprint != null) {
      final matches = savedFingerprint == fingerprintText;
      if (matches) {
        _verifiedHostKeyType = type;
        _verifiedHostKeyFingerprint = fingerprintText;
      }
      return matches;
    }

    if (savedType == null && savedFingerprint == null) {
      _pendingHostKeyType = type;
      _pendingHostKeyFingerprint = fingerprintText;
      _awaitingHostKeyApproval = true;
    }
    return false;
  }

  Future<void> _rememberVerifiedHostKey() async {
    final type = _verifiedHostKeyType;
    final fingerprint = _verifiedHostKeyFingerprint;
    if (type == null || fingerprint == null) return;
    if (_connection.hostKeyType == type &&
        _connection.hostKeyFingerprint == fingerprint) {
      return;
    }

    await _storageService.updateConnection(
      _connection.copyWith(
        hostKeyType: type,
        hostKeyFingerprint: fingerprint,
      ),
    );
  }

  String _formatFingerprint(Uint8List fingerprint) {
    return fingerprint
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }

  Future<bool> _promptToTrustUnknownHostKey() async {
    final type = _pendingHostKeyType;
    final fingerprint = _pendingHostKeyFingerprint;
    if (!mounted || type == null || fingerprint == null) return false;

    final trusted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AdwaitaColors.darkView,
          title: const Text('Trust SSH Host Key?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The server ${_connection.host}:${_connection.port} is presenting an unknown SSH host key.',
                  style: TextStyle(color: AdwaitaColors.darkMuted),
                ),
                const SizedBox(height: 12),
                Text(
                  'Type',
                  style: TextStyle(
                    color: AdwaitaColors.darkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  type,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  'Fingerprint',
                  style: TextStyle(
                    color: AdwaitaColors.darkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  fingerprint,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Trusting this key will pin it for future connections.',
                  style: TextStyle(color: AdwaitaColors.darkMuted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Trust and Connect'),
            ),
          ],
        );
      },
    );

    _awaitingHostKeyApproval = false;
    return trusted == true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionState.detachTerminal();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        _sessionState.detachTerminal();
      },
      child: Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          title: Text(_connection.name),
          backgroundColor: AdwaitaColors.darkHeader,
          actions: [
            if (!_connecting) ...[
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  icon: const Icon(LucideIcons.lock),
                  onPressed: widget.onLockRequested,
                  tooltip: 'Lock App',
                  color: Colors.grey,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  icon: const Icon(LucideIcons.logOut),
                  onPressed: () async {
                    await _disconnect();
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  tooltip: 'Disconnect',
                  color: Colors.grey,
                ),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.zero,
                child: Listener(
                  onPointerDown: (pointerDown) {
                    widget.onUserActivity();
                    if (pointerDown.kind == PointerDeviceKind.mouse &&
                        pointerDown.buttons == kSecondaryMouseButton) {
                      _showContextMenu(context, pointerDown.position);
                    }
                  },
                  onPointerSignal: (pointerSignal) {
                    widget.onUserActivity();
                    if (pointerSignal is PointerScrollEvent) {
                      if (HardwareKeyboard.instance.isControlPressed) {
                        final nextFontSize = (_fontSize +
                                (pointerSignal.scrollDelta.dy < 0 ? 1 : -1))
                            .clamp(8, 40)
                            .toDouble();
                        if (nextFontSize == _fontSize) return;
                        setState(() {
                          _fontSize = nextFontSize;
                        });
                        _scheduleFontSizeSave();
                      }
                    }
                  },
                  child: RepaintBoundary(
                    child: TerminalView(
                      _terminal,
                      controller: _terminalController,
                      autofocus: true,
                      backgroundOpacity: 0,
                      theme: TerminalTheme(
                        cursor: AdwaitaColors.terminalForeground,
                        selection: AdwaitaColors.terminalSelection,
                        foreground: AdwaitaColors.terminalForeground,
                        background: _backgroundColor,
                        black: const Color(0xFF2E3436),
                        red: const Color(0xFFCC0000),
                        green: const Color(0xFF4E9A06),
                        yellow: const Color(0xFFC4A000),
                        blue: const Color(0xFF3465A4),
                        magenta: const Color(0xFF75507B),
                        cyan: const Color(0xFF06989A),
                        white: const Color(0xFFD3D7CF),
                        brightBlack: const Color(0xFF555753),
                        brightRed: const Color(0xFFEF2929),
                        brightGreen: const Color(0xFF8AE234),
                        brightYellow: const Color(0xFFFCE94F),
                        brightBlue: const Color(0xFF729FCF),
                        brightMagenta: const Color(0xFFAD7FA8),
                        brightCyan: const Color(0xFF34E2E2),
                        brightWhite: const Color(0xFFEEEEEC),
                        searchHitBackground: const Color(0xFFF6D32D),
                        searchHitBackgroundCurrent: const Color(0xFFFF7800),
                        searchHitForeground: Colors.black,
                      ),
                      textStyle: TerminalStyle(
                        fontSize: _fontSize,
                        fontFamily: 'Ubuntu Mono',
                      ),
                    ),
                  ),
                ),
              ),
              if (_connecting)
                Container(
                  color: AdwaitaColors.darkWindow.withValues(alpha: 0.94),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AdwaitaColors.darkView,
                        border: Border.all(color: AdwaitaColors.darkBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(strokeWidth: 3),
                            const SizedBox(height: 18),
                            Text(
                              'Connecting to ${_connection.host}...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _scheduleFontSizeSave() {
    _fontSizeSaveTimer?.cancel();
    _fontSizeSaveTimer = Timer(const Duration(milliseconds: 250), () {
      _storageService.saveFontSize(_fontSize);
    });
  }

  void _showContextMenu(BuildContext context, Offset position) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selectedValue = await showMenu<String>(
      context: context,
      color: AdwaitaColors.darkView,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 90),
        reverseDuration: Duration(milliseconds: 60),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AdwaitaColors.darkBorder),
      ),
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'copy',
          enabled: _terminalController.selection != null,
          height: 34,
          padding: EdgeInsets.zero,
          child: _buildContextMenuItem(
            'Copy',
            enabled: _terminalController.selection != null,
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          height: 34,
          padding: EdgeInsets.zero,
          child: _buildContextMenuItem('Paste'),
        ),
        const PopupMenuDivider(height: 9),
        PopupMenuItem<String>(
          value: 'select_all',
          height: 34,
          padding: EdgeInsets.zero,
          child: _buildContextMenuItem('Select All'),
        ),
        PopupMenuItem<String>(
          value: 'clear',
          height: 34,
          padding: EdgeInsets.zero,
          child: _buildContextMenuItem('Clear Terminal',
              color: AdwaitaColors.destructive),
        ),
      ],
    );

    if (selectedValue == null) return;

    switch (selectedValue) {
      case 'copy':
        final range = _terminalController.selection;
        if (range != null) {
          final selectedText = _terminal.buffer.getText(range);
          if (selectedText.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: selectedText));
            _terminalController.clearSelection();
          }
        }
        break;
      case 'paste':
        final data = await Clipboard.getData('text/plain');
        if (data != null && data.text != null) {
          _terminal.onOutput?.call(data.text!);
        }
        break;
      case 'select_all':
        final startAnchor = _terminal.buffer.createAnchor(0, 0);
        final endAnchor = _terminal.buffer.createAnchor(
            _terminal.viewWidth, _terminal.buffer.lines.length - 1);
        _terminalController.setSelection(startAnchor, endAnchor);
        break;
      case 'clear':
        _terminal.write('\x1b[2J\x1b[H');
        break;
    }
  }

  Widget _buildContextMenuItem(
    String label, {
    Color? color,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            color: enabled
                ? color ?? AdwaitaColors.terminalForeground
                : AdwaitaColors.darkMuted.withValues(alpha: 0.45),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PasswordPromptDialog extends StatefulWidget {
  final String title;
  final String subtitle;

  const _PasswordPromptDialog({
    required this.title,
    required this.subtitle,
  });

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();
  bool _obscureText = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdwaitaColors.darkView,
      title: Text(
        'SSH Password',
        style: TextStyle(color: AdwaitaColors.terminalForeground),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the password for ${widget.title}.',
              style: TextStyle(color: AdwaitaColors.darkMuted),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: TextStyle(color: AdwaitaColors.darkMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscureText,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
