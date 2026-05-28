package com.lockout.app

import android.content.Context
import org.json.JSONArray

// Reads and writes Flutter's SharedPreferences from native code.
// Flutter's shared_preferences plugin stores data in "FlutterSharedPreferences"
// with a "flutter." key prefix. This lets BroadcastReceivers (schedule alarms,
// boot receiver) read profile data and update session state without Flutter running.
object FlutterPrefs {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_PROFILES = "flutter.profiles"
    private const val KEY_ACTIVE_PROFILE_ID = "flutter.active_profile_id"

    fun getActiveProfileId(ctx: Context): String? =
        prefs(ctx).getString(KEY_ACTIVE_PROFILE_ID, null)

    fun setActiveProfileId(ctx: Context, id: String?) {
        val edit = prefs(ctx).edit()
        if (id == null) edit.remove(KEY_ACTIVE_PROFILE_ID) else edit.putString(KEY_ACTIVE_PROFILE_ID, id)
        edit.apply()
    }

    fun getProfileName(ctx: Context, profileId: String): String? {
        val json = prefs(ctx).getString(KEY_PROFILES, null) ?: return null
        return try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                if (obj.getString("id") == profileId) return obj.getString("name")
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    // Returns packages for a specific profile, or null if not found.
    fun getProfilePackages(ctx: Context, profileId: String): List<String>? {
        val json = prefs(ctx).getString(KEY_PROFILES, null) ?: return null
        return try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                if (obj.getString("id") == profileId) {
                    val pkgs = obj.getJSONArray("blockedPackages")
                    return (0 until pkgs.length()).map { pkgs.getString(it) }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    // Returns all profiles that have a schedule enabled.
    fun getAllScheduledProfiles(ctx: Context): List<ScheduledProfile> {
        val json = prefs(ctx).getString(KEY_PROFILES, null) ?: return emptyList()
        return try {
            val arr = JSONArray(json)
            val result = mutableListOf<ScheduledProfile>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                if (!obj.optBoolean("scheduleEnabled", false)) continue
                val startStr = obj.optString("scheduleStart").takeIf { it.isNotEmpty() } ?: continue
                val endStr = obj.optString("scheduleEnd").takeIf { it.isNotEmpty() } ?: continue
                val startParts = startStr.split(":")
                val endParts = endStr.split(":")
                if (startParts.size != 2 || endParts.size != 2) continue
                val pkgs = obj.getJSONArray("blockedPackages")
                result.add(
                    ScheduledProfile(
                        id = obj.getString("id"),
                        packages = (0 until pkgs.length()).map { pkgs.getString(it) },
                        startHH = startParts[0].toInt(),
                        startMM = startParts[1].toInt(),
                        endHH = endParts[0].toInt(),
                        endMM = endParts[1].toInt(),
                    )
                )
            }
            result
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}

data class ScheduledProfile(
    val id: String,
    val packages: List<String>,
    val startHH: Int,
    val startMM: Int,
    val endHH: Int,
    val endMM: Int,
)
