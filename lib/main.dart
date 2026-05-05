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
    final endTime = storage.getSessionEndTime();

    // Don't resume a session whose timer already expired while the phone was off.
    if (endTime != null && DateTime.now().isAfter(endTime)) {
      await storage.clearActiveSession();
      // In DPC mode, also lift quiet mode since the timed session has ended.
      if (storage.dpcModeEnabled) await BlockingService.dpcSetQuietMode(false);
    } else if (storage.dpcModeEnabled) {
      // DPC mode: re-arm quiet mode (the work profile may have been re-enabled
      // while the phone was off or the app was killed).
      await BlockingService.dpcSetQuietMode(true);
    } else if (profile != null && profile.blockedPackages.isNotEmpty) {
      await BlockingService.startBlocking(profile.blockedPackages);
    } else {
      await storage.clearActiveSession();
    }
  }

  runApp(LockoutApp(storage: storage));
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
