package ru.socialworld.app

import android.app.Application
import com.yandex.mapkit.MapKitFactory

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MapKitFactory.setLocale("ru_RU")
        MapKitFactory.setApiKey(readEnvValue("YANDEX_MAPKIT_API_KEY") ?: DEV_MAPKIT_KEY)
    }

    private fun readEnvValue(name: String): String? = runCatching {
        assets.open("flutter_assets/.env").bufferedReader().useLines { lines ->
            lines.map(String::trim)
                .firstOrNull { it.startsWith("$name=") }
                ?.substringAfter('=')
                ?.trim()
                ?.takeIf(String::isNotEmpty)
        }
    }.getOrNull()

    private companion object {
        // MapKit требует непустой ключ до регистрации плагина; карта с этой заглушкой не создаётся.
        const val DEV_MAPKIT_KEY = "00000000-0000-0000-0000-000000000000"
    }
}
