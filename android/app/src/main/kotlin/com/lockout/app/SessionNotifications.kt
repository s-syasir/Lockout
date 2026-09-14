package com.lockout.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat

// The "session started" notification - shared by both the scheduled-alarm
// path (ScheduleReceiver) and the manual/NFC path (BlockingChannel), which
// used to only exist for the former.
object SessionNotifications {

    private const val CHANNEL_ID = "lockout_schedule"
    private const val NOTIF_ID = 1001
    private const val TEMP_NOTIF_ID = 1002
    const val NAG_NOTIF_ID = 1003

    fun showStart(ctx: Context, profileName: String) {
        ensureChannel(ctx)
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Lockout")
            .setContentText("\"$profileName\" session started")
            .setAutoCancel(true)
            .setContentIntent(launchAppIntent(ctx))
            .build()
        notify(ctx, NOTIF_ID, notif)
    }

    fun showResumed(ctx: Context, profileName: String) {
        ensureChannel(ctx)
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Lockout")
            .setContentText("\"$profileName\" blocking resumed automatically")
            .setAutoCancel(true)
            .setContentIntent(launchAppIntent(ctx))
            .build()
        notify(ctx, NOTIF_ID, notif)
    }

    fun showTempUnblock(ctx: Context, profileName: String, minutes: Int) {
        ensureChannel(ctx)
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Lockout")
            .setContentText("\"$profileName\" unblocked for $minutes min — resumes automatically")
            .setAutoCancel(true)
            .setContentIntent(launchAppIntent(ctx))
            .build()
        notify(ctx, TEMP_NOTIF_ID, notif)
    }

    // Recurring nudge while a profile was stopped unlimited outside its own
    // schedule window - tapping it re-bricks immediately via RebrickReminderReceiver.
    fun showNag(ctx: Context, profileId: String, profileName: String) {
        ensureChannel(ctx)
        val pi = PendingIntent.getBroadcast(
            ctx, profileId.hashCode(), RebrickReminderReceiver.rebrickNowIntent(ctx, profileId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Lockout")
            .setContentText("Still unblocked outside \"$profileName\"'s schedule — tap to re-lock")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        notify(ctx, NAG_NOTIF_ID, notif)
    }

    fun cancelNag(ctx: Context) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NAG_NOTIF_ID)
    }

    private fun launchAppIntent(ctx: Context): PendingIntent {
        val launchIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        return PendingIntent.getActivity(
            ctx, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun notify(ctx: Context, id: Int, notif: android.app.Notification) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, notif)
    }

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Schedule",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "Fires when a blocking session starts, resumes, or is temporarily paused" }
            )
        }
    }
}
