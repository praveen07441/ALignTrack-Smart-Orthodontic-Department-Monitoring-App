// 1. UPDATED: Using AGP 8.7.0 to support Gradle 8.12 and SDK 36
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // High version (8.7.0) is required to talk to Gradle 8.12 and SDK 36
        classpath("com.android.tools.build:gradle:8.7.0") 
        // Modern Kotlin version for Java 17 compatibility
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.20")
        // Standard Google/Firebase support
        classpath("com.google.gms:google-services:4.4.0")
    }
}

// 2. Your existing logic continues here
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