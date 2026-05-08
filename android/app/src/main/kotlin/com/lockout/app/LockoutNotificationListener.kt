package com.lockout.app

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class LockoutNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val pkg = sbn?.packageName ?: return
        if (BlockingService.blockedPackages.contains(pkg)) {
            cancelNotification(sbn.key)
        }
    }
}
