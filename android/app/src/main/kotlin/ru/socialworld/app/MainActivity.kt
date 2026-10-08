package ru.socialworld.app

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.telecom.CallAudioState
import com.hiennv.flutter_callkit_incoming.CallkitConnection
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // «Поделиться» из других приложений (lib/core/share). Присланное лежит в
    // pendingShare, пока Dart его не заберёт: при холодном запуске слушателя
    // на той стороне ещё нет.
    private var shareChannel: MethodChannel? = null
    private var pendingShare: Map<String, Any?>? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureShare(intent)
    }

    private fun captureShare(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val uris = ArrayList<Uri>()
        if (action == Intent.ACTION_SEND) {
            streamExtra(intent)?.let { uris.add(it) }
        } else {
            streamsExtra(intent)?.let { uris.addAll(it) }
        }
        // Намерение обработано: поворот экрана и возврат в приложение его не
        // повторят.
        intent.action = Intent.ACTION_MAIN
        Thread {
            val shared = copySharedFiles(uris)
            val payload = mapOf<String, Any?>(
                "text" to text,
                "files" to shared.first,
                "skipped" to shared.second,
            )
            runOnUiThread {
                pendingShare = payload
                shareChannel?.invokeMethod(
                    "shared",
                    payload,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            if (pendingShare === payload) pendingShare = null
                        }

                        override fun error(code: String, message: String?, details: Any?) {}

                        // Слушателя ещё нет (холодный запуск): Dart заберёт
                        // сам через "initial".
                        override fun notImplemented() {}
                    },
                )
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamsExtra(intent: Intent): List<Uri>? =
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }

    /// Присланные файлы копируются в кэш приложения: чужой content:// после
    /// закрытия того приложения может перестать читаться. Больше 100 МБ не
    /// берём (в чате всё равно потолок 50 МБ); сколько пропущено, передаём.
    private fun copySharedFiles(uris: List<Uri>): Pair<List<Map<String, Any?>>, Int> {
        val dir = java.io.File(cacheDir, "shared").apply { mkdirs() }
        val files = ArrayList<Map<String, Any?>>()
        var skipped = 0
        for ((index, uri) in uris.withIndex()) {
            try {
                var name: String? = null
                var size = -1L
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameAt = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        if (nameAt >= 0) name = cursor.getString(nameAt)
                        val sizeAt = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                        if (sizeAt >= 0 && !cursor.isNull(sizeAt)) size = cursor.getLong(sizeAt)
                    }
                }
                if (size > 100L * 1024 * 1024) {
                    skipped++
                    continue
                }
                val safe = (name ?: "file_$index").replace('/', '_').replace('\\', '_')
                val target = java.io.File(dir, "${System.currentTimeMillis()}_${index}_$safe")
                val input = contentResolver.openInputStream(uri)
                if (input == null) {
                    skipped++
                    continue
                }
                input.use { source -> target.outputStream().use { sink -> source.copyTo(sink) } }
                files.add(
                    mapOf(
                        "path" to target.absolutePath,
                        "name" to safe,
                        "mime" to contentResolver.getType(uri),
                        "size" to target.length(),
                    ),
                )
            } catch (e: Exception) {
                skipped++
            }
        }
        return Pair(files, skipped)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chawo/share").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    val payload = pendingShare
                    pendingShare = null
                    result.success(payload)
                } else {
                    result.notImplemented()
                }
            }
        }
        captureShare(intent)
        // Отпечаток устройства для антифрода приглашений (lib/features/referrals):
        // Android ID переживает переустановку приложения, на сервер уходит
        // только его хеш.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chawo/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidId" -> result.success(
                        android.provider.Settings.Secure.getString(
                            contentResolver,
                            android.provider.Settings.Secure.ANDROID_ID,
                        ),
                    )
                    // Автоскачивание обновлений (lib/core/update): по умолчанию
                    // только по Wi-Fi, мобильный трафик человека не тратим.
                    "onWifi" -> {
                        val manager = getSystemService(ConnectivityManager::class.java)
                        val caps = manager?.getNetworkCapabilities(manager.activeNetwork)
                        result.success(
                            caps != null && (
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                                ),
                        )
                    }
                    // Громкая связь в звонке (lib/features/calls). Звонок живёт в
                    // системном Telecom (self-managed), и маршрут звука держит
                    // он: AudioManager.setSpeakerphoneOn от приложения Telecom
                    // перебивает своим «к уху» (лог 07.10: route EARPIECE весь
                    // разговор). Поэтому маршрут меняем через сам Connection.
                    "callAudioRoute" -> {
                        val callId = call.argument<String>("callId")
                        val speaker = call.argument<Boolean>("speaker") == true
                        val connection = callId?.let { CallkitConnection.find(it) }
                        if (connection == null) {
                            result.success(false)
                        } else {
                            @Suppress("DEPRECATION")
                            connection.setAudioRoute(
                                if (speaker) CallAudioState.ROUTE_SPEAKER else CallAudioState.ROUTE_WIRED_OR_EARPIECE,
                            )
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Ярлык чата на рабочем столе (lib/core/shortcuts/home_shortcut.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chawo/shortcuts")
            .setMethodCallHandler { call, result ->
                if (call.method != "pin") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val manager = getSystemService(ShortcutManager::class.java)
                    if (manager == null || !manager.isRequestPinShortcutSupported) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val id = call.argument<String>("id")!!
                    val label = call.argument<String>("label")!!
                    val uri = call.argument<String>("uri")!!
                    val bytes = call.argument<ByteArray>("icon")
                    val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                    val icon = if (bitmap != null) {
                        Icon.createWithBitmap(bitmap)
                    } else {
                        Icon.createWithResource(this, R.mipmap.ic_launcher)
                    }
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).setPackage(packageName)
                    val info = ShortcutInfo.Builder(this, id)
                        .setShortLabel(label)
                        .setIcon(icon)
                        .setIntent(intent)
                        .build()
                    result.success(manager.requestPinShortcut(info, null))
                } catch (e: Exception) {
                    result.error("pin_failed", e.message, null)
                }
            }
    }
}
