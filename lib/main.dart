import 'package:flutter/material.dart';
import 'services/blocking_service.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await StorageService.init();

  if (storage.hasActiveSession) {
    final profileId = storage.getActiveProfileId()!;
    final profile = storage.getProfile(profileId);

    if (storage.dpcModeEnabled) {
      await BlockingService.dpcSetQuietMode(true);
    } else if (profile != null && profile.blockedPackages.isNotEmpty) {
      final ok = await BlockingService.startBlocking(profile.blockedPackages);
      if (!ok) await storage.clearActiveSession();
    } else {
      await storage.clearActiveSession();
    }
  }

  runApp(LockoutApp(storage: storage));

  // Fire-and-forget: shows the system POST_NOTIFICATIONS prompt once per
  // install (Android tracks this itself — a no-op on repeat launches once
  // answered). Without it, session-start and missed-notification summaries
  // silently never appear on Android 13+.
  BlockingService.requestNotificationPermission();
}

class LockoutApp extends StatelessWidget {
  final StorageService storage;
  const LockoutApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lockout',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A2E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A2E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(storage: storage),
    );
  }
}
