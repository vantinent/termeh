// ignore_for_file: prefer_const_constructors

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';
import '../app_info.dart';
import '../models/ssh_connection.dart';
import '../services/master_key_service.dart';
import '../services/ssh_session_manager.dart';
import '../services/storage_service.dart';
import '../theme/adwaita_theme.dart';
import 'about_screen.dart';
import 'terminal_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onLockRequested;
  final VoidCallback onUserActivity;
  final ValueChanged<int> onAutoLockMinutesChanged;

  const HomeScreen({
    super.key,
    required this.onLockRequested,
    required this.onUserActivity,
    required this.onAutoLockMinutesChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storageService = StorageService();
  final _masterKeyService = MasterKeyService();
  final _sessionManager = SshSessionManager.instance;
  List<SshConnection> _connections = [];

  @override
  void initState() {
    super.initState();
    _loadConnections();
    _sessionManager.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _sessionManager.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _markActivity() {
    widget.onUserActivity();
  }

  Future<void> _loadConnections() async {
    final connections = await _storageService.getConnections();
    if (!mounted) return;
    setState(() {
      _connections = connections;
    });
  }

  List<_ConnectionGroup> _groupedConnections() {
    final groups = <String, List<SshConnection>>{};

    for (final connection in _connections) {
      final groupKey = connection.group.trim();
      groups.putIfAbsent(groupKey, () => <SshConnection>[]).add(connection);
    }

    final entries = groups.entries.toList()
      ..sort((a, b) {
        if (a.key.isEmpty && b.key.isNotEmpty) return -1;
        if (a.key.isNotEmpty && b.key.isEmpty) return 1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    return entries
        .map(
          (entry) => _ConnectionGroup(
            key: entry.key,
            name: entry.key.isEmpty ? 'Ungrouped' : entry.key,
            connections: List<SshConnection>.from(entry.value),
          ),
        )
        .toList();
  }

  List<SshConnection> _flattenGroups(List<_ConnectionGroup> groups) {
    return groups.expand((group) => group.connections).toList();
  }

  Future<void> _reorderConnectionsInGroup(
    String groupKey,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final groupedConnections = _groupedConnections();
    final targetGroupIndex =
        groupedConnections.indexWhere((group) => group.key == groupKey);
    if (targetGroupIndex == -1) return;

    final targetGroup = groupedConnections[targetGroupIndex];
    final updatedGroupConnections =
        List<SshConnection>.from(targetGroup.connections);
    final movedConnection = updatedGroupConnections.removeAt(oldIndex);
    updatedGroupConnections.insert(newIndex, movedConnection);

    groupedConnections[targetGroupIndex] = _ConnectionGroup(
      key: targetGroup.key,
      name: targetGroup.name,
      connections: updatedGroupConnections,
    );

    final updatedConnections = _flattenGroups(groupedConnections);

    setState(() {
      _connections = updatedConnections;
    });

    try {
      await _storageService.saveConnections(updatedConnections);
    } catch (e) {
      if (!mounted) return;
      await _loadConnections();
      _showAppSnackBar('Failed to save server order: $e', SnackBarKind.error);
    }
  }

  Future<void> _openConnection(
    SshConnection connection, {
    bool reconnect = false,
  }) async {
    final latestConnection = await _latestConnection(connection);
    if (!mounted) return;

    if (reconnect && _sessionManager.isConnected(latestConnection.id)) {
      await _sessionManager.disconnect(latestConnection.id);
    }
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          connection: latestConnection,
          onUserActivity: widget.onUserActivity,
          onLockRequested: widget.onLockRequested,
        ),
      ),
    );

    if (mounted) {
      await _loadConnections();
    }
  }

  Future<void> _disconnectConnection(SshConnection connection) async {
    await _sessionManager.disconnect(connection.id);
    if (mounted) {
      setState(() {});
    }
  }

  Future<SshConnection> _latestConnection(SshConnection fallback) async {
    final connections = await _storageService.getConnections();
    return connections.firstWhere(
      (connection) => connection.id == fallback.id,
      orElse: () => fallback,
    );
  }

  Future<void> _exportServerList() async {
    final hasMasterKey = await _masterKeyService.hasMasterKey();
    if (!hasMasterKey) {
      if (!mounted) return;
      _showAppSnackBar(
        'Set a master key before exporting servers.',
        SnackBarKind.info,
      );
      return;
    }

    final masterKey = await _promptForMasterKey(
      title: 'Export Servers',
      message: 'Enter your master key to encrypt the server list.',
    );
    if (masterKey == null || masterKey.isEmpty) return;

    final verified = await _masterKeyService.verifyMasterKey(masterKey);
    if (!verified) {
      if (!mounted) return;
      _showAppSnackBar(
        'Incorrect master key.',
        SnackBarKind.error,
      );
      return;
    }

    final saveLocation = await getSaveLocation(
      suggestedName: 'termeh-server-list.enc',
    );
    if (saveLocation == null) return;

    try {
      final contents =
          await _storageService.exportConnectionsEncrypted(masterKey);
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(contents)),
        name: 'termeh-server-list.enc',
        mimeType: 'application/octet-stream',
      );
      await file.saveTo(saveLocation.path);

      if (!mounted) return;
      _showAppSnackBar('Server list exported.', SnackBarKind.success);
    } catch (e) {
      if (!mounted) return;
      _showAppSnackBar('Export failed: $e', SnackBarKind.error);
    }
  }

  Future<void> _importServerList() async {
    if (!mounted) return;

    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Encrypted Termeh Export',
          extensions: <String>['enc', 'termeh'],
        ),
      ],
    );
    if (file == null) return;

    final masterKey = await _promptForMasterKey(
      title: 'Import Servers',
      message: 'Enter the master key used to encrypt the exported file.',
    );
    if (masterKey == null || masterKey.isEmpty) return;

    final verified = await _masterKeyService.verifyMasterKey(masterKey);
    if (!verified) {
      if (!mounted) return;
      _showAppSnackBar(
        'Incorrect master key.',
        SnackBarKind.error,
      );
      return;
    }

    try {
      final contents = await file.readAsString();
      await _storageService.importConnectionsEncrypted(contents, masterKey);
      await _loadConnections();

      if (!mounted) return;
      _showAppSnackBar('Server list imported.', SnackBarKind.success);
    } catch (e) {
      if (!mounted) return;
      _showAppSnackBar('Import failed: $e', SnackBarKind.error);
    }
  }

  Future<String?> _promptForMasterKey({
    required String title,
    required String message,
  }) async {
    final controller = TextEditingController();
    try {
      if (!mounted) return null;
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actionsAlignment: MainAxisAlignment.end,
          content: Listener(
            onPointerDown: (_) => _markActivity(),
            onPointerSignal: (_) => _markActivity(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      obscureText: true,
                      autofocus: true,
                      onChanged: (_) => _markActivity(),
                      decoration: const InputDecoration(
                        labelText: 'Master Key',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _markActivity();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                _markActivity();
                Navigator.pop(dialogContext, controller.text);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      return result;
    } finally {
      controller.dispose();
    }
  }

  void _showAppSnackBar(String message, SnackBarKind kind) {
    final color = switch (kind) {
      SnackBarKind.success => AdwaitaColors.success,
      SnackBarKind.error => AdwaitaColors.destructive,
      SnackBarKind.info => AdwaitaColors.accent,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  void _showSettings() async {
    final width = await _storageService.getWindowWidth();
    final height = await _storageService.getWindowHeight();
    var terminalBackgroundColor =
        Color(await _storageService.getBackgroundColor());
    var unlockGraceMinutes =
        await _storageService.getMasterUnlockGraceMinutes();
    var autoLockMinutes = await _storageService.getAutoLockMinutes();
    final widthController =
        TextEditingController(text: width.toStringAsFixed(0));
    final heightController =
        TextEditingController(text: height.toStringAsFixed(0));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: BoxDecoration(
            color: AdwaitaColors.darkView,
            border: Border.all(color: AdwaitaColors.darkBorder),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            left: 18,
            right: 18,
            top: 12,
          ),
          child: Listener(
            onPointerDown: (_) => _markActivity(),
            onPointerSignal: (_) => _markActivity(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Settings',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(LucideIcons.x),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          widthController,
                          'Default Width',
                          LucideIcons.arrowLeftRight,
                          '1000',
                          isNumber: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTextField(
                          heightController,
                          'Default Height',
                          LucideIcons.arrowUpDown,
                          '700',
                          isNumber: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: AdwaitaColors.darkSidebar,
                    borderRadius: BorderRadius.circular(8),
                    child: PopupMenuButton<Color>(
                      tooltip: 'Terminal Background',
                      initialValue: terminalBackgroundColor,
                      onSelected: (color) {
                        setSheetState(() {
                          terminalBackgroundColor = color;
                        });
                        _storageService.saveBackgroundColor(color.toARGB32());
                      },
                      itemBuilder: (context) => [
                        _buildColorOption(
                          'Ubuntu Aubergine',
                          AdwaitaColors.terminalBackground,
                          terminalBackgroundColor,
                        ),
                        _buildColorOption(
                          'GNOME Dark',
                          const Color(0xFF241F31),
                          terminalBackgroundColor,
                        ),
                        _buildColorOption(
                          'Black',
                          Colors.black,
                          terminalBackgroundColor,
                        ),
                        _buildColorOption(
                          'Adwaita Dark',
                          AdwaitaColors.darkView,
                          terminalBackgroundColor,
                        ),
                        _buildColorOption(
                          'Solarized Dark',
                          const Color(0xFF002B36),
                          terminalBackgroundColor,
                        ),
                        _buildColorOption(
                          'macOS Graphite',
                          const Color(0xFF2B2B2B),
                          terminalBackgroundColor,
                        ),
                        _buildColorOption(
                          'macOS Midnight',
                          const Color(0xFF111827),
                          terminalBackgroundColor,
                        ),
                      ],
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          side: BorderSide(color: AdwaitaColors.darkBorder),
                        ),
                        leading: Icon(LucideIcons.palette),
                        title: Text('Terminal Background'),
                        subtitle: Text('Color used for terminal sessions'),
                        trailing: Icon(LucideIcons.chevronRight),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: AdwaitaColors.darkSidebar,
                    borderRadius: BorderRadius.circular(8),
                    child: PopupMenuButton<int>(
                      tooltip: 'Unlock Grace Period',
                      initialValue: unlockGraceMinutes,
                      onSelected: (minutes) {
                        setSheetState(() {
                          unlockGraceMinutes = minutes;
                        });
                        _storageService.saveMasterUnlockGraceMinutes(minutes);
                      },
                      itemBuilder: (context) => [
                        _buildGraceOption(0, unlockGraceMinutes),
                        _buildGraceOption(1, unlockGraceMinutes),
                        _buildGraceOption(5, unlockGraceMinutes),
                        _buildGraceOption(10, unlockGraceMinutes),
                        _buildGraceOption(30, unlockGraceMinutes),
                        _buildGraceOption(60, unlockGraceMinutes),
                      ],
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: AdwaitaColors.darkBorder),
                        ),
                        leading: const Icon(LucideIcons.timerReset),
                        title: const Text('Unlock Grace Period'),
                        subtitle: Text(_unlockGraceLabel(unlockGraceMinutes)),
                        trailing: const Icon(LucideIcons.chevronRight),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: AdwaitaColors.darkSidebar,
                    borderRadius: BorderRadius.circular(8),
                    child: PopupMenuButton<int>(
                      tooltip: 'Auto-Lock After Inactivity',
                      initialValue: autoLockMinutes,
                      onSelected: (minutes) {
                        setSheetState(() {
                          autoLockMinutes = minutes;
                        });
                        _storageService.saveAutoLockMinutes(minutes);
                        widget.onAutoLockMinutesChanged(minutes);
                        _markActivity();
                      },
                      itemBuilder: (context) => [
                        _buildAutoLockOption(0, autoLockMinutes),
                        _buildAutoLockOption(1, autoLockMinutes),
                        _buildAutoLockOption(5, autoLockMinutes),
                        _buildAutoLockOption(10, autoLockMinutes),
                        _buildAutoLockOption(15, autoLockMinutes),
                        _buildAutoLockOption(30, autoLockMinutes),
                        _buildAutoLockOption(60, autoLockMinutes),
                      ],
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: AdwaitaColors.darkBorder),
                        ),
                        leading: const Icon(LucideIcons.timerOff),
                        title: const Text('Auto-Lock After Inactivity'),
                        subtitle: Text(_autoLockLabel(autoLockMinutes)),
                        trailing: const Icon(LucideIcons.chevronRight),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: AdwaitaColors.darkSidebar,
                          borderRadius: BorderRadius.circular(8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: AdwaitaColors.darkBorder,
                              ),
                            ),
                            leading: const Icon(Icons.file_upload_outlined),
                            title: const Text('Export Servers'),
                            subtitle: const Text('Encrypted File'),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _exportServerList();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Material(
                          color: AdwaitaColors.darkSidebar,
                          borderRadius: BorderRadius.circular(8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: AdwaitaColors.darkBorder,
                              ),
                            ),
                            leading: const Icon(Icons.file_download_outlined),
                            title: const Text('Import Servers'),
                            subtitle: const Text('Encrypted File'),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _importServerList();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: AdwaitaColors.darkSidebar,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: AdwaitaColors.darkBorder),
                      ),
                      leading: const Icon(LucideIcons.info),
                      title: const Text('About Termeh'),
                      subtitle: const Text(
                        'Version ${AppInfo.version} • ${AppInfo.developer}',
                      ),
                      trailing: const Icon(LucideIcons.chevronRight),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AboutScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: AdwaitaColors.darkSidebar,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: AdwaitaColors.darkBorder),
                      ),
                      leading: const Icon(LucideIcons.lock),
                      title: const Text('Master Key'),
                      trailing: const Icon(LucideIcons.chevronRight),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showChangeMasterKeyDialog();
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: FilledButton(
                      onPressed: () async {
                        final newWidth =
                            double.tryParse(widthController.text) ?? 1000.0;
                        final newHeight =
                            double.tryParse(heightController.text) ?? 700.0;
                        await _storageService.saveWindowWidth(newWidth);
                        await _storageService.saveWindowHeight(newHeight);
                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        _showAppSnackBar(
                          'Settings saved.',
                          SnackBarKind.info,
                        );
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      widthController.dispose();
      heightController.dispose();
    });
  }

  PopupMenuItem<Color> _buildColorOption(
    String name,
    Color color,
    Color selectedColor,
  ) {
    return PopupMenuItem<Color>(
      value: color,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (selectedColor.toARGB32() == color.toARGB32()) ...[
            const Spacer(),
            Icon(LucideIcons.check, size: 16, color: AdwaitaColors.accent),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<int> _buildGraceOption(int minutes, int selectedMinutes) {
    return PopupMenuItem<int>(
      value: minutes,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Text(
            _unlockGraceLabel(minutes),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (selectedMinutes == minutes) ...[
            const Spacer(),
            Icon(LucideIcons.check, size: 16, color: AdwaitaColors.accent),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  String _unlockGraceLabel(int minutes) {
    if (minutes <= 0) return 'Always ask';
    if (minutes == 1) return '1 minute';
    return '$minutes minutes';
  }

  void _showChangeMasterKeyDialog() {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    var busy = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Listener(
          onPointerDown: (_) => _markActivity(),
          onPointerSignal: (_) => _markActivity(),
          child: Container(
            decoration: BoxDecoration(
              color: AdwaitaColors.darkView,
              border: Border.all(color: AdwaitaColors.darkBorder),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              left: 18,
              right: 18,
              top: 12,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Change Master Key',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        onPressed:
                            busy ? null : () => Navigator.pop(sheetContext),
                        icon: const Icon(LucideIcons.x),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildTextField(
                    currentController,
                    'Current Master Key',
                    LucideIcons.lock,
                    '',
                    isPassword: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    newController,
                    'New Master Key',
                    LucideIcons.lock,
                    '',
                    isPassword: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    confirmController,
                    'Confirm New Master Key',
                    LucideIcons.lock,
                    '',
                    isPassword: true,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: AdwaitaColors.destructive,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final currentKey = currentController.text;
                              final newKey = newController.text;
                              final confirmKey = confirmController.text;

                              if (newKey.length < 8) {
                                setSheetState(
                                    () => error = 'Use at least 8 characters.');
                                return;
                              }
                              if (newKey != confirmKey) {
                                setSheetState(
                                    () => error = 'The keys do not match.');
                                return;
                              }

                              setSheetState(() {
                                busy = true;
                                error = null;
                              });

                              final changed =
                                  await _masterKeyService.changeMasterKey(
                                currentKey,
                                newKey,
                                onMacVaultMigrated:
                                    _storageService.migrateMacVault,
                              );
                              if (!sheetContext.mounted) return;
                              if (!changed) {
                                setSheetState(() {
                                  busy = false;
                                  error = 'Incorrect current master key.';
                                });
                                return;
                              }

                              Navigator.pop(sheetContext);
                              if (!mounted) return;
                              _showAppSnackBar(
                                'Master key changed.',
                                SnackBarKind.success,
                              );
                            },
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Change'),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      currentController.dispose();
      newController.dispose();
      confirmController.dispose();
    });
  }

  void _showConnectionSheet([SshConnection? connection]) {
    final nameController = TextEditingController(text: connection?.name);
    final hostController = TextEditingController(text: connection?.host);
    final portController =
        TextEditingController(text: connection?.port.toString() ?? '22');
    final userController = TextEditingController(text: connection?.username);
    final groupController = TextEditingController(text: connection?.group);
    final passController = TextEditingController(text: connection?.password);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheetContext) => Listener(
        onPointerDown: (_) => _markActivity(),
        onPointerSignal: (_) => _markActivity(),
        child: Container(
          decoration: BoxDecoration(
            color: AdwaitaColors.darkView,
            border: Border.all(color: AdwaitaColors.darkBorder),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            left: 18,
            right: 18,
            top: 12,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      connection == null ? 'New Server' : 'Edit Server',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(LucideIcons.x),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildTextField(nameController, 'Server Name', LucideIcons.tag,
                    'e.g. Production'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: _buildTextField(hostController, 'Host',
                            LucideIcons.server, '192.168.1.1')),
                    const SizedBox(width: 10),
                    Expanded(
                        flex: 1,
                        child: _buildTextField(
                            portController, 'Port', null, '22',
                            isNumber: true)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(
                    userController, 'Username', LucideIcons.user, 'root'),
                const SizedBox(height: 12),
                _buildTextField(
                    passController, 'Password', LucideIcons.lock, '••••••••',
                    isPassword: true),
                const SizedBox(height: 12),
                _buildTextField(groupController, 'Group', LucideIcons.folder,
                    'Work, Personal, etc.'),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: FilledButton(
                    onPressed: () async {
                      if (nameController.text.isEmpty ||
                          hostController.text.isEmpty ||
                          userController.text.isEmpty) {
                        _showAppSnackBar(
                          'Please fill all required fields.',
                          SnackBarKind.error,
                        );
                        return;
                      }
                      final port = int.tryParse(portController.text) ?? 22;
                      final sameServer = connection != null &&
                          connection.host == hostController.text &&
                          connection.port == port;
                      final conn = SshConnection(
                        id: connection?.id ?? const Uuid().v4(),
                        name: nameController.text,
                        host: hostController.text,
                        port: port,
                        username: userController.text,
                        group: groupController.text.trim(),
                        password: passController.text,
                        hostKeyType: sameServer ? connection.hostKeyType : null,
                        hostKeyFingerprint:
                            sameServer ? connection.hostKeyFingerprint : null,
                      );

                      if (connection == null) {
                        await _storageService.addConnection(conn);
                      } else {
                        await _storageService.updateConnection(conn);
                      }

                      _loadConnections();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: Text(
                      connection == null ? 'Add Server' : 'Save Changes',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      nameController.dispose();
      hostController.dispose();
      portController.dispose();
      userController.dispose();
      groupController.dispose();
      passController.dispose();
    });
  }

  Widget _buildTextField(TextEditingController controller, String label,
      IconData? icon, String hint,
      {bool isPassword = false, bool isNumber = false}) {
    return TextFormField(
      controller: controller,
      onChanged: (_) => _markActivity(),
      obscureText: isPassword,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      ),
    );
  }

  PopupMenuItem<int> _buildAutoLockOption(int minutes, int selectedMinutes) {
    return PopupMenuItem<int>(
      value: minutes,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Text(
            _autoLockLabel(minutes),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (selectedMinutes == minutes) ...[
            const Spacer(),
            Icon(LucideIcons.check, size: 16, color: AdwaitaColors.accent),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  String _autoLockLabel(int minutes) {
    if (minutes <= 0) return 'Never lock';
    if (minutes == 1) return '1 minute';
    return '$minutes minutes';
  }

  Widget _buildConnectionTile(
    BuildContext context,
    ThemeData theme,
    SshConnection conn, {
    required int index,
    required bool showDragHandle,
  }) {
    final isConnected = _sessionManager.isConnected(conn.id);
    final tileColor = isConnected
        ? AdwaitaColors.success.withValues(alpha: 0.16)
        : theme.colorScheme.primary.withValues(alpha: 0.16);
    final iconColor =
        isConnected ? AdwaitaColors.success : theme.colorScheme.primary;
    final subtitleText = conn.group.trim().isEmpty
        ? '${conn.username}@${conn.host}:${conn.port}'
        : '${conn.group.trim()} • ${conn.username}@${conn.host}:${conn.port}';

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AdwaitaColors.darkBorder),
      ),
      child: InkWell(
        onTap: () => _openConnection(conn),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.server,
                  color: iconColor,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conn.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              if (isConnected) ...[
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _openConnection(conn),
                  icon: const Icon(LucideIcons.terminal, size: 16),
                  label: const Text('Open'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(LucideIcons.logOut),
                  onPressed: () => _disconnectConnection(conn),
                  tooltip: 'Disconnect',
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (showDragHandle)
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: 'Drag to reorder',
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        LucideIcons.gripVertical,
                        color: Colors.white12,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(LucideIcons.ellipsis),
                onPressed: () => _showOptions(conn),
                style: IconButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionGroupSection(
    BuildContext context,
    ThemeData theme,
    _ConnectionGroup group,
  ) {
    final groupBorderColor = AdwaitaColors.darkBorder.withValues(alpha: 0.95);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Row(
            children: [
              Text(
                group.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AdwaitaColors.darkMuted,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AdwaitaColors.darkSidebar,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: groupBorderColor),
                ),
                child: Text(
                  '${group.connections.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdwaitaColors.darkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (oldIndex, newIndex) =>
              _reorderConnectionsInGroup(group.key, oldIndex, newIndex),
          itemCount: group.connections.length,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final value = Curves.easeInOut.transform(animation.value);
                  return Transform.scale(
                    scale: 1.0 + (0.02 * value),
                    child: child,
                  );
                },
                child: child,
              ),
            );
          },
          itemBuilder: (context, index) {
            final conn = group.connections[index];
            return KeyedSubtree(
              key: ValueKey(conn.id),
              child: _buildConnectionTile(
                context,
                theme,
                conn,
                index: index,
                showDragHandle: true,
              ),
            );
          },
        ),
      ],
    );
  }

  void _showOptions(SshConnection conn) {
    final isConnected = _sessionManager.isConnected(conn.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AdwaitaColors.darkView,
          border: Border.all(color: AdwaitaColors.darkBorder),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(LucideIcons.terminal),
              title: const Text('Open Terminal'),
              onTap: () {
                Navigator.pop(context);
                _openConnection(conn);
              },
            ),
            if (isConnected)
              ListTile(
                leading: const Icon(LucideIcons.refreshCw),
                title: const Text('Reconnect'),
                subtitle:
                    const Text('Close the current session and open a new one'),
                onTap: () async {
                  Navigator.pop(context);
                  await _openConnection(conn, reconnect: true);
                },
              ),
            if (isConnected)
              ListTile(
                leading:
                    Icon(LucideIcons.logOut, color: AdwaitaColors.destructive),
                title: Text('Disconnect',
                    style: TextStyle(color: AdwaitaColors.destructive)),
                onTap: () async {
                  Navigator.pop(context);
                  await _disconnectConnection(conn);
                },
              ),
            ListTile(
              leading: const Icon(LucideIcons.pencil),
              title: const Text('Edit Server'),
              onTap: () {
                Navigator.pop(context);
                _showConnectionSheet(conn);
              },
            ),
            ListTile(
              leading:
                  Icon(LucideIcons.trash2, color: AdwaitaColors.destructive),
              title: Text('Delete Server',
                  style: TextStyle(color: AdwaitaColors.destructive)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Connection'),
                    content:
                        Text('Are you sure you want to delete "${conn.name}"?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('Delete',
                            style: TextStyle(color: AdwaitaColors.destructive)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _storageService.deleteConnection(conn.id);
                  _loadConnections();
                }
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupedConnections = _groupedConnections();
    return Listener(
      onPointerDown: (_) => _markActivity(),
      onPointerMove: (_) => _markActivity(),
      onPointerSignal: (_) => _markActivity(),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Termeh'),
          leadingWidth: 64,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: SvgPicture.asset(
                  'assets/icon/icon.svg',
                  semanticsLabel: 'Termeh logo',
                ),
              ),
            ),
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => _showConnectionSheet(),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('New'),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(LucideIcons.lock),
              onPressed: widget.onLockRequested,
              tooltip: 'Lock',
              style: IconButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(LucideIcons.settings),
              onPressed: _showSettings,
              tooltip: 'Settings',
              style: IconButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            if (groupedConnections.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.terminal,
                        size: 64,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'No saved servers',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: AdwaitaColors.darkMuted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () => _showConnectionSheet(),
                        child: const Text('Add Connection'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(18),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0;
                              i < groupedConnections.length;
                              i++) ...[
                            _buildConnectionGroupSection(
                              context,
                              theme,
                              groupedConnections[i],
                            ),
                            if (i != groupedConnections.length - 1)
                              const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum SnackBarKind {
  success,
  error,
  info,
}

class _ConnectionGroup {
  final String key;
  final String name;
  final List<SshConnection> connections;

  _ConnectionGroup({
    required this.key,
    required this.name,
    required this.connections,
  });
}
