package com.lockout.app

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class LockoutNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notif = sbn ?: return
        val pkg = notif.packageName
        if (!BlockingService.blockedPackages.contains(pkg)) return

        // Group summaries (e.g. WhatsApp's "3 new messages" wrapper) are
        // redundant with the individual conversation notifications that
        // also get posted - recording both would double-count. Still
        // cancel it so it doesn't slip through, just don't log it.
        val isGroupSummary = notif.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0
        if (!isGroupSummary) {
            val (title, text) = extractContent(notif.notification.extras)
            val appName = try {
                @Suppress("DEPRECATION")
                packageManager.getApplicationLabel(
                    packageManager.getApplicationInfo(pkg, 0)
                ).toString()
            } catch (_: Exception) { pkg }
            // Always record something, even if extraction found nothing -
            // a silently-dropped entry here means the missed-notification
            // summary undercounts what was actually suppressed.
            NativePrefs.appendMissedNotif(
                this, pkg, appName,
                title, text.ifEmpty { "New notification" },
                notif.postTime,
            )
        }

        cancelNotification(notif.key)
    }

    // Many apps (WhatsApp included) use MessagingStyle or a custom layout
    // where the plain EXTRA_TITLE/EXTRA_TEXT fields are blank - the real
    // content lives in EXTRA_BIG_TEXT, EXTRA_SUMMARY_TEXT, or the last
    // entry of EXTRA_MESSAGES instead. Try all of them in order.
    private fun extractContent(extras: Bundle): Pair<String, String> {
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString()
            ?: ""

        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.takeIf { it.isNotEmpty() }
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.takeIf { it.isNotEmpty() }
            ?: lastMessagingStyleText(extras)
            ?: extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()
            ?: ""

        return title to text
    }

    @Suppress("DEPRECATION")
    private fun lastMessagingStyleText(extras: Bundle): String? {
        val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return null
        val last = messages.lastOrNull() as? Bundle ?: return null
        return last.getCharSequence("text")?.toString()?.takeIf { it.isNotEmpty() }
    }
}
