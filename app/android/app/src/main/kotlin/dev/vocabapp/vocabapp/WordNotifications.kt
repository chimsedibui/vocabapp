package dev.vocabapp.vocabapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.graphics.Typeface
import android.os.Build
import android.os.IBinder
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import java.io.File

/**
 * Pinned word on the lock screen: [WordService] keeps one ongoing notification
 * showing a word the learner last rated Quên/Khó/Tạm (ratings 1–3), with IPA,
 * part of speech, meaning and example.
 *
 * The word changes when the screen turns on and at least [interval] minutes
 * have passed since the last change, or on "Từ khác". There are no alarms, so
 * the phone is never woken for this, and OEM alarm deferral (ColorOS pushes
 * background alarms days out) does not apply. Ongoing, because lock screens
 * such as ColorOS hide ordinary notifications seen before locking.
 *
 * Runs without the Flutter engine and reads `vocabulary.db` directly; settings
 * live in SharedPreferences so boot and app updates can restart the service.
 */
object WordNotifications {
    const val ACTION_NEXT = "dev.vocabapp.vocabapp.WORD_NEXT"
    const val ACTION_STOP = "dev.vocabapp.vocabapp.WORD_STOP"
    const val NOTIFICATION_ID = 4101
    val intervals = listOf(10, 15, 20)

    // v2: DEFAULT importance; LOW ("silent") is hidden on most lock screens.
    private const val CHANNEL = "word_rotation_v2"
    private const val OLD_CHANNEL = "word_rotation"
    private const val PREFS = "word_notifications"
    private const val RECENT = 5

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun enabled(context: Context) = prefs(context).getBoolean("enabled", false)

    fun interval(context: Context) = prefs(context).getInt("interval", 15)

    fun enable(context: Context, minutes: Int) {
        prefs(context).edit()
            .putBoolean("enabled", true)
            .putInt("interval", minutes.coerceIn(intervals.first(), intervals.last()))
            .putLong("changed_at", 0)
            .apply()
        start(context)
    }

    fun disable(context: Context) {
        prefs(context).edit().putBoolean("enabled", false).apply()
        context.stopService(Intent(context, WordService::class.java))
        manager(context).cancel(NOTIFICATION_ID)
    }

    /** Restarts the service after boot, an app update or a force stop. */
    fun restore(context: Context) {
        if (enabled(context)) runCatching { start(context) }
    }

