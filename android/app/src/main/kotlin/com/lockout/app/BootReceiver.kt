package com.lockout.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// On boot, reschedules all profile alarms and immediately starts blocking
// for any profile whose scheduled window is currently active.
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        // AlarmManager alarms don't survive reboot. A temp-unblock that was
        // mid-countdown when the phone went down should resume blocking now
        // rather than being lost — "resumes automatically" is the whole point.
        val tempProfileId = FlutterPrefs.getActiveProfileId(ctx)
            ?.takeIf { it == NativePrefs.getTempUnblockProfileId(ctx) }
        if (tempProfileId != null) {
            NativePrefs.clearTempUnblock(ctx)
            val packages = FlutterPrefs.getProfilePackages(ctx, tempProfileId)
            if (packages != null) {
                NativePrefs.savePackages(ctx, packages)
                BlockingService.startBlocking(packages)
            }
        }

        // Same for an in-flight rebrick reminder loop - re-arm it so the nag continues.
        val nagProfileId = NativePrefs.getNagProfileId(ctx)
        if (nagProfileId != null) {
            RebrickReminderReceiver.start(ctx, nagProfileId)
        }

        val profiles = FlutterPrefs.getAllScheduledProfiles(ctx)
        for (profile in profiles) {
            ScheduleReceiver.scheduleAll(ctx, profile)

            if (ScheduleReceiver.isCurrentlyInWindow(
                    profile.startHH, profile.startMM,
                    profile.endHH, profile.endMM
                )
            ) {
                NativePrefs.savePackages(ctx, profile.packages)
                BlockingService.startBlocking(profile.packages)
                FlutterPrefs.setActiveProfileId(ctx, profile.id)
            }
        }
    }
}
