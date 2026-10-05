package pl.gpsrtk.gps_rtk_app

import android.media.AudioManager
import android.media.ToneGenerator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Sygnały tyczenia (lib/services/beeper.dart). SystemSound z Fluttera jest
    // na Androidzie ignorowany, więc gramy systemowe tony. Strumień
    // powiadomień — słychać w terenie, a tryb cichy telefonu go wycisza.
    private var tone: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gps_rtk/beep")
            .setMethodCallHandler { call, result ->
                if (call.method == "beep") {
                    try {
                        val t = tone ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
                            .also { tone = it }
                        when (call.argument<String>("kind")) {
                            "arrived" -> t.startTone(ToneGenerator.TONE_PROP_ACK, 600)
                            else -> t.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
                        }
                    } catch (e: RuntimeException) {
                        // ToneGenerator bywa niedostępny (zajęty audio) — bez dźwięku.
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        tone?.release()
        tone = null
        super.onDestroy()
    }
}
