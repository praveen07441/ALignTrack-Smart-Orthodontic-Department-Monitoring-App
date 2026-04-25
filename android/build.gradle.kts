buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // AGP 8.7.0 supports Gradle 8.12 and SDK 36
        classpath("com.android.tools.build:gradle:8.7.0")
        // Kotlin 1.9.22 for Java 17 compatibility
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22")
        // Google Services / Firebase
        classpath("com.google.gms:google-services:4.4.1")
    }
}

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