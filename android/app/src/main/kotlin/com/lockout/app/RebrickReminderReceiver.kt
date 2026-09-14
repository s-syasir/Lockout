package com.lockout.app

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Nags every ~30 minutes to re-brick a profile that was stopped "unlimited"
// outside its own schedule window - only reposting once the previous nag
// has actually been dismissed, so it doesn't stack notifications.
class RebrickReminderReceiver : BroadcastReceiver() {

    companion object {
        private const val ACTION_CHECK = "com.lockout.NAG_CHECK"
        private const val ACTION_REBRICK_NOW = "com.lockout.NAG_REBRICK_NOW"
        private const val EXTRA_PROFILE_ID = "profile_id"
        private const val INTERVAL_MS = 30 * 60_000L

        fun start(ctx: Context, profileId: String) {
            NativePrefs.saveNagProfile(ctx, profileId)
            scheduleNextCheck(ctx, profileId)
        }

        fun stop(ctx: Context) {
            val profileId = NativePrefs.getNagProfileId(ctx)
            if (profileId != null) {
                val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                am.cancel(checkPendingIntent(ctx, profileId))
            }
            NativePrefs.clearNagProfile(ctx)
            SessionNotifications.cancelNag(ctx)
        }

        fun rebrickNowIntent(ctx: Context, profileId: String): Intent =
            Intent(ctx, RebrickReminderReceiver::class.java).apply {
                action = ACTION_REBRICK_NOW
                putExtra(EXTRA_PROFILE_ID, profileId)
            }

        private fun scheduleNextCheck(ctx: Context, profileId: String) {
            val triggerMs = System.currentTimeMillis() + INTERVAL_MS
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, checkPendingIntent(ctx, profileId))
        }

        private fun checkPendingIntent(ctx: Context, profileId: String): PendingIntent {
            val intent = Intent(ctx, RebrickReminderReceiver::class.java).apply {
                action = ACTION_CHECK
                putExtra(EXTRA_PROFILE_ID, profileId)
            }
            return PendingIntent.getBroadcast(
                ctx, profileId.hashCode() and 0x3FFFFFFF, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        val profileId = intent.getStringExtra(EXTRA_PROFILE_ID) ?: return
        when (intent.action) {
            ACTION_CHECK -> handleCheck(ctx, profileId)
            ACTION_REBRICK_NOW -> handleRebrickNow(ctx, profileId)
        }
    }

    private fun handleCheck(ctx: Context, profileId: String) {
        // Stopped, or superseded by a different profile since this was scheduled.
        if (NativePrefs.getNagProfileId(ctx) != profileId) return

        // Already re-bricked through some other path - stop nagging.
        if (FlutterPrefs.getActiveProfileId(ctx) == profileId && BlockingService.isBlocking) {
            stop(ctx)
            return
        }

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val stillShowing = nm.activeNotifications.any { it.id == SessionNotifications.NAG_NOTIF_ID }
        if (!stillShowing) {
            val profileName = FlutterPrefs.getProfileName(ctx, profileId) ?: "Session"
            SessionNotifications.showNag(ctx, profileId, profileName)
        }
        scheduleNextCheck(ctx, profileId)
    }

    private fun handleRebrickNow(ctx: Context, profileId: String) {
        val packages = FlutterPrefs.getProfilePackages(ctx, profileId) ?: return
        NativePrefs.clearMissedNotifs(ctx)
        NativePrefs.savePackages(ctx, packages)
        BlockingService.startBlocking(packages)
        FlutterPrefs.setActiveProfileId(ctx, profileId)

        val profileName = FlutterPrefs.getProfileName(ctx, profileId) ?: "Session"
        SessionNotifications.showStart(ctx, profileName)
        stop(ctx)
    }
}
