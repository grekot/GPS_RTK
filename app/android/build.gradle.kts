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

// AGP 8 wymaga `namespace` w każdym module. Starsze wtyczki (np. desktopowy
// flutter_libserialport 0.4.0 — na Androidzie go NIE używamy, korzystamy z
// usb_serial) deklarują tylko stary `package` i wywalają build: „Namespace not
// specified". Wstrzykujemy brakujący namespace z `group` wtyczki. Część modułów
// bywa już zewaluowana (przez evaluationDependsOn powyżej), więc obsługujemy oba
// przypadki — inaczej afterEvaluate rzuca „project already evaluated".
subprojects {
    fun applyNamespace() {
        val android = extensions.findByName("android") ?: return
        runCatching {
            val getNamespace = android.javaClass.getMethod("getNamespace")
            if (getNamespace.invoke(android) == null) {
                android.javaClass
                    .getMethod("setNamespace", String::class.java)
                    .invoke(android, project.group.toString())
            }
        }
    }
    if (state.executed) applyNamespace() else afterEvaluate { applyNamespace() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
