package com.lockout.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

// Centralises read/write of Lockout's own native SharedPreferences.
// Methods take an explicit Context so callers (including BroadcastReceivers
// that run before the Flutter engine starts) never touch BlockingChannel.context.
object NativePrefs {
    private const val PREFS_NAME = "lockout"
    private const val KEY_PACKAGES = "blocked_packages"
    private const val KEY_MISSED_NOTIFS = "missed_notifs"
    private const val MISSED_NOTIFS_CAP = 200
    private const val KEY_TEMP_UNBLOCK_PROFILE = "temp_unblock_profile_id"
    private const val KEY_TEMP_UNBLOCK_EXPIRY = "temp_unblock_expiry_ms"
    private const val KEY_NAG_PROFILE = "nag_profile_id"

    fun saveTempUnblock(ctx: Context, profileId: String, expiryMs: Long) {
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TEMP_UNBLOCK_PROFILE, profileId)
            .putLong(KEY_TEMP_UNBLOCK_EXPIRY, expiryMs)
            .apply()
    }

    fun clearTempUnblock(ctx: Context) {
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_TEMP_UNBLOCK_PROFILE)
            .remove(KEY_TEMP_UNBLOCK_EXPIRY)
            .apply()
    }

    fun getTempUnblockProfileId(ctx: Context): String? =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_TEMP_UNBLOCK_PROFILE, null)

    fun getTempUnblockExpiryMs(ctx: Context): Long =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getLong(KEY_TEMP_UNBLOCK_EXPIRY, 0L)

    fun saveNagProfile(ctx: Context, profileId: String) {
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_NAG_PROFILE, profileId).apply()
    }

    fun clearNagProfile(ctx: Context) {
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().remove(KEY_NAG_PROFILE).apply()
    }

    fun getNagProfileId(ctx: Context): String? =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_NAG_PROFILE, null)

    fun savePackages(ctx: Context, packages: Collection<String>) {
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_PACKAGES, packages.toSet())
            .apply()
    }

    fun loadPackages(ctx: Context): Set<String> =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()

    fun appendMissedNotif(ctx: Context, pkg: String, app: String, title: String, text: String, time: Long) {
        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val arr = try { JSONArray(prefs.getString(KEY_MISSED_NOTIFS, "[]") ?: "[]") } catch (_: Exception) { JSONArray() }
        if (arr.length() >= MISSED_NOTIFS_CAP) return
        arr.put(JSONObject().apply {
            put("pkg", pkg); put("app", app)
            put("title", title); put("text", text); put("time", time)
        })
        prefs.edit().putString(KEY_MISSED_NOTIFS, arr.toString()).apply()
    }

    fun loadMissedNotifs(ctx: Context): JSONArray {
        val raw = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_MISSED_NOTIFS, "[]") ?: "[]"
        return try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
    }

    fun clearMissedNotifs(ctx: Context) {
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().remove(KEY_MISSED_NOTIFS).apply()
    }
}
