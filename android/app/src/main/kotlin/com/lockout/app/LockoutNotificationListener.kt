package com.lockout.app

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class LockoutNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notif = sbn ?: return
        val pkg = notif.packageName
        if (!BlockingService.blockedPackages.contains(pkg)) return

        val extras = notif.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        if (title.isNotEmpty() || text.isNotEmpty()) {
            val appName = try {
                @Suppress("DEPRECATION")
                packageManager.getApplicationLabel(
                    packageManager.getApplicationInfo(pkg, 0)
                ).toString()
            } catch (_: Exception) { pkg }
            NativePrefs.appendMissedNotif(this, pkg, appName, title, text, notif.postTime)
        }

        cancelNotification(notif.key)
    }
}
