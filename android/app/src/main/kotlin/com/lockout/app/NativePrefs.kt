package com.lockout.app

import android.content.Context

// Centralises read/write of Lockout's own native SharedPreferences.
// Methods take an explicit Context so callers (including BroadcastReceivers
// that run before the Flutter engine starts) never touch BlockingChannel.context.
object NativePrefs {
    private const val PREFS_NAME = "lockout"
    private const val KEY_PACKAGES = "blocked_packages"

    fun savePackages(ctx: Context, packages: Collection<String>) {
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_PACKAGES, packages.toSet())
            .apply()
    }

    fun loadPackages(ctx: Context): Set<String> =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()
}
