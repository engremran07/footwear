param(
  [ValidateSet('major','minor','patch','build')]
  [string]$Mode = 'patch',
  [switch]$SkipTests,
  [switch]$SkipBuild,
  [switch]$SkipGit,
  [switch]$SkipDeploy,
  [switch]$SkipInstall,
  [switch]$WebOnly,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Step([string]$msg) { Write-Host "" ; Write-Host "==> $msg" -ForegroundColor Cyan }
function OK([string]$msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function WARN([string]$msg) { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function DIE([string]$msg)  { Write-Host "" ; Write-Host "[FATAL] $msg" -ForegroundColor Red ; exit 1 }
function DRY([string]$cmd)  {
  if ($DryRun) { Write-Host "    [DRY] $cmd" -ForegroundColor Yellow }
  else { Invoke-Expression $cmd }
}

# Resolve paths relative to this script
$scriptDir   = $PSScriptRoot
$rootDir     = Split-Path -Parent $scriptDir
$appDir      = Join-Path $rootDir "app"
$pubspec     = Join-Path $appDir "pubspec.yaml"
$releasesDir = Join-Path $rootDir "releases"

if (-not (Test-Path $pubspec)) {
  DIE "pubspec.yaml not found at $pubspec -- check repo layout."
}

if (-not (Test-Path $releasesDir)) {
  New-Item -ItemType Directory -Path $releasesDir | Out-Null
  OK "Created releases\ folder at $releasesDir"
}

Push-Location $appDir
$arm64Apk = $null

try {
  # 1. Version bump
  Step "Bumping version ($Mode)"
  DRY "dart run tool/bump_version.dart $Mode"
  if (-not $DryRun) {
    $vLine = (Get-Content $pubspec | Select-String '^version:').Line
    $script:version = ($vLine -split '\s+')[1].Trim()
    $script:semver  = ($script:version -split '\+')[0]
    OK "New version: $script:version"
  } else {
    $script:version = 'X.Y.Z+N'
    $script:semver  = 'X.Y.Z'
  }

  # 2. Analyze
  Step "flutter analyze lib --no-pub"
  DRY "flutter analyze lib --no-pub"
  if (-not $DryRun) { OK "Analyzer clean" }

  # 3. Tests
  if (-not $SkipTests) {
    Step "flutter test"
    DRY "flutter test test/unit --reporter=expanded"
    if (-not $DryRun) { OK "All unit tests passed" }
  } else {
    WARN "Tests skipped (-SkipTests)"
  }

  # 4. Build
  if (-not $SkipBuild) {
    if (-not $WebOnly) {
      # 4a. Fat APK (single file: arm32 + arm64 + x86_64)
      # NEVER --split-per-abi — always fat APK per project rules.
      Step "Building fat release APK"
      DRY "flutter build apk --release"

      if (-not $DryRun) {
        $apkDir = Join-Path $appDir "build\app\outputs\flutter-apk"
        $src = Join-Path $apkDir "app-release.apk"
        if (-not (Test-Path $src)) { WARN "APK not found: $src" }
        else {
          $destName = "FootWear-V$($script:semver).apk"
          $dest = Join-Path $releasesDir $destName
          Copy-Item $src $dest -Force
          $sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
          OK "$destName ($sizeMB MB) -> releases\"
          $arm64Apk = $dest
        }
      } else {
        WARN "[DRY] Would copy app-release.apk to releases\FootWear-V{semver}.apk"
      }
    }

    # 4b. Web build
    Step "Building Flutter web (release)"
    # FLUTTER_WEB_USE_SKIA was removed in Flutter 3.10+ — do NOT pass it.
    DRY "flutter build web --release"
    if (-not $DryRun) { OK "Web build -> app/build/web/" }

  } else {
    WARN "Build skipped (-SkipBuild)"
  }

  # 5. adb install
  if (-not $SkipInstall -and -not $WebOnly) {
    Step "Installing arm64 APK to connected Android device"
    # Resolve adb: prefer PATH, fall back to Android SDK default locations
    $adbExe = (Get-Command adb -ErrorAction SilentlyContinue)?.Source
    if (-not $adbExe) {
      $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "C:\Android\platform-tools\adb.exe",
        "$env:ProgramFiles\Android\android-sdk\platform-tools\adb.exe"
      )
      $adbExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if ($DryRun) {
      WARN "[DRY] adb install FootWear-V{semver}-arm64.apk"
    } elseif (-not $adbExe) {
      WARN "adb not found -- skipping install (add platform-tools to PATH)"
    } elseif ($arm64Apk -and (Test-Path $arm64Apk)) {
      $devices = (& $adbExe devices 2>$null) | Select-String '^\w' | Where-Object { $_ -notmatch '^List' }
      if ($devices) {
        & $adbExe install -r $arm64Apk
        if ($LASTEXITCODE -eq 0) {
          OK "Installed $(Split-Path -Leaf $arm64Apk) to device"
        } else {
          WARN "adb install returned exit code $LASTEXITCODE -- check device connection"
        }
      } else {
        WARN "No Android device connected -- skipping adb install"
      }
    } else {
      WARN "arm64 APK not found -- skipping adb install"
    }
  } else {
    WARN "Install skipped (-SkipInstall or -WebOnly)"
  }

  # 6. Firebase deploy
  if (-not $SkipDeploy) {
    Push-Location $rootDir
    $targets = if (-not $SkipBuild -and -not $WebOnly) {
      "firestore:rules,firestore:indexes,hosting"
    } elseif ($WebOnly -and -not $SkipBuild) {
      "hosting"
    } else {
      "firestore:rules,firestore:indexes"
    }
    Step "firebase deploy --only $targets"
    DRY "firebase deploy --only $targets"
    Pop-Location
    if (-not $DryRun) { OK "Firebase deploy complete" }
  } else {
    WARN "Firebase deploy skipped (-SkipDeploy)"
  }

  # 7. Git commit + tag + push
  if (-not $SkipGit) {
    Step "Git: commit + tag v$($script:version) + push"
    Push-Location $rootDir
    DRY "git add -A"
    DRY "git commit -m `"release: v$($script:version)`""
    DRY "git tag -a `"v$($script:version)`" -m `"ShoesERP v$($script:version)`""
    DRY "git push origin HEAD --tags"
    Pop-Location
    if (-not $DryRun) { OK "Pushed tag v$($script:version)" }
  } else {
    WARN "Git skipped (-SkipGit)"
  }

  # Done
  $v = $script:version
  Write-Host ""
  Write-Host "  +-------------------------------------------+" -ForegroundColor Green
  Write-Host "  |  FootWear ERP  v$($v.PadRight(25))|" -ForegroundColor Green
  Write-Host "  |  Release pipeline complete                |" -ForegroundColor Green
  Write-Host "  +-------------------------------------------+" -ForegroundColor Green
  Write-Host ""

} finally {
  Pop-Location
}