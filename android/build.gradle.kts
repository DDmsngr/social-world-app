allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// yandex_maps_mapkit собран под compileSdk 35, а flutter_plugin_android_lifecycle
// требует от зависящих от него модулей 36+ — сборка падает на checkAarMetadata.
// Поднимаем планку всем плагинам разом, как это сделано в SLED.
//
// Свойство ставится динамически, а не через типизированный LibraryExtension:
// AGP здесь 9.x, где старые классы расширений уже выпилены.
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.findByName("android")?.withGroovyBuilder {
                setProperty("compileSdk", 36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
