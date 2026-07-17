package dev.embedded_devtools

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service that keeps the app process out of the cached-app freezer
 * while the embedded DevTools server must stay reachable — e.g. the tester
 * opens the phone's own browser, backgrounding the app.
 */
class KeepAliveService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val port = intent?.getIntExtra("port", 0) ?: 0
        val channelId = "embedded_devtools"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Embedded DevTools",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val notification: Notification =
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            })
                .setContentTitle("DevTools server running")
                .setContentText(
                    if (port > 0) "Serving Flutter DevTools on port $port" else "Serving Flutter DevTools",
                )
                .setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setOngoing(true)
                .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    companion object {
        private const val NOTIFICATION_ID = 0x51A0
    }
}
