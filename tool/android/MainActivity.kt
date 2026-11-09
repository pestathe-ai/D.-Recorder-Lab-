package dev.drecorderlab.d_recorder_lab

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "d_recorder/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        RecorderService.control(this, RecorderService.ACTION_START, call.argument<String>("path"))
                        result.success(null)
                    }
                    "pause" -> { RecorderService.control(this, RecorderService.ACTION_PAUSE); result.success(null) }
                    "resume" -> { RecorderService.control(this, RecorderService.ACTION_RESUME); result.success(null) }
                    "stop" -> { RecorderService.control(this, RecorderService.ACTION_STOP); result.success(null) }
                    "status" -> result.success(RecorderService.statusMap())
                    "clearNotice" -> { RecorderService.lastError = null; result.success(null) }
                    "requestMic" -> requestMic(result)
                    "openSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        )
                        result.success(null)
                    }
                    "pickAudio" -> pickAudio(result)
                    "importStart" -> {
                        AudioImporter.start(this, Uri.parse(call.argument<String>("uri")!!), call.argument<String>("path")!!)
                        result.success(null)
                    }
                    "importStatus" -> result.success(AudioImporter.statusMap())
                    "importCancel" -> { AudioImporter.cancel(); result.success(null) }
                    "processingUpdate" -> {
                        ProcessingService.update(
                            this,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: "",
                            call.argument<Int>("percent") ?: -1,
                        )
                        result.success(null)
                    }
                    "processingStop" -> { ProcessingService.stop(this); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickAudio(result: MethodChannel.Result) {
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "video/*"))
        startActivityForResult(intent, 4712)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4712) return
        val uri = if (resultCode == RESULT_OK) data?.data else null
        var name = "Audio importato"
        if (uri != null) {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst() && !it.isNull(0)) name = it.getString(0)
                }
            } catch (_: Exception) {}
        }
        pendingPick?.success(uri?.let { mapOf("uri" to it.toString(), "name" to name) })
        pendingPick = null
    }

    private fun requestMic(result: MethodChannel.Result) {
        val needed = mutableListOf<String>()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.RECORD_AUDIO)
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            needed.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (needed.isEmpty()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < 23) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(needed.toTypedArray(), 4711)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4711) return
        val granted = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    override fun onDestroy() {
        // La trascrizione vive nell'interfaccia: se questa si chiude, il
        // servizio non ha più motivo di restare attivo. La registrazione invece continua.
        if (isFinishing) ProcessingService.stop(this)
        super.onDestroy()
    }
}
