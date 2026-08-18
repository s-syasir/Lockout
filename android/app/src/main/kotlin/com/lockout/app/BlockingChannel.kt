package com.lockout.app

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Process
import android.os.UserHandle
import android.os.UserManager
import android.provider.Settings
import android.text.TextUtils
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

// MethodChannel bridge between Flutter and the native blocking layer.
// Channel name must match BlockingService.dart's _channel constant.
object BlockingChannel : MethodChannel.MethodCallHandler {

    private const val CHANNEL = "com.lockout/blocking"

    private lateinit var context: Context

    // Set by MainActivity when an NFC NDEF_DISCOVERED intent arrives.
    // Flutter reads and clears this via getPendingNfcTag.
    var pendingNfcProfileId: String? = null

    // Set by MainActivity so BlockingChannel can start the provisioning
    // activity without holding an Activity reference itself.
    var startProvisioningFn: (() -> Unit)? = null

    // Pending result for an in-flight dpcProvisionManagedProfile call.
    private var pendingProvisionResult: MethodChannel.Result? = null

    // Set by MainActivity so BlockingChannel can trigger the POST_NOTIFICATIONS
    // system prompt without holding an Activity reference itself.
    var requestNotificationPermissionFn: (() -> Unit)? = null

    // Pending result for an in-flight requestNotificationPermission call.
    private var pendingNotifPermResult: MethodChannel.Result? = null

