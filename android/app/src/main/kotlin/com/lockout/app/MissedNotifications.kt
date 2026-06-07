package com.lockout.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import org.json.JSONObject

object MissedNotifications {

    private const val CHANNEL_ID = "lockout_missed"

    fun postSummaries(ctx: Context) {
        val arr = NativePrefs.loadMissedNotifs(ctx)
        if (arr.length() == 0) return

        val byPkg = mutableMapOf<String, MutableList<JSONObject>>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            byPkg.getOrPut(obj.getString("pkg")) { mutableListOf() }.add(obj)
        }

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(nm)

        for ((pkg, notifs) in byPkg) {
            val appName = notifs.first().getString("app")
            val count = notifs.size
            val latest = notifs.last()
            val latestTitle = latest.optString("title")
            val latestText = latest.optString("text")

            val contentTitle = if (count == 1) appName else "$appName ($count)"
            val contentText = when {
                count == 1 && latestTitle.isNotEmpty() && latestText.isNotEmpty() -> "$latestTitle: $latestText"
                count == 1 -> latestTitle.ifEmpty { latestText }
                else -> "$count notifications while locked out"
            }

            val style = NotificationCompat.InboxStyle().setBigContentTitle(contentTitle)
            notifs.takeLast(5).forEach { n ->
                val t = n.optString("title")
                val b = n.optString("text")
                val line = if (t.isNotEmpty() && b.isNotEmpty()) "$t: $b" else t.ifEmpty { b }
                if (line.isNotEmpty()) style.addLine(line)
            }

            val launchIntent = ctx.packageManager.getLaunchIntentForPackage(pkg)
            val pi = launchIntent?.let {
                PendingIntent.getActivity(
                    ctx, pkg.hashCode(), it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

            val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(contentTitle)
                .setContentText(contentText)
                .setStyle(style)
                .setAutoCancel(true)
                .apply { if (pi != null) setContentIntent(pi) }
                .build()

            nm.notify(pkg.hashCode(), notif)
        }

        NativePrefs.clearMissedNotifs(ctx)
    }

    private fun ensureChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Missed notifications",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "Summary of notifications received during a lockout session" }
            )
        }
    }
}
