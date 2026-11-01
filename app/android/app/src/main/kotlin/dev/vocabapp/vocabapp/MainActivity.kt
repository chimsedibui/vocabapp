package dev.vocabapp.vocabapp

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.speech.tts.TextToSpeech
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: String? = null

    // "vocabapp/speech": reads English with the device's TextToSpeech engine.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vocabapp/speech")
            .setMethodCallHandler { call, result ->
                if (call.method != "speak") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text").orEmpty()
                val engine = tts
                when {
                    text.isEmpty() -> result.success(false)
                    engine != null && ready -> result.success(say(engine, text))
                    else -> {
                        // The engine binds asynchronously; speak once it is up.
                        pending = text
                        if (engine == null) {
                            tts = TextToSpeech(this) { status ->
                                ready = status == TextToSpeech.SUCCESS
                                val queued = pending
                                pending = null
                                if (ready && queued != null) say(tts!!, queued)
                            }
                        }
                        result.success(true)
                    }
                }
            }
        // "vocabapp/update": installs a downloaded, checksum-verified APK.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vocabapp/update")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    installApk(File(call.argument<String>("path")!!))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("install", e.message, null)
                }
            }
    }

    private fun installApk(apk: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("base.apk", 0, apk.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val intent = Intent(this, MainActivity::class.java).setAction(INSTALL_STATUS)
            // The installer fills in the status extras, so the intent must be mutable.
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            session.commit(PendingIntent.getActivity(this, 0, intent, flags).intentSender)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action != INSTALL_STATUS) return
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirm != null) startActivity(confirm)
            }
            PackageInstaller.STATUS_SUCCESS -> Unit
            else -> Toast.makeText(
                this,
                "Không cài được bản cập nhật: " +
                    (intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "đã huỷ"),
                Toast.LENGTH_LONG,
            ).show()
        }
    }

    private fun say(engine: TextToSpeech, text: String): Boolean {
        val language = engine.setLanguage(Locale.US)
        if (language == TextToSpeech.LANG_MISSING_DATA ||
            language == TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            return false
        }
        return engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "vocabapp") ==
            TextToSpeech.SUCCESS
    }

    companion object {
        private const val INSTALL_STATUS = "dev.vocabapp.vocabapp.INSTALL_STATUS"
    }

    override fun onDestroy() {
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
