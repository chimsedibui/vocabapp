package dev.vocabapp.vocabapp

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
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

    override fun onDestroy() {
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
