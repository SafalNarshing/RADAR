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

// Some plugins (e.g. onnxruntime) still declare an older compileSdkVersion
// in their own android/build.gradle, which newer AGP versions reject once
// any of their dependencies (androidx.exifinterface, lifecycle-process,
// annotation-experimental, ...) require API 34+. Force every subproject to
// compile against the same SDK as the app instead of patching each plugin.
subprojects {
    val forceCompileSdk: () -> Unit = {
        extensions.findByName("android")?.let { ext ->
            if (ext is com.android.build.gradle.BaseExtension) {
                ext.compileSdkVersion(36)
            }
        }
    }
    // :app is evaluated eagerly above (evaluationDependsOn), so by the time
    // this runs for it, afterEvaluate would throw — apply directly instead.
    if (state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
