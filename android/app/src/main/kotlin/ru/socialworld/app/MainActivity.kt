package ru.socialworld.app

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