    fun register(ctx: Context, messenger: BinaryMessenger) {
        context = ctx.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    // Called by MainActivity.onActivityResult after the provisioning flow completes.
    fun resolveProvisioningResult(success: Boolean) {
        pendingProvisionResult?.success(success)
        pendingProvisionResult = null
    }

    // Called by MainActivity.onRequestPermissionsResult after the user responds
    // to the POST_NOTIFICATIONS system prompt.
    fun resolveNotificationPermissionResult(granted: Boolean) {
        pendingNotifPermResult?.success(granted)
        pendingNotifPermResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startBlocking" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                // Null when this is a mid-session package-list update (e.g.
                // editing the active profile), not a genuine new session -
                // only post the start notification for real starts.
                val profileName = call.argument<String>("profileName")
                if (!isAccessibilityEnabled()) {
                    result.error("PERMISSION_DENIED", "Accessibility Service not enabled", null)
                    return
                }
                NativePrefs.clearMissedNotifs(context)
                persistBlockedPackages(packages)
                BlockingService.startBlocking(packages)
                if (profileName != null) SessionNotifications.showStart(context, profileName)
                result.success(true)
            }
            "stopBlocking" -> {
                MissedNotifications.postSummaries(context)
                persistBlockedPackages(emptyList())
                BlockingService.stopBlocking()
                result.success(null)
            }
            "isBlocking" -> result.success(BlockingService.isBlocking)
            "hasAccessibilityPermission" -> result.success(isAccessibilityEnabled())
            "openAccessibilitySettings" -> {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                result.success(null)
            }
            "getInstalledApps" -> result.success(getInstalledApps())
            "getAppIcon" -> {
                val packageName = call.argument<String>("packageName") ?: run {
                    result.error("INVALID_ARG", "packageName required", null)
                    return
                }
                result.success(getAppIconBytes(packageName))
            }
            "getPendingNfcTag" -> {
                val id = pendingNfcProfileId
                pendingNfcProfileId = null
                result.success(id)
            }

            // ── DPC / Work Profile ────────────────────────────────────────────
            // Requires Android 9+ (API 28) for quiet mode.
            // The app must be the profile owner of a managed profile.

            "dpcHasManagedProfile" -> result.success(isProfileOwner())

            "dpcIsQuietModeEnabled" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    result.success(false)
                    return
                }
                val handle = getManagedProfileHandle()
                if (handle == null) { result.success(false); return }
                val um = context.getSystemService(Context.USER_SERVICE) as UserManager
                result.success(um.isQuietModeEnabled(handle))
            }

            "dpcSetQuietMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    result.error("UNSUPPORTED", "Requires Android 9+", null)
                    return
                }
                val handle = getManagedProfileHandle()
                if (handle == null) {
                    result.error("NO_PROFILE", "No managed profile found", null)
                    return
                }
                try {
                    val um = context.getSystemService(Context.USER_SERVICE) as UserManager
                    um.requestQuietModeEnabled(enabled, handle)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("DPC_ERROR", e.message, null)
                }
            }

            "dpcProvisionManagedProfile" -> {
                if (isProfileOwner()) {
                    result.success(true)
                    return
                }
                pendingProvisionResult = result
                startProvisioningFn?.invoke() ?: run {
                    pendingProvisionResult = null
                    result.error("NO_ACTIVITY", "Activity not available for provisioning", null)
                }
            }

            "hasNotificationListenerPermission" -> result.success(isNotificationListenerEnabled())
            "openNotificationListenerSettings" -> {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                result.success(null)
            }

            "hasNotificationPermission" -> result.success(hasPostNotificationsPermission())
            "requestNotificationPermission" -> {
                if (hasPostNotificationsPermission()) {
                    result.success(true)
                    return
                }
                pendingNotifPermResult = result
                requestNotificationPermissionFn?.invoke() ?: run {
                    pendingNotifPermResult = null
                    result.error("NO_ACTIVITY", "Activity not available for permission request", null)
                }
            }
            "openAppNotificationSettings" -> {
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                result.success(null)
            }

            // ── Schedule ─────────────────────────────────────────────────────
            "setSchedule" -> {
                val profileId = call.argument<String>("profileId") ?: run {
                    result.error("INVALID_ARG", "profileId required", null)
                    return
                }
                val startHH = call.argument<Int>("startHH") ?: 0
                val startMM = call.argument<Int>("startMM") ?: 0
                val endHH   = call.argument<Int>("endHH")   ?: 0
                val endMM   = call.argument<Int>("endMM")   ?: 0
                val profile = ScheduledProfile(profileId, emptyList(), startHH, startMM, endHH, endMM)
                ScheduleReceiver.scheduleAll(context, profile)
                result.success(null)
            }
            "cancelSchedule" -> {
                val profileId = call.argument<String>("profileId") ?: run {
                    result.error("INVALID_ARG", "profileId required", null)
                    return
                }
                ScheduleReceiver.cancel(context, profileId)
                result.success(null)
            }
            "canScheduleExactAlarms" -> result.success(ScheduleReceiver.canScheduleExact(context))
            "openExactAlarmSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    fun persistBlockedPackages(packages: List<String>) {
        NativePrefs.savePackages(context, packages)
    }

    fun loadPersistedPackages(): Set<String> = NativePrefs.loadPackages(context)

    // POST_NOTIFICATIONS is a runtime permission on API 33+; auto-granted below that.
    private fun hasPostNotificationsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return enabled.contains(context.packageName)
    }

    // Returns whether Lockout's AccessibilityService is enabled in system settings.
    private fun isAccessibilityEnabled(): Boolean {
        val expectedComponent = "${context.packageName}/${BlockingService::class.java.name}"
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expectedComponent, ignoreCase = true)) return true
        }
        return false
    }

    // Returns all user-installed apps (excludes pure system apps and our own package).
    // Cached in BlockingService.dart, so this only runs once per session.
    @Suppress("DEPRECATION")
    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = context.packageManager
        return pm.getInstalledApplications(PackageManager.GET_META_DATA)
            .filter { app ->
                app.packageName != context.packageName &&
                (app.flags and ApplicationInfo.FLAG_SYSTEM == 0 ||
                 app.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0)
            }
            .mapNotNull { app ->
                val label = try {
                    pm.getApplicationLabel(app).toString()
                } catch (_: Exception) {
                    return@mapNotNull null
                }
                mapOf("packageName" to app.packageName, "appName" to label)
            }
    }

    // ── DPC helpers ──────────────────────────────────────────────────────────

    // Returns true if this app is the profile owner of any managed profile.
    private fun isProfileOwner(): Boolean {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isProfileOwnerApp(context.packageName)
    }

    // Returns the UserHandle of our managed profile, or null if none exists.
    // Looks for any profile that is not the current user — after provisioning
    // via our admin, the only such profile will be ours.
    private fun getManagedProfileHandle(): UserHandle? {
        val um = context.getSystemService(Context.USER_SERVICE) as UserManager
        val myHandle = Process.myUserHandle()
        return um.userProfiles.firstOrNull { it != myHandle }
    }

    // ── App icon ─────────────────────────────────────────────────────────────

    // Returns 64×64 PNG bytes for an app's launcher icon, or null on failure.
    // Uses Canvas to handle all drawable types (BitmapDrawable, AdaptiveIconDrawable, etc).
    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val drawable = context.packageManager.getApplicationIcon(packageName)
            val size = 64
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            ByteArrayOutputStream().also { stream ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 85, stream)
                bitmap.recycle()
            }.toByteArray()
        } catch (_: Exception) {
            null
        }
    }
}
