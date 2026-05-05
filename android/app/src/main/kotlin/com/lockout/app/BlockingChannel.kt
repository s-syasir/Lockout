package com.lockout.app

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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

// MethodChannel bridge between Flutter and the native blocking layer.
// Channel name must match BlockingService.dart's _channel constant.
object BlockingChannel : MethodChannel.MethodCallHandler {

    private const val CHANNEL = "com.lockout/blocking"
    private const val PREFS_NAME = "lockout"
    private const val PREFS_KEY_PACKAGES = "blocked_packages"

    private lateinit var context: Context

    // Set by MainActivity when an NFC NDEF_DISCOVERED intent arrives.
    // Flutter reads and clears this via getPendingNfcTag.
    var pendingNfcProfileId: String? = null

    // Set by MainActivity so BlockingChannel can start the provisioning
    // activity without holding an Activity reference itself.
    var startProvisioningFn: (() -> Unit)? = null

    // Pending result for an in-flight dpcProvisionManagedProfile call.
    private var pendingProvisionResult: MethodChannel.Result? = null

    fun register(ctx: Context, messenger: BinaryMessenger) {
        context = ctx.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    // Called by MainActivity.onActivityResult after the provisioning flow completes.
    fun resolveProvisioningResult(success: Boolean) {
        pendingProvisionResult?.success(success)
        pendingProvisionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startBlocking" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                if (!isAccessibilityEnabled()) {
                    result.error("PERMISSION_DENIED", "Accessibility Service not enabled", null)
                    return
                }
                persistBlockedPackages(packages)
                BlockingService.startBlocking(packages)
                result.success(true)
            }
            "stopBlocking" -> {
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

            else -> result.notImplemented()
        }
    }

    // Persists the blocked package list so BlockingService can restore it
    // after being restarted by the system (e.g. after OEM battery-saver kill).
    fun persistBlockedPackages(packages: List<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(PREFS_KEY_PACKAGES, packages.toSet())
            .apply()
    }

    fun loadPersistedPackages(): Set<String> {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(PREFS_KEY_PACKAGES, emptySet()) ?: emptySet()
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
