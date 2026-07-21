pluginManagement {
    repositories {
        maven { url = uri("file:///workspace/local-maven-repo") }
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri("file:///workspace/local-maven-repo") }
        mavenCentral()
        google()
    }
}