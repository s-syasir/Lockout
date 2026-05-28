package com.lockout.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// On boot, reschedules all profile alarms and immediately starts blocking
// for any profile whose scheduled window is currently active.
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

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
