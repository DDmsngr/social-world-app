package ru.socialworld.app

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
