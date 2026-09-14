package com.lockout.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Fires once, N minutes after a schedule-window unblock, and silently
// re-bricks the profile so the user doesn't have to remember to.
class TempUnblockReceiver : BroadcastReceiver() {

    companion object {
        private const val ACTION_EXPIRE = "com.lockout.TEMP_UNBLOCK_EXPIRE"
        private const val EXTRA_PROFILE_ID = "profile_id"

        fun schedule(ctx: Context, profileId: String, minutes: Int) {
            val triggerMs = System.currentTimeMillis() + minutes * 60_000L
            NativePrefs.saveTempUnblock(ctx, profileId, triggerMs)
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pendingIntent(ctx, profileId))
        }

        // Cancels whatever temp-unblock is pending, regardless of which profile it's for.
        fun cancelAny(ctx: Context) {
            val profileId = NativePrefs.getTempUnblockProfileId(ctx) ?: return
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pendingIntent(ctx, profileId))
            NativePrefs.clearTempUnblock(ctx)
        }

        private fun pendingIntent(ctx: Context, profileId: String): PendingIntent {
            val intent = Intent(ctx, TempUnblockReceiver::class.java).apply {
                action = ACTION_EXPIRE
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
        // Stale alarm (already cancelled/superseded) - ignore.
        if (NativePrefs.getTempUnblockProfileId(ctx) != profileId) return
        NativePrefs.clearTempUnblock(ctx)

        // Another profile took over in the meantime - don't clobber it.
        if (FlutterPrefs.getActiveProfileId(ctx) != profileId) return

        val packages = FlutterPrefs.getProfilePackages(ctx, profileId) ?: return
        NativePrefs.savePackages(ctx, packages)
        BlockingService.startBlocking(packages)

        val profileName = FlutterPrefs.getProfileName(ctx, profileId) ?: "Session"
        SessionNotifications.showResumed(ctx, profileName)
    }
}
