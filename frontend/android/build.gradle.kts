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

    // file_picker 8.3.7 fija compileSdk 34 en su modulo Android y el
    // AAR de flutter_plugin_android_lifecycle (2.0.35, transitorio
    // del toolchain actual) exige compilar contra 36 o superior.
    // Se eleva solo el compileSdk de los modulos de plugins (permite
    // usar APIs nuevas); targetSdk y minSdk no cambian, asi que el
    // comportamiento en ejecucion y los dispositivos soportados son
    // los mismos. :app queda fuera: ya esta evaluado aqui.
    if (name != "app") {
        afterEvaluate {
            if (plugins.hasPlugin("com.android.library")) {
                extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                    if (compileSdk == null || compileSdk!! < 36) {
                        compileSdk = 36
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
