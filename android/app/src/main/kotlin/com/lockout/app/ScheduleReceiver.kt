package com.lockout.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import java.util.Calendar

// Handles scheduled start/stop alarms. Each alarm reschedules itself for the
// next day so the schedule repeats daily without any intervention.
class ScheduleReceiver : BroadcastReceiver() {

    companion object {
        private const val ACTION_START = "com.lockout.SCHEDULE_START"
        private const val ACTION_STOP = "com.lockout.SCHEDULE_STOP"
        private const val EXTRA_PROFILE_ID = "profile_id"
        private const val NOTIF_CHANNEL_ID = "lockout_schedule"
        private const val NOTIF_ID = 1001

        fun scheduleAll(ctx: Context, profile: ScheduledProfile) {
            scheduleAlarm(ctx, profile.id, profile.startHH, profile.startMM, isStart = true)
            scheduleAlarm(ctx, profile.id, profile.endHH, profile.endMM, isStart = false)
        }

        fun cancel(ctx: Context, profileId: String) {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(makePendingIntent(ctx, profileId, isStart = true))
            am.cancel(makePendingIntent(ctx, profileId, isStart = false))
        }

        fun canScheduleExact(ctx: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            return am.canScheduleExactAlarms()
        }

        private fun scheduleAlarm(ctx: Context, profileId: String, hh: Int, mm: Int, isStart: Boolean) {
            val triggerMs = nextOccurrenceMs(hh, mm)
            val pi = makePendingIntent(ctx, profileId, isStart)
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pi)
            }
        }

        private fun makePendingIntent(ctx: Context, profileId: String, isStart: Boolean): PendingIntent {
            val action = if (isStart) ACTION_START else ACTION_STOP
            val requestCode = (profileId.hashCode() and 0x3FFFFFFF) * 2 + (if (isStart) 0 else 1)
            val intent = Intent(ctx, ScheduleReceiver::class.java).apply {
                this.action = action
                putExtra(EXTRA_PROFILE_ID, profileId)
            }
            return PendingIntent.getBroadcast(
                ctx, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        fun nextOccurrenceMs(hh: Int, mm: Int): Long {
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hh)
                set(Calendar.MINUTE, mm)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= System.currentTimeMillis()) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }
            return cal.timeInMillis
        }

        fun isCurrentlyInWindow(startHH: Int, startMM: Int, endHH: Int, endMM: Int): Boolean {
            val now = Calendar.getInstance()
            val nowMins = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val startMins = startHH * 60 + startMM
            val endMins = endHH * 60 + endMM
            return if (startMins < endMins) {
                nowMins in startMins until endMins
            } else {
                // Window crosses midnight
                nowMins >= startMins || nowMins < endMins
            }
        }
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        val profileId = intent.getStringExtra(EXTRA_PROFILE_ID) ?: return
        when (intent.action) {
            ACTION_START -> handleStart(ctx, profileId)
            ACTION_STOP -> handleStop(ctx, profileId)
        }
    }

    private fun handleStart(ctx: Context, profileId: String) {
        val profile = FlutterPrefs.getAllScheduledProfiles(ctx).find { it.id == profileId }
        val packages = profile?.packages ?: FlutterPrefs.getProfilePackages(ctx, profileId) ?: return

        NativePrefs.clearMissedNotifs(ctx)
        NativePrefs.savePackages(ctx, packages)
        BlockingService.startBlocking(packages)
        FlutterPrefs.setActiveProfileId(ctx, profileId)

        val profileName = FlutterPrefs.getProfileName(ctx, profileId) ?: "Session"
        showStartNotification(ctx, profileName)

        // Reschedule for next day
        if (profile != null) {
            scheduleAlarm(ctx, profileId, profile.startHH, profile.startMM, isStart = true)
        }
    }

    private fun showStartNotification(ctx: Context, profileName: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Schedule",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "Fires when a scheduled blocking session starts" }
            nm.createNotificationChannel(channel)
        }

        val launchIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val pi = PendingIntent.getActivity(
            ctx, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(ctx, NOTIF_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Lockout")
            .setContentText("\"$profileName\" session started")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        nm.notify(NOTIF_ID, notif)
    }

    private fun handleStop(ctx: Context, profileId: String) {
        MissedNotifications.postSummaries(ctx)
        NativePrefs.savePackages(ctx, emptyList())
        BlockingService.stopBlocking()
        FlutterPrefs.setActiveProfileId(ctx, null)

        // Reschedule for next day
        val profile = FlutterPrefs.getAllScheduledProfiles(ctx).find { it.id == profileId }
        if (profile != null) {
            scheduleAlarm(ctx, profileId, profile.endHH, profile.endMM, isStart = false)
        }
    }
}
