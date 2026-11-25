import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/blur_engine.dart';
import 'services/detector_service.dart';
import 'ui/affirmation_gate.dart';
import 'ui/block_list_screen.dart';
import 'ui/blockp_theme.dart';
import 'ui/calm_screen.dart';
import 'ui/home_screen.dart';
import 'ui/permissions_screen.dart';
import 'ui/premium_screen.dart';
import 'ui/support_screen.dart';
import 'ui/theme.dart';

/// Entrypoint for the headless engine the accessibility service starts.
///
/// Every screenshot is analysed by the same Dart code the UI and tests use;
/// Kotlin only captures pixels and draws the returned regions.
@pragma('vm:entry-point')
void detectorMain() {
  runDetectorEngine();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads preferences and the native protection status. Even if this fails the
  // app still starts and shows the problem instead of crashing on a black
  // screen.
  await blurEngine.init();
  // Only the real app starts the watchdog; widget tests would be left with a
  // pending timer.
  blurEngine.startWatchdog();
  runApp(const BasirahApp());
}

class BasirahApp extends StatelessWidget {
  const BasirahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Basirah (بَصِيرَة)',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      builder: (context, child) => child ?? const SizedBox.shrink(),
      home: const RootShell(),
    );
  }
}

enum _Tab { dashboard, blockList, premium, calm, support }

/// Keeps tab state alive while switching with the bottom navigation bar, and
/// asks for the accessibility permission on a device that does not have it.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  _Tab _tab = _Tab.dashboard;
  bool _setupSkipped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!blurEngine.isInitialized) {
      blurEngine.init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Accessibility and device-admin are granted in system Settings, so the
  /// status read on launch is stale by the time the user comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) blurEngine.refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay = isDark
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Color(0xFF1B2531),
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Color(0xFFEAF1FE),
            systemNavigationBarIconBrightness: Brightness.dark,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: blurEngine.initError != null && !blurEngine.isInitialized
          ? _InitFailure(message: blurEngine.initError!)
          : ListenableBuilder(
              listenable: blurEngine,
              builder: (context, _) {
                final status = blurEngine.status;
                final needsSetup = status.supported &&
                    !status.accessibilityEnabled &&
                    !_setupSkipped;
                if (needsSetup) {
                  return PermissionsScreen(
                    onSkip: () => setState(() => _setupSkipped = true),
                  );
                }
                // After the configured time the app opens on the morning
                // affirmations instead of the dashboard.
                if (blurEngine.needsMorningAffirmations) {
                  return const MorningAffirmationsGate();
                }
                return Scaffold(
                  // The bar is docked, not floating: the scaffold reserves its
                  // height so it never covers the last card on a tab.
                  extendBody: false,
                  backgroundColor: context.bp.canvas,
                  body: IndexedStack(
                    index: _tab.index,
                    children: [
                      HomeScreen(
                        onOpenTab: (index) =>
                            setState(() => _tab = _Tab.values[index]),
                      ),
                      const BlockListScreen(),
                      const PremiumScreen(),
                      const CalmScreen(),
                      const SupportScreen(),
                    ],
                  ),
                  bottomNavigationBar: BpBottomBar(
                    index: _tab.index,
                    onSelected: (index) =>
                        setState(() => _tab = _Tab.values[index]),
                  ),
                );
              },
            ),
    );
  }
}

class _InitFailure extends StatelessWidget {
  final String message;
  const _InitFailure({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bp.canvas,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 42, color: context.bp.ink),
              const SizedBox(height: 12),
              Text('Basirah could not start', style: context.title),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.body,
              ),
              const SizedBox(height: 16),
              BpButton(label: 'Retry', onPressed: blurEngine.init),
            ],
          ),
        ),
      ),
    );
  }
}
