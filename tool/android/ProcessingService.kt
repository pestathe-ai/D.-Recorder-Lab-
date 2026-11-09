package dev.drecorderlab.d_recorder_lab

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/** Tiene vivo il processo durante trascrizioni e download lunghi. */
class ProcessingService : Service() {
    companion object {
        private const val CHANNEL = "processing"
        private const val NOTIFICATION_ID = 7102
        private const val ACTION_UPDATE = "update"
        private const val ACTION_STOP = "stop"
        private const val WATCHDOG_MS = 5L * 60 * 1000
        @Volatile private var active = false

        fun update(context: Context, title: String, text: String, percent: Int) {
            val intent = Intent(context, ProcessingService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra("title", title)
                .putExtra("text", text)
                .putExtra("percent", percent)
            try {
                if (!active && Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                active = true
            } catch (_: Exception) {
                // Senza servizio il lavoro continua, ma Android potrebbe sospenderlo.
            }
        }

        fun stop(context: Context) {
            if (!active) return
            try {
                context.startService(Intent(context, ProcessingService::class.java).setAction(ACTION_STOP))
            } catch (_: Exception) {}
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val watchdog = Runnable { finish() }
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_UPDATE) {
            if (intent?.action != ACTION_STOP) stopSelf()
            finish()
            return START_NOT_STICKY
        }
        val notification = build(
            intent.getStringExtra("title") ?: "",
            intent.getStringExtra("text") ?: "",
            intent.getIntExtra("percent", -1),
        )
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            finish()
            return START_NOT_STICKY
        }
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "drecorder:work").apply {
                setReferenceCounted(false)
                acquire(8L * 60 * 60 * 1000)
            }
        }
        handler.removeCallbacks(watchdog)
        handler.postDelayed(watchdog, WATCHDOG_MS)
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun build(title: String, text: String, percent: Int): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "Elaborazione", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .setProgress(100, percent.coerceIn(0, 100), percent < 0)
        return builder.build()
    }

    private fun finish() {
        active = false
        handler.removeCallbacks(watchdog)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(true)
        stopSelf()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        finish()
    }

    override fun onDestroy() {
        active = false
        handler.removeCallbacks(watchdog)
        wakeLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }
}
