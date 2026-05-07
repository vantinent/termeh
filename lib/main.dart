import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app_info.dart';
import 'screens/master_key_screen.dart';
import 'services/ssh_session_manager.dart';
import 'services/storage_service.dart';
import 'theme/adwaita_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  final storageService = StorageService();
  final width = await storageService.getWindowWidth();
  final height = await storageService.getWindowHeight();

  final windowOptions = WindowOptions(
    size: Size(width, height),
    center: true,
    title: AppInfo.name,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const TermehApp());
}

class TermehApp extends StatefulWidget {
  const TermehApp({super.key});

  @override
  State<TermehApp> createState() => _TermehAppState();
}

class _TermehAppState extends State<TermehApp> with WindowListener {
  final _sessionManager = SshSessionManager.instance;
  bool _handlingClose = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.setPreventClose(true);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (_handlingClose) return;
    _handlingClose = true;
    _confirmClose();
  }

  Future<void> _confirmClose() async {
    try {
      if (!_sessionManager.hasActiveConnections) {
        await windowManager.destroy();
        return;
      }

      final context = navigatorKey.currentContext;
      if (context == null) {
        await _sessionManager.disconnectAll();
        await windowManager.destroy();
        return;
      }

      final shouldClose = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Close App?'),
          content: const Text(
            'One or more SSH connections are still active. '
            'Do you want to disconnect them and close the app?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Close'),
            ),
          ],
        ),
      );

      if (shouldClose == true) {
        await _sessionManager.disconnectAll();
        await windowManager.destroy();
      }
    } finally {
      _handlingClose = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AdwaitaTheme.dark(),
      home: const MasterKeyGate(),
    );
  }
}
