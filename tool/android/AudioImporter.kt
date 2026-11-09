package dev.drecorderlab.d_recorder_lab

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.min

/** Converte qualunque audio leggibile da Android in WAV mono a 16 kHz. */
object AudioImporter {
    private const val OUT_RATE = 16000
    private const val MIN_FREE_BYTES = 80L * 1024 * 1024

    @Volatile var state = "idle"
    @Volatile var progress = 0.0
    @Volatile var error: String? = null
    @Volatile private var cancelled = false

    fun statusMap(): Map<String, Any?> = mapOf("state" to state, "progress" to progress, "error" to error)

    fun cancel() { cancelled = true }

    fun start(context: Context, uri: Uri, outPath: String) {
        if (state == "running") return
        state = "running"
        progress = 0.0
        error = null
        cancelled = false
        val appContext = context.applicationContext
        Thread({
            try {
                convert(appContext, uri, outPath)
                state = if (cancelled) "idle" else "done"
            } catch (e: UserMessage) {
                error = e.message
                state = "error"
            } catch (e: Exception) {
                error = "Non riesco a leggere questo file audio."
                state = "error"
            }
            if (state != "done") File(outPath).delete()
        }, "import-audio").start()
    }

    private class UserMessage(message: String) : Exception(message)

    private class Resampler(inRate: Int, private val emit: (Double) -> Unit) {
        private val step = inRate.toDouble() / OUT_RATE
        private val down = step >= 1.0
        private var sum = 0.0
        private var count = 0
        private var position = 0.0
        private var next = step
        private var previous = 0.0
        private var first = true
        private var fraction = 0.0

        fun push(sample: Double) {
            if (down) {
                sum += sample
                count++
                position += 1.0
                if (position >= next) {
                    emit(sum / count)
                    sum = 0.0
                    count = 0
                    next += step
                }
            } else {
                if (first) {
                    previous = sample
                    first = false
                    return
                }
                while (fraction < 1.0) {
                    emit(previous + (sample - previous) * fraction)
                    fraction += step
                }
                fraction -= 1.0
                previous = sample
            }
        }
    }

    private fun convert(context: Context, uri: Uri, outPath: String) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        val outFile = File(outPath)
        outFile.parentFile?.mkdirs()
        var outBytes = 0L
        try {
            try {
                extractor.setDataSource(context, uri, null)
            } catch (e: Exception) {
                throw UserMessage("Questo formato non è supportato dal telefono.")
            }
            var track = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    track = i
                    format = f
                    break
                }
            }
            val input = format ?: throw UserMessage("Questo file non contiene audio.")
            extractor.selectTrack(track)
            val durationUs = if (input.containsKey(MediaFormat.KEY_DURATION)) input.getLong(MediaFormat.KEY_DURATION) else 0L
            val decoder = try {
                MediaCodec.createDecoderByType(input.getString(MediaFormat.KEY_MIME)!!).apply {
                    configure(input, null, null, 0)
                    start()
                }
            } catch (e: Exception) {
                throw UserMessage("Il telefono non sa leggere questo tipo di audio.")
            }
            codec = decoder

            BufferedOutputStream(FileOutputStream(outFile), 1 shl 18).use { out ->
                out.write(header(0))
                var channels = max(1, input.getInteger(MediaFormat.KEY_CHANNEL_COUNT))
                var isFloat = false
                val two = ByteArray(2)
                val emit: (Double) -> Unit = { value ->
                    val s = (value.coerceIn(-1.0, 1.0) * 32767).toInt()
                    two[0] = s.toByte()
                    two[1] = (s shr 8).toByte()
                    out.write(two)
                    outBytes += 2
                }
                var resampler = Resampler(input.getInteger(MediaFormat.KEY_SAMPLE_RATE), emit)
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                var sinceCheck = 0L
                while (!outputDone) {
                    if (cancelled) return
                    if (!inputDone) {
                        val index = decoder.dequeueInputBuffer(10000)
                        if (index >= 0) {
                            val buffer = decoder.getInputBuffer(index)!!
                            val size = extractor.readSampleData(buffer, 0)
                            if (size < 0) {
                                decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                    val index = decoder.dequeueOutputBuffer(info, 10000)
                    if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val f = decoder.outputFormat
                        channels = max(1, f.getInteger(MediaFormat.KEY_CHANNEL_COUNT))
                        isFloat = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                        resampler = Resampler(f.getInteger(MediaFormat.KEY_SAMPLE_RATE), emit)
                    } else if (index >= 0) {
                        if (info.size > 0) {
                            val buffer = decoder.getOutputBuffer(index)!!
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            pushFrames(buffer.slice().order(ByteOrder.nativeOrder()), channels, isFloat, resampler)
                            if (durationUs > 0) progress = min(1.0, info.presentationTimeUs.toDouble() / durationUs)
                            sinceCheck += info.size
                            if (sinceCheck > 8_000_000L) {
                                sinceCheck = 0
                                if ((outFile.parentFile ?: outFile).usableSpace < MIN_FREE_BYTES) {
                                    throw UserMessage("Spazio insufficiente sul telefono.")
                                }
                            }
                        }
                        decoder.releaseOutputBuffer(index, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }
            if (outBytes < OUT_RATE) throw UserMessage("Il file audio è vuoto o troppo corto.")
            RandomAccessFile(outFile, "rw").use { raf ->
                raf.seek(0)
                raf.write(header(outBytes))
                raf.fd.sync()
            }
            progress = 1.0
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            extractor.release()
        }
    }

    private fun pushFrames(data: ByteBuffer, channels: Int, isFloat: Boolean, resampler: Resampler) {
        if (isFloat) {
            val floats = data.asFloatBuffer()
            val frames = floats.remaining() / channels
            for (frame in 0 until frames) {
                var sum = 0.0
                for (c in 0 until channels) sum += floats.get(frame * channels + c)
                resampler.push(sum / channels)
            }
        } else {
            val shorts = data.asShortBuffer()
            val frames = shorts.remaining() / channels
            for (frame in 0 until frames) {
                var sum = 0.0
                for (c in 0 until channels) sum += shorts.get(frame * channels + c) / 32768.0
                resampler.push(sum / channels)
            }
        }
    }

    private fun header(dataLength: Long): ByteArray {
        val capped = min(dataLength, 0xFFFFFFFFL - 36).toInt()
        val b = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + capped).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
        b.putInt(OUT_RATE).putInt(OUT_RATE * 2).putShort(2).putShort(16)
        b.put("data".toByteArray()).putInt(capped)
        return b.array()
    }
}
