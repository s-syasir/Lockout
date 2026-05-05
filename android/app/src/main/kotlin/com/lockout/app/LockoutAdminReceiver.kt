package com.lockout.app

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent

// Receives lifecycle callbacks for Lockout's managed profile.
// The only thing we do here is enable the profile after provisioning completes —
// the system creates it in a disabled state and expects the admin to flip it on.
class LockoutAdminReceiver : DeviceAdminReceiver() {
    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        dpm.setProfileEnabled(getWho(context))
    }
}
