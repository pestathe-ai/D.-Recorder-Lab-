package dev.drecorderlab.d_recorder_lab

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Registra dal microfono in un servizio in primo piano, indipendente
 * dall'interfaccia. Il file WAV viene chiuso correttamente a ogni controllo
 * periodico: se il telefono si spegne si perdono al massimo pochi secondi.
 */
class RecorderService : Service() {
    companion object {
        const val ACTION_START = "start"
        const val ACTION_PAUSE = "pause"
        const val ACTION_RESUME = "resume"
        const val ACTION_STOP = "stop"
        private const val EXTRA_PATH = "path"
        private const val CHANNEL = "recording"
        private const val NOTIFICATION_ID = 7101
        private const val SAMPLE_RATE = 16000
        private const val BYTES_PER_SECOND = SAMPLE_RATE * 2
        private const val MIN_FREE_BYTES = 80L * 1024 * 1024

        @Volatile var state = "idle"
        @Volatile var path: String? = null
        @Volatile var dataBytes = 0L
        @Volatile var level = 0.0
        @Volatile var silenced = false
        @Volatile var lastError: String? = null

        fun statusMap(): Map<String, Any?> = mapOf(
            "state" to state,
            "path" to path,
            "elapsedMs" to dataBytes * 1000 / BYTES_PER_SECOND,
            "level" to level,
            "silenced" to silenced,
            "error" to lastError,
        )

        fun control(context: Context, action: String, filePath: String? = null) {
            if (action == ACTION_START) {
                if (state != "idle") return
                state = "recording"
                path = filePath
                dataBytes = 0
                level = 0.0
                silenced = false
                lastError = null
            } else if (state == "idle") {
                return
            }
            val intent = Intent(context, RecorderService::class.java).setAction(action)
            if (filePath != null) intent.putExtra(EXTRA_PATH, filePath)
            try {
                if (action == ACTION_START && Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                if (action == ACTION_START) {
                    state = "idle"
                    lastError = "Non riesco ad avviare la registrazione."
                }
            }
        }
    }

    @Volatile private var running = false
    private var worker: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var recordingCallback: AudioManager.AudioRecordingCallback? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> begin(intent.getStringExtra(EXTRA_PATH))
            ACTION_PAUSE -> if (state == "recording") { state = "paused"; level = 0.0; refresh() }
            ACTION_RESUME -> if (state == "paused") { state = "recording"; refresh() }
            ACTION_STOP -> running = false
            else -> if (!running) stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun begin(filePath: String?) {
        if (filePath == null || running) return
        createChannel()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIFICATION_ID, build())
            }
        } catch (e: Exception) {
            state = "idle"
            lastError = "Android non ha permesso di usare il microfono in questo momento."
            stopSelf()
            return
        }
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "drecorder:rec").apply {
            setReferenceCounted(false)
            acquire(24L * 60 * 60 * 1000)
        }
        running = true
        worker = Thread({ loop(filePath) }, "recorder").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    private fun loop(filePath: String) {
        var recorder: AudioRecord? = null
        var file: RandomAccessFile? = null
        try {
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            )
            recorder = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minBuffer * 4, BYTES_PER_SECOND * 2),
            )
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                throw IllegalStateException("Il microfono non è disponibile.")
            }
            File(filePath).parentFile?.mkdirs()
            file = RandomAccessFile(filePath, "rw")
            file.setLength(0)
            file.write(header(0))
            watchSilencing(recorder)
            recorder.startRecording()

            val buffer = ByteArray(3200)
            var sinceSync = 0L
            var sinceSpaceCheck = 0L
            val folder = File(filePath).parentFile ?: filesDir
            while (running) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read < 0) throw IllegalStateException("Il microfono ha smesso di rispondere.")
                val count = read and 1.inv()
                if (count == 0 || state == "paused") continue
                file.write(buffer, 0, count)
                dataBytes += count
                level = rms(buffer, count)
                sinceSync += count
                sinceSpaceCheck += count
                if (sinceSync >= BYTES_PER_SECOND * 5) {
                    sinceSync = 0
                    patchHeader(file)
                }
                if (sinceSpaceCheck >= BYTES_PER_SECOND * 30) {
                    sinceSpaceCheck = 0
                    if (folder.usableSpace < MIN_FREE_BYTES) {
                        lastError = "Spazio quasi esaurito: registrazione fermata e salvata."
                        break
                    }
                }
            }
        } catch (e: Exception) {
            lastError = e.message ?: "Errore durante la registrazione."
        } finally {
            try { file?.let { patchHeader(it); it.close() } } catch (_: Exception) {}
            unwatchSilencing()
            try { recorder?.stop() } catch (_: Exception) {}
            try { recorder?.release() } catch (_: Exception) {}
            running = false
            state = "idle"
            path = null
            level = 0.0
            Handler(Looper.getMainLooper()).post {
                wakeLock?.let { if (it.isHeld) it.release() }
                stopForeground(true)
                stopSelf()
            }
        }
    }

    private fun rms(buffer: ByteArray, count: Int): Double {
        val shorts = ByteBuffer.wrap(buffer, 0, count).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        if (shorts.remaining() == 0) return 0.0
        var sum = 0.0
        val n = shorts.remaining()
        for (i in 0 until n) {
            val v = shorts.get(i) / 32768.0
            sum += v * v
        }
        return min(1.0, sqrt(sum / n) * 4)
    }

    private fun patchHeader(file: RandomAccessFile) {
        val end = file.filePointer
        file.seek(0)
        file.write(header(end - 44))
        file.seek(end)
        file.fd.sync()
    }

    private fun header(dataLength: Long): ByteArray {
        val capped = min(dataLength, 0xFFFFFFFFL - 36).toInt()
        val b = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + capped).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
        b.putInt(SAMPLE_RATE).putInt(BYTES_PER_SECOND).putShort(2).putShort(16)
        b.put("data".toByteArray()).putInt(capped)
        return b.array()
    }

    private fun watchSilencing(recorder: AudioRecord) {
        if (Build.VERSION.SDK_INT < 29) return
        val session = recorder.audioSessionId
        val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val callback = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
                val mine = configs.firstOrNull { it.clientAudioSessionId == session } ?: return
                if (mine.isClientSilenced != silenced) {
                    silenced = mine.isClientSilenced
                    refresh()
                }
            }
        }
        manager.registerAudioRecordingCallback(callback, Handler(Looper.getMainLooper()))
        recordingCallback = callback
    }

    private fun unwatchSilencing() {
        if (Build.VERSION.SDK_INT < 29) return
        val callback = recordingCallback ?: return
        (getSystemService(Context.AUDIO_SERVICE) as AudioManager).unregisterAudioRecordingCallback(callback)
        recordingCallback = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL, "Registrazione", NotificationManager.IMPORTANCE_LOW)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }

    private fun action(name: String, code: Int): PendingIntent = PendingIntent.getService(
        this, code, Intent(this, RecorderService::class.java).setAction(name),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    @Suppress("DEPRECATION")
    private fun build(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val paused = state == "paused"
        val text = when {
            silenced -> "Microfono occupato da un'altra app: l'audio è muto"
            paused -> "In pausa"
            else -> "Registrazione in corso"
        }
        builder.setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("D. Recorder Lab")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(open)
            .setWhen(System.currentTimeMillis() - dataBytes * 1000 / BYTES_PER_SECOND)
            .setShowWhen(!paused)
            .setUsesChronometer(!paused)
            .addAction(
                Notification.Action.Builder(
                    null,
                    if (paused) "Riprendi" else "Pausa",
                    action(if (paused) ACTION_RESUME else ACTION_PAUSE, 1),
                ).build(),
            )
            .addAction(Notification.Action.Builder(null, "Ferma e salva", action(ACTION_STOP, 2)).build())
        return builder.build()
    }

    private fun refresh() {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, build())
    }

    override fun onDestroy() {
        running = false
        wakeLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }
}
