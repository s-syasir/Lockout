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

    fun showStart(ctx: Context, profileName: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Schedule",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "Fires when a blocking session starts" }
            )
        }

        val launchIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val pi = PendingIntent.getActivity(
            ctx, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Lockout")
            .setContentText("\"$profileName\" session started")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        nm.notify(NOTIF_ID, notif)
    }
}
