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

    // 일부 플러그인(audioplayers_android 등)이 낮은 compileSdk로 고정되어 있어
    // 최신 androidx 전이 의존성과 충돌하는 문제를 방지하기 위해, 플러그인 자신의
    // build.gradle이 compileSdk를 설정한 "이후"(afterEvaluate)에 앱과 동일한
    // 값으로 덮어씀. :app은 evaluationDependsOn으로 인해 이미 평가가 끝난
    // 상태일 수 있어 afterEvaluate 등록 시 예외가 나므로 제외.
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let {
                it.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
