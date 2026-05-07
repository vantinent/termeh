import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/master_key_service.dart';
import '../services/ssh_session_manager.dart';
import '../services/storage_service.dart';
import '../theme/adwaita_theme.dart';
import 'home_screen.dart';

class MasterKeyGate extends StatefulWidget {
  const MasterKeyGate({super.key});

  @override
  State<MasterKeyGate> createState() => _MasterKeyGateState();
}

class _MasterKeyGateState extends State<MasterKeyGate> {
  final _masterKeyService = MasterKeyService();
  final _storageService = StorageService();
  Timer? _inactivityTimer;
  bool _loading = true;
  bool _hasMasterKey = false;
  bool _unlocked = false;
  int _autoLockMinutes = 15;

  @override
  void initState() {
    super.initState();
    _loadGateState();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGateState() async {
    final hasSetupCompleted = await _masterKeyService.hasCompletedMacSetup();
    final hasVaultData = await _masterKeyService.hasMacVaultData();

    if (!hasSetupCompleted && !hasVaultData) {
      await _masterKeyService.resetStaleMacSetup();
    }

    final hasMasterKey = await _masterKeyService.hasMasterKey();
    final graceMinutes = await _storageService.getMasterUnlockGraceMinutes();
    final autoLockMinutes = await _storageService.getAutoLockMinutes();
    final canBypass = await _masterKeyService.canBypassUnlockPrompt(
      graceMinutes,
    );
    if (!mounted) return;

    setState(() {
      _hasMasterKey = hasMasterKey;
      _autoLockMinutes = autoLockMinutes;
      _loading = false;
      _unlocked = hasSetupCompleted && canBypass;
    });

    if (canBypass) {
      _scheduleInactivityLock();
    } else {
      _inactivityTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_unlocked) {
      return HomeScreen(
        onLockRequested: _lockApp,
        onUserActivity: _recordActivity,
        onAutoLockMinutesChanged: _updateAutoLockMinutes,
      );
    }

    return _MasterKeyScreen(
      isSetup: !_hasMasterKey,
      onUnlocked: _handleUnlocked,
    );
  }

  void _handleUnlocked() {
    setState(() {
      _unlocked = true;
    });
    _scheduleInactivityLock();
  }

  Future<void> _lockApp() async {
    _inactivityTimer?.cancel();
    await _masterKeyService.clearSuccessfulUnlockRecord();
    MasterKeyService.clearMacUnlockedMasterKey();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).popUntil((route) {
        return route.isFirst;
      });
    }
    setState(() {
      _unlocked = false;
    });
  }

  void _recordActivity() {
    if (!_unlocked || _autoLockMinutes <= 0) return;
    _scheduleInactivityLock();
  }

  void _updateAutoLockMinutes(int minutes) {
    setState(() {
      _autoLockMinutes = minutes;
    });
    _scheduleInactivityLock();
  }

  void _scheduleInactivityLock() {
    _inactivityTimer?.cancel();
    if (!_unlocked || _autoLockMinutes <= 0) return;
    _inactivityTimer = Timer(
      Duration(minutes: _autoLockMinutes),
      _lockApp,
    );
  }
}

class _MasterKeyScreen extends StatefulWidget {
  const _MasterKeyScreen({
    required this.isSetup,
    required this.onUnlocked,
  });

  final bool isSetup;
  final VoidCallback onUnlocked;

  @override
  State<_MasterKeyScreen> createState() => _MasterKeyScreenState();
}

class _MasterKeyScreenState extends State<_MasterKeyScreen> {
  final _masterKeyService = MasterKeyService();
  final _sessionManager = SshSessionManager.instance;
  final _keyController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _hasActiveConnections => _sessionManager.hasActiveConnections;

  @override
  void initState() {
    super.initState();
    _sessionManager.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _sessionManager.removeListener(_onSessionChanged);
    _keyController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _submit() async {
    final key = _keyController.text;
    final confirm = _confirmController.text;

    if (key.length < 4) {
      setState(() {
        _error = 'Use at least 4 characters.';
      });
      return;
    }

    if (widget.isSetup) {
      if (key != confirm) {
        setState(() {
          _error = 'The keys do not match.';
        });
        return;
      }

      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await _masterKeyService.setMasterKey(key);
        if (!mounted) return;
        widget.onUnlocked();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Could not save the master key on this Mac.';
        });
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final verified = await _masterKeyService.verifyMasterKey(key);
      if (!mounted) return;
      if (verified) {
        await _masterKeyService.recordSuccessfulUnlock();
        widget.onUnlocked();
        return;
      }

      setState(() {
        _busy = false;
        _error = 'Incorrect master key.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not unlock securely on this Mac.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AdwaitaColors.darkWindow,
      body: Stack(
        children: [
          const _MasterKeyBackdrop(),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Image.asset(
                              'assets/icon/icon.png',
                              width: 48,
                              height: 48,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(LucideIcons.keyRound, size: 42),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            widget.isSetup
                                ? 'Create Master Key'
                                : 'Unlock Termeh',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _keyController,
                            obscureText: true,
                            autofocus: true,
                            onSubmitted: (_) => _busy ? null : _submit(),
                            decoration: const InputDecoration(
                              labelText: 'Master Key',
                              prefixIcon: Icon(LucideIcons.lock),
                            ),
                          ),
                          if (widget.isSetup) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _confirmController,
                              obscureText: true,
                              onSubmitted: (_) => _busy ? null : _submit(),
                              decoration: const InputDecoration(
                                labelText: 'Confirm Master Key',
                                prefixIcon: Icon(LucideIcons.lock),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: AdwaitaColors.destructive,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(widget.isSetup ? 'Create' : 'Unlock'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_hasActiveConnections) ...[
                    const SizedBox(height: 12),
                    _buildConnectionWarning(theme),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionWarning(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AdwaitaColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AdwaitaColors.accent.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.info,
                  size: 18,
                  color: AdwaitaColors.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Active SSH connections are still open.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AdwaitaColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MasterKeyBackdrop extends StatelessWidget {
  const _MasterKeyBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AdwaitaColors.darkWindow,
                    AdwaitaColors.darkHeader,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -96,
            right: -68,
            child: _GateGlow(
              size: 220,
              color: AdwaitaColors.success.withValues(alpha: 0.08),
            ),
          ),
          Positioned(
            bottom: 110,
            left: -92,
            child: _GateGlow(
              size: 200,
              color: AdwaitaColors.accent.withValues(alpha: 0.07),
            ),
          ),
          Positioned(
            top: 220,
            left: 180,
            child: _GateGlow(
              size: 120,
              color: Colors.white.withValues(alpha: 0.022),
            ),
          ),
        ],
      ),
    );
  }
}

class _GateGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _GateGlow({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 120,
            spreadRadius: 28,
          ),
        ],
      ),
    );
  }
}
