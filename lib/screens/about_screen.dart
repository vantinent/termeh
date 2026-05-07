// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../theme/adwaita_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdwaitaColors.darkWindow,
      appBar: AppBar(
        title: const Text('About Termeh'),
        backgroundColor: AdwaitaColors.darkHeader,
      ),
      body: Stack(
        children: [
          const _AboutBackdrop(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _HeroPanel(),
                      SizedBox(height: 18),
                      _AboutCopyCard(),
                      SizedBox(height: 18),
                      _LicenseCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutBackdrop extends StatelessWidget {
  const _AboutBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -100,
            child: _GlowBlob(
              size: 240,
              color: AdwaitaColors.accent.withValues(alpha: 0.15),
            ),
          ),
          Positioned(
            top: 170,
            right: -80,
            child: _GlowBlob(
              size: 180,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({
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
            blurRadius: 80,
            spreadRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  Future<void> _launchRepository(BuildContext context) async {
    final launched = await launchUrl(
      Uri.parse(AppInfo.githubUrl),
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the repository.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AdwaitaColors.darkView.withValues(alpha: 0.98),
            AdwaitaColors.darkSidebar.withValues(alpha: 0.94),
          ],
        ),
        border: Border.all(color: AdwaitaColors.darkBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: SvgPicture.asset(
              'assets/icon/icon.svg',
              semanticsLabel: 'Termeh logo',
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppInfo.name,
                  style: textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppInfo.description,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AdwaitaColors.darkMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  FilledButton.icon(
                    onPressed: () => _launchRepository(context),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open GitHub'),
                  ),
                  const SizedBox(width: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _Pill(label: AppInfo.version),
                      _Pill(label: 'Vantinent'),
                    ],
                  ),
                ])
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AboutCopyCard extends StatelessWidget {
  const _AboutCopyCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AdwaitaColors.darkView,
        border: Border.all(color: AdwaitaColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: AdwaitaColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'About Termeh',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Termeh is a modern desktop SSH client built for managing servers '
            'and terminal sessions with a clean and efficient experience. It '
            'provides a fast, lightweight, and distraction-free environment '
            'for developers, system administrators, and power users.',
            style: textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              style: textTheme.bodyLarge?.copyWith(
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.88),
              ),
              children: const [
                TextSpan(
                  text: 'Your privacy and security are a core part of '
                      'Termeh\'s design. ',
                ),
                TextSpan(
                  text: 'All data is stored securely on your local machine, '
                      'and the application does not rely on any '
                      'services for syncing, analytics, or data processing.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: ' Your server credentials and session data remain '
                      'under your control.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Termeh is also fully open source, allowing anyone to inspect the '
            'codebase, contribute improvements, and verify how the '
            'application works. The project focuses on transparency, '
            'simplicity, and giving users complete ownership over their '
            'workflow and data.',
            style: textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  const _LicenseCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AdwaitaColors.darkView,
        border: Border.all(color: AdwaitaColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.gavel_outlined,
                  color: AdwaitaColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'MIT License',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Termeh is released under the MIT License. You can use, copy, '
            'modify, merge, publish, distribute, sublicense, and sell copies '
            'of the software, as described in the repository root LICENSE '
            'file.',
            style: textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Copyright (c) 2026 Vantinent',
            style: textTheme.bodyMedium?.copyWith(
              color: AdwaitaColors.darkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
