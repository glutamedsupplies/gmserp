# Creates android/upload-keystore.jks and reminds you to copy key.properties.example
# Run from project root:  powershell -ExecutionPolicy Bypass -File tool/create_android_keystore.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$keystore = Join-Path $root "android\upload-keystore.jks"
$propsExample = Join-Path $root "android\key.properties.example"
$props = Join-Path $root "android\key.properties"

function Find-Keytool {
    $fromPath = Get-Command keytool -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin\keytool.exe"))
    }
    $candidates.Add("C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe")
    $candidates.Add("C:\Program Files\Android\Android Studio\jre\bin\keytool.exe")
    $candidates.Add("C:\Program Files\Java\jdk-17\bin\keytool.exe")
    $candidates.Add("C:\Program Files\Java\jdk-21\bin\keytool.exe")
    $candidates.Add("C:\Program Files\Eclipse Adoptium\jdk-17*\bin\keytool.exe")
    $candidates.Add("C:\Program Files\Eclipse Adoptium\jdk-21*\bin\keytool.exe")

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $resolved = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved -and (Test-Path $resolved.FullName)) {
            return $resolved.FullName
        }
    }

    return $null
}

if (Test-Path $keystore) {
    Write-Host "Keystore already exists: $keystore"
    exit 0
}

$keytoolPath = Find-Keytool
if (-not $keytoolPath) {
    Write-Error "keytool not found. Install Android Studio or JDK, then re-run this script."
}

Write-Host "Using keytool: $keytoolPath"
Write-Host "Creating release keystore at $keystore"
Write-Host "You will be prompted for store password, key password, and certificate details."
& $keytoolPath -genkey -v `
    -keystore $keystore `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -alias upload

if (-not (Test-Path $props)) {
    Copy-Item $propsExample $props
    Write-Host ""
    Write-Host "Created $props - edit it with your store and key passwords."
} else {
    Write-Host "key.properties already exists; not overwritten."
}

Write-Host ""
Write-Host "Release build:  flutter build appbundle --release"
Write-Host "Upload app-release.aab to Google Play Console for OTA updates."
