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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Provide properties for older flutter plugins (like app_links) that look for rootProject.ext
extra.set("compileSdkVersion", 34)
extra.set("minSdkVersion", 24)
extra.set("targetSdkVersion", 34)
extra.set("ndkVersion", "26.1.10909125")
