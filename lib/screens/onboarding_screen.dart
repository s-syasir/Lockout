import 'package:flutter/material.dart';
import '../services/blocking_service.dart';

// First-run screen. Explains what Lockout needs and why,
// then sends the user to Accessibility Settings.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 24),
              Text(
                'One permission needed',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              const Text(
                'Lockout uses Android\'s Accessibility Service to detect '
                'when a blocked app opens and redirect you away from it.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'No data ever leaves your phone. Lockout has no internet '
                'permission and no analytics.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              // iOS note
              const Text(
                'On iOS, Lockout uses Screen Time (FamilyControls) instead '
                'of Accessibility Service.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const Spacer(),
              const _Step(
                number: '1',
                text: 'Tap "Open Settings" below',
              ),
              const SizedBox(height: 12),
              const _Step(
                number: '2',
                text: 'Find "Lockout" in the list',
              ),
              const SizedBox(height: 12),
              const _Step(
                number: '3',
                text: 'Toggle it on, then come back',
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await BlockingService.openAccessibilitySettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('I\'ll do this later'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          child: Text(number, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
  }
}
