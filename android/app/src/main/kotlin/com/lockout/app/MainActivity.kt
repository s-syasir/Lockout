package com.lockout.app

import android.Manifest
import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    companion object {
        private const val REQ_PROVISION_MANAGED_PROFILE = 1001
        private const val REQ_POST_NOTIFICATIONS = 1002
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BlockingChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
        BlockingChannel.startProvisioningFn = { startManagedProfileProvisioning() }
        BlockingChannel.requestNotificationPermissionFn = { requestPostNotificationsPermission() }
    }

    // POST_NOTIFICATIONS is a runtime permission on API 33+; below that it's
    // granted automatically at install time.
    private fun requestPostNotificationsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_POST_NOTIFICATIONS
            )
        } else {
            BlockingChannel.resolveNotificationPermissionResult(true)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            BlockingChannel.resolveNotificationPermissionResult(granted)
        }
    }

    @Suppress("DEPRECATION")
    private fun startManagedProfileProvisioning() {
        val intent = Intent(DevicePolicyManager.ACTION_PROVISION_MANAGED_PROFILE).apply {
            putExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME,
                ComponentName(this@MainActivity, LockoutAdminReceiver::class.java)
            )
        }
        if (intent.resolveActivity(packageManager) != null) {
            startActivityForResult(intent, REQ_PROVISION_MANAGED_PROFILE)
        } else {
            BlockingChannel.resolveProvisioningResult(false)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PROVISION_MANAGED_PROFILE) {
            BlockingChannel.resolveProvisioningResult(resultCode == Activity.RESULT_OK)
        }
    }

    override fun onResume() {
        super.onResume()
        handleNfcIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNfcIntent(intent)
    }

    // Parses an NDEF_DISCOVERED intent and stores the profile ID so Flutter
    // can retrieve it via the getPendingNfcTag channel method.
    private fun handleNfcIntent(intent: Intent?) {
        if (intent?.action != NfcAdapter.ACTION_NDEF_DISCOVERED) return
        val rawMessages = intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES) ?: return
        for (raw in rawMessages) {
            val message = raw as NdefMessage
            for (record in message.records) {
                val payload = record.payload
                if (payload.size < 3) continue
                // NDEF Text record layout: byte 0 = status (lang-code length in low 6 bits),
                // next N bytes = BCP 47 language code, remainder = UTF-8 text.
                val langLen = payload[0].toInt() and 0x3F
                if (1 + langLen >= payload.size) continue
                val text = String(payload, 1 + langLen, payload.size - 1 - langLen, Charsets.UTF_8)
                val prefix = "lockout:profile:"
                if (text.startsWith(prefix)) {
                    BlockingChannel.pendingNfcProfileId = text.substring(prefix.length)
                    return
                }
            }
        }
    }
}
