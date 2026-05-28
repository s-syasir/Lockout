package com.lockout.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

// AccessibilityService that watches for foreground app changes.
// When a blocked package comes to the foreground, we send the user home.
//
// This is the entire blocking mechanism — no polling, no GMS, no Firebase.
// Pure AOSP. Survives microG, GrapheneOS, CalyxOS.
//
// Architecture:
//   Flutter ──MethodChannel──► BlockingChannel ──► BlockingService (singleton)
//                                                        │
//                                              onAccessibilityEvent()
//                                                        │
//                                         blocked? → sendHome()
class BlockingService : AccessibilityService() {

    override fun onServiceConnected() {
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            notificationTimeout = 100
        }
        instance = this

        // Restore blocked packages persisted before a service restart.
        // Must use applicationContext directly — BlockingChannel.context is only
        // initialised when MainActivity runs, which may not have happened yet
        // (e.g. service restarted by Android on boot before the Flutter app launches).
        val saved = NativePrefs.loadPackages(applicationContext)
        if (saved.isNotEmpty()) {
            blockedPackages = saved
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return

        // Ignore our own package — we'd lock ourselves out otherwise.
        if (pkg == packageName) return

        if (blockedPackages.contains(pkg)) {
            sendHome()
        }
    }

    private fun sendHome() {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    override fun onInterrupt() {
        // Required override — nothing to do here.
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    companion object {
        var instance: BlockingService? = null
            private set

        var blockedPackages: Set<String> = emptySet()
            private set

        fun startBlocking(packages: List<String>) {
            blockedPackages = packages.toSet()
        }

        fun stopBlocking() {
            blockedPackages = emptySet()
        }

        val isRunning: Boolean get() = instance != null
        val isBlocking: Boolean get() = isRunning && blockedPackages.isNotEmpty()
    }
}