    private fun start(context: Context) {
        val intent = Intent(context, WordService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    /** True when the word is due to change: [interval] minutes since the last one. */
    fun due(context: Context) =
        System.currentTimeMillis() - prefs(context).getLong("changed_at", 0) >=
            interval(context) * 60_000L

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun broadcast(context: Context, action: String, code: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            code,
            Intent(context, WordNotificationReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private class Word(
        val cardId: String,
        val term: String,
        val meaning: String,
        val pos: String?,
        val ipa: String?,
        val example: String?,
    )

    /** Cards whose latest review was again/hard/okay, not suspended. */
    private const val QUERY = """
        SELECT c.id, e.term, s.meaning, s.part_of_speech, s.pronunciation, s.note
        FROM cards c JOIN senses s ON s.id=c.sense_id JOIN entries e ON e.id=s.entry_id
        WHERE c.suspended=0 AND s.status='approved'
        AND (SELECT r.rating FROM review_events r WHERE r.card_id=c.id
             ORDER BY r.reviewed_at DESC LIMIT 1) IN ('again','hard','okay')"""

    private fun pick(context: Context): Word? {
        // Same file as getApplicationSupportDirectory() in lib/data/database.dart.
        val file = File(context.filesDir, "vocabulary.db")
        if (!file.exists()) return null
        val words = SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE)
            .use { db ->
                db.rawQuery(QUERY, null).use { c ->
                    buildList {
                        while (c.moveToNext()) {
                            add(Word(
                                c.getString(0), c.getString(1), c.getString(2),
                                c.getString(3), c.getString(4), c.getString(5),
                            ))
                        }
                    }
                }
            }
        if (words.isEmpty()) return null
        val recent = prefs(context).getString("recent", "")!!.split('\n').filter { it.isNotEmpty() }
        val fresh = words.filter { it.cardId !in recent }
        val word = (fresh.ifEmpty { words }).random()
        val keep = (listOf(word.cardId) + recent).take(minOf(RECENT, words.size - 1).coerceAtLeast(0))
        prefs(context).edit().putString("recent", keep.joinToString("\n")).apply()
        return word
    }

    /** Picks a new word and builds its notification; records the change time. */
    fun next(context: Context): Notification {
        val word = runCatching { pick(context) }.getOrNull()
        prefs(context).edit().putLong("changed_at", System.currentTimeMillis()).apply()
        return build(context, word)
    }

    /** Shows the next word in the pinned notification. */
    fun rotate(context: Context) {
        if (!manager(context).areNotificationsEnabled()) return
        manager(context).notify(NOTIFICATION_ID, next(context))
    }

    private fun build(context: Context, word: Word?): Notification {
        val manager = manager(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.deleteNotificationChannel(OLD_CHANNEL)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Từ vựng xoay vòng", NotificationManager.IMPORTANCE_DEFAULT)
                    .apply {
                        description = "Hiện lần lượt các từ bạn đánh giá Quên/Khó/Tạm."
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                        setSound(null, null)
                        enableVibration(false)
                        setShowBadge(false)
                    },
            )
        }
        val title: String
        val summary: String
        val body = SpannableStringBuilder()
        if (word == null) {
            title = "Chưa có từ khó"
            summary = "Đánh giá Quên/Khó/Tạm khi ôn để từ hiện ở đây."
            body.append(summary)
        } else {
            title = buildString {
                append(word.term)
                word.ipa?.takeIf { it.isNotBlank() }?.let { append("  /$it/") }
            }
            val pos = partsOfSpeech[word.pos]
            summary = if (pos == null) word.meaning else "($pos) ${word.meaning}"
            body.append(summary)
            word.example?.takeIf { it.isNotBlank() }?.let {
                body.append("\n\n")
                val start = body.length
                body.append(it)
                body.setSpan(StyleSpan(Typeface.ITALIC), start, body.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_word)
            .setContentTitle(title)
            .setContentText(summary)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(open)
            // Swiping it away (possible for foreground-service notifications on
            // Android 14+) shows the next word: without a visible notification
            // ColorOS freezes the process, so it could never come back by itself.
            .setDeleteIntent(broadcast(context, ACTION_NEXT, 3))
        if (word != null) {
            builder.addAction(Notification.Action.Builder(null, "Từ khác", broadcast(context, ACTION_NEXT, 1)).build())
        }
        builder.addAction(Notification.Action.Builder(null, "Tắt", broadcast(context, ACTION_STOP, 2)).build())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    /** Same Vietnamese labels as `partsOfSpeech` in lib/domain/models.dart. */
    private val partsOfSpeech = mapOf(
        "noun" to "danh từ",
        "verb" to "động từ",
        "adjective" to "tính từ",
        "adverb" to "trạng từ",
        "pronoun" to "đại từ",
        "preposition" to "giới từ",
        "conjunction" to "liên từ",
        "interjection" to "thán từ",
        "determiner" to "hạn định từ",
        "phrase" to "cụm từ",
        "other" to "khác",
    )
}

/**
 * Foreground service that owns the pinned notification and listens for the
 * screen turning on (only possible with a registered, not manifest, receiver).
 */
class WordService : Service() {
    private var started = false
    private val screenOn = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (!WordNotifications.due(context)) return
            val pending = goAsync()
            Thread {
                try {
                    WordNotifications.rotate(context.applicationContext)
                } finally {
                    pending.finish()
                }
            }.start()
        }
    }

    override fun onCreate() {
        super.onCreate()
        registerReceiver(screenOn, IntentFilter(Intent.ACTION_SCREEN_ON))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!WordNotifications.enabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Opening the app restarts the service; keep the word unless it is due.
        if (started && !WordNotifications.due(this)) return START_STICKY
        started = true
        // Must be foreground within seconds of startForegroundService; the
        // query is a single small SELECT.
        val notification = WordNotifications.next(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                WordNotifications.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(WordNotifications.NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterReceiver(screenOn)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

class WordNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val pending = goAsync()
        Thread {
            try {
                when (intent.action) {
                    Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                        WordNotifications.restore(app)
                    WordNotifications.ACTION_STOP -> WordNotifications.disable(app)
                    WordNotifications.ACTION_NEXT ->
                        if (WordNotifications.enabled(app)) WordNotifications.rotate(app)
                }
            } finally {
                pending.finish()
            }
        }.start()
    }
}
