package com.lockout.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

// Handles scheduled start/stop alarms, one pair per active weekday. Each
// alarm reschedules itself a week later on receipt, so a per-day schedule
// repeats weekly without any intervention.
class ScheduleReceiver : BroadcastReceiver() {

    companion object {
        private const val ACTION_START = "com.lockout.SCHEDULE_START"
        private const val ACTION_STOP = "com.lockout.SCHEDULE_STOP"
        private const val EXTRA_PROFILE_ID = "profile_id"
        private const val EXTRA_DAY = "day"

        fun scheduleAll(ctx: Context, profile: ScheduledProfile) {
            for (window in profile.days) {
                scheduleAlarm(ctx, profile.id, window.day, window.startHH, window.startMM, isStart = true)
                scheduleAlarm(ctx, profile.id, window.day, window.endHH, window.endMM, isStart = false)
            }
        }

        // Cancels every possible day/start-stop alarm for this profile.
        // Cancelling an alarm that was never set is a harmless no-op, so this
        // doesn't need to know which days were actually active.
        fun cancel(ctx: Context, profileId: String) {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (day in 1..7) {
                am.cancel(makePendingIntent(ctx, profileId, day, isStart = true))
                am.cancel(makePendingIntent(ctx, profileId, day, isStart = false))
            }
        }

        fun canScheduleExact(ctx: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            return am.canScheduleExactAlarms()
        }

        private fun scheduleAlarm(ctx: Context, profileId: String, day: Int, hh: Int, mm: Int, isStart: Boolean) {
            val triggerMs = nextOccurrenceMs(day, hh, mm)
            val pi = makePendingIntent(ctx, profileId, day, isStart)
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pi)
            }
        }

        private fun makePendingIntent(ctx: Context, profileId: String, day: Int, isStart: Boolean): PendingIntent {
            val action = if (isStart) ACTION_START else ACTION_STOP
            // profileId hash gets 16 slots (7 days x 2 directions, rounded up) so
            // different profiles never collide with each other's day/direction alarms.
            val requestCode = (profileId.hashCode() and 0x1FFFFFF) * 16 + day * 2 + (if (isStart) 0 else 1)
            val intent = Intent(ctx, ScheduleReceiver::class.java).apply {
                this.action = action
                putExtra(EXTRA_PROFILE_ID, profileId)
                putExtra(EXTRA_DAY, day)
            }
            return PendingIntent.getBroadcast(
                ctx, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        // Our day numbering is 1=Monday..7=Sunday (matches Dart's DateTime.weekday).
        // java.util.Calendar uses SUNDAY=1..SATURDAY=7 - convert explicitly rather
        // than relying on the two ever lining up.
        private fun toCalendarDayOfWeek(day: Int): Int = if (day == 7) Calendar.SUNDAY else day + 1

        fun currentAppDay(): Int {
            val calDow = Calendar.getInstance().get(Calendar.DAY_OF_WEEK)
            return if (calDow == Calendar.SUNDAY) 7 else calDow - 1
        }

        // Next time this specific weekday+time occurs, today included if it
        // hasn't passed yet.
        fun nextOccurrenceMs(day: Int, hh: Int, mm: Int): Long {
            val targetDow = toCalendarDayOfWeek(day)
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hh)
                set(Calendar.MINUTE, mm)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            while (cal.get(Calendar.DAY_OF_WEEK) != targetDow) {
                cal.add(Calendar.DAY_OF_YEAR, 1)
            }
            if (cal.timeInMillis <= System.currentTimeMillis()) {
                cal.add(Calendar.DAY_OF_YEAR, 7)
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
        val day = intent.getIntExtra(EXTRA_DAY, -1)
        if (day !in 1..7) return
        when (intent.action) {
            ACTION_START -> handleStart(ctx, profileId, day)
            ACTION_STOP -> handleStop(ctx, profileId, day)
        }
    }

    private fun handleStart(ctx: Context, profileId: String, day: Int) {
        val profile = FlutterPrefs.getAllScheduledProfiles(ctx).find { it.id == profileId }
        val packages = profile?.packages ?: FlutterPrefs.getProfilePackages(ctx, profileId) ?: return

        // The schedule itself is bricking - any manual unlimited-stop reminder
        // or leftover temp-unblock timer for this profile is now moot.
        RebrickReminderReceiver.stop(ctx)
        TempUnblockReceiver.cancelAny(ctx)

        NativePrefs.clearMissedNotifs(ctx)
        NativePrefs.savePackages(ctx, packages)
        BlockingService.startBlocking(packages)
        FlutterPrefs.setActiveProfileId(ctx, profileId)

        val profileName = FlutterPrefs.getProfileName(ctx, profileId) ?: "Session"
        SessionNotifications.showStart(ctx, profileName)

        // Reschedule this day's start alarm for next week.
        val window = profile?.days?.find { it.day == day }
        if (window != null) {
            scheduleAlarm(ctx, profileId, day, window.startHH, window.startMM, isStart = true)
        }
    }

    private fun handleStop(ctx: Context, profileId: String, day: Int) {
        MissedNotifications.postSummaries(ctx)
        NativePrefs.savePackages(ctx, emptyList())
        BlockingService.stopBlocking()
        FlutterPrefs.setActiveProfileId(ctx, null)

        // Reschedule this day's stop alarm for next week.
        val profile = FlutterPrefs.getAllScheduledProfiles(ctx).find { it.id == profileId }
        val window = profile?.days?.find { it.day == day }
        if (window != null) {
            scheduleAlarm(ctx, profileId, day, window.endHH, window.endMM, isStart = false)
        }
    }
}
