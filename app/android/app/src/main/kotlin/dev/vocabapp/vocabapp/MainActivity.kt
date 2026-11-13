package dev.vocabapp.vocabapp

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
    private var permissionDone: ((Boolean) -> Unit)? = null
    private var externalActivityOpen = false
    private val closeHandler = Handler(Looper.getMainLooper())
    private val closeUi = Runnable {
        if (!isDestroyed && !isFinishing && WordNotifications.enabled(this)) {
            finishAndRemoveTask()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A force stop (e.g. swiping the app away on ColorOS) drops the service.
        WordNotifications.restore(this)
        syncRecentsTask()
    }

    override fun onStart() {
        super.onStart()
        closeHandler.removeCallbacks(closeUi)
    }

    override fun onResume() {
        super.onResume()
        externalActivityOpen = false
        closeHandler.removeCallbacks(closeUi)
        syncRecentsTask()
    }

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations && !externalActivityOpen && WordNotifications.enabled(this)) {
            // Give on-pause sync a few seconds to complete, then release the
            // Flutter UI so only the small WordService anchor stays in RAM.
            closeHandler.removeCallbacks(closeUi)
            closeHandler.postDelayed(closeUi, 3_000L)
        }
    }

    override fun startActivityForResult(intent: Intent, requestCode: Int, options: Bundle?) {
        externalActivityOpen = true
        closeHandler.removeCallbacks(closeUi)
        super.startActivityForResult(intent, requestCode, options)
    }

    override fun finish() {
        if (WordNotifications.enabled(this)) {
            finishAndRemoveTask()
        } else {
            super.finish()
        }
    }

    private fun syncRecentsTask() {
        val hideFromRecents = WordNotifications.enabled(this)
        val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        manager.appTasks.forEach { task ->
            runCatching { task.setExcludeFromRecents(hideFromRecents) }
        }
    }

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
        // "vocabapp/notify": rotating word notification, see WordNotifications.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vocabapp/notify")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(mapOf(
                        "enabled" to WordNotifications.enabled(this),
                        "interval" to WordNotifications.interval(this),
                        "allowed" to notificationsAllowed(),
                    ))
                    "enable" -> {
                        val minutes = call.argument<Int>("interval") ?: 15
                        requestNotifications { allowed ->
                            if (allowed) {
                                WordNotifications.enable(this, minutes)
                                syncRecentsTask()
                            }
                            result.success(allowed)
                        }
                    }
                    "disable" -> {
                        WordNotifications.disable(this)
                        syncRecentsTask()
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        startActivity(appDetailsIntent())
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
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
        // One update at a time: a second tap would otherwise leave an older
        // session that Android later reports as aborted.
        installer.mySessions.forEach { runCatching { installer.abandonSession(it.sessionId) } }
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        // Android 12+ lets an app update itself without the confirm dialog;
        // the system still asks when it cannot honour this (e.g. first grant).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
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

    private fun appDetailsIntent() =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", packageName, null))

    /**
     * Opens this app's notification settings, where the learner can allow the
     * pinned word on the lock screen. Some lock screens (e.g. ColorOS 16) hide
     * it unless allowed here; the app cannot change that itself.
     */
    private fun openNotificationSettings() {
        // The channel must exist for its settings to be listed.
        WordNotifications.ensureChannel(this)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            appDetailsIntent()
        }
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            startActivity(appDetailsIntent())
        }
    }

    private fun notificationsAllowed() =
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()

    private fun requestNotifications(done: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            done(notificationsAllowed())
            return
        }
        permissionDone?.invoke(false)
        permissionDone = done
        externalActivityOpen = true
        closeHandler.removeCallbacks(closeUi)
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_PERMISSION)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFY_PERMISSION) return
        externalActivityOpen = false
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        permissionDone?.invoke(granted)
        permissionDone = null
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
            // Aborted: the user cancelled, or an abandoned/superseded session;
            // the install itself may still succeed, so this is not an error.
            PackageInstaller.STATUS_SUCCESS, PackageInstaller.STATUS_FAILURE_ABORTED -> Unit
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
        private const val NOTIFY_PERMISSION = 4102
    }

    override fun onDestroy() {
        closeHandler.removeCallbacks(closeUi)
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
