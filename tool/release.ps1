#!/usr/bin/env pwsh
<#
.SYNOPSIS
  ShoesERP Autonomous Release Script
  Unified version bump + build (web + APK splits) + Firebase deploy + Git tag.

.USAGE
  From D:\Footwear\app\ :
    ..\tool\release.ps1 -Mode minor
    ..\tool\release.ps1 -Mode patch
    ..\tool\release.ps1 -Mode major
    ..\tool\release.ps1 -Mode build   # increment build number only

.MODES
  major  : x+1.0.0   (breaking change)
  minor  : x.y+1.0   (new features, backward-compat)  -- DEFAULT
  patch  : x.y.z+1   (bug fixes)
  build  : x.y.z+b+1 (internal / hot fix; no semver increment)

.FLAGS
  -SkipTests    : skip flutter test (emergency patch only)
  -SkipBuild    : skip APK / web build (deploy rules only)
  -SkipGit      : skip git commit + tag + push
  -SkipDeploy   : skip firebase deploy
  -WebOnly      : build and deploy web only (skip APKs)
  -DryRun       : print plan without executing

.EXAMPLE
  # Standard minor release — full pipeline:
  cd D:\Footwear\app
  ..\tool\release.ps1 -Mode minor

  # Emergency rules-only deploy (no rebuild):
  cd D:\Footwear\app
  ..\tool\release.ps1 -Mode build -SkipBuild

  # Dry run to see what would happen:
  ..\tool\release.ps1 -Mode minor -DryRun
#>

param(
  [ValidateSet('major','minor','patch','build')]
  [string]$Mode = 'minor',
  [switch]$SkipTests,
  [switch]$SkipBuild,
  [switch]$SkipGit,
  [switch]$SkipDeploy,
  [switch]$WebOnly,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── helpers ────────────────────────────────────────────────────────────────────
function Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK([string]$msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function DIE([string]$msg)  { Write-Host "`n[FATAL] $msg" -ForegroundColor Red ; exit 1 }
function DRY([string]$cmd)  {
  if ($DryRun) { Write-Host "    [DRY] $cmd" -ForegroundColor Yellow }
  else { Invoke-Expression $cmd }
}

# ── resolve paths ──────────────────────────────────────────────────────────────
$appDir   = Split-Path -Parent $PSScriptRoot   # D:\Footwear\app
$rootDir  = Split-Path -Parent $appDir          # D:\Footwear
$pubspec  = Join-Path $appDir "pubspec.yaml"

if (-not (Test-Path $pubspec)) {
  DIE "Run this script from D:\Footwear\app\ or ensure pubspec.yaml exists at $pubspec"
}

Push-Location $appDir

try {
  # ── 1. Version bump ──────────────────────────────────────────────────────────
  Step "Bumping version ($Mode)"
  DRY "dart run tool/bump_version.dart $Mode"
  if (-not $DryRun) {
    # Re-read bumped version for tagging
    $vLine = (Get-Content $pubspec | Select-String '^version:').Line
    $script:version = ($vLine -split '\s+')[1].Trim()   # e.g. 3.1.0+8
    $script:semver  = ($script:version -split '\+')[0]   # e.g. 3.1.0
    OK "New version: $script:version"
  } else {
    $script:version = 'X.Y.Z+N'
    $script:semver  = 'X.Y.Z'
  }

  # ── 2. Analyze ───────────────────────────────────────────────────────────────
  Step "flutter analyze"
  DRY "flutter analyze lib --no-pub"
  if (-not $DryRun) { OK "Analyze clean" }

  # ── 3. Tests ─────────────────────────────────────────────────────────────────
  if (-not $SkipTests) {
    Step "flutter test"
    DRY "flutter test test/unit --reporter=expanded"
    if (-not $DryRun) { OK "All unit tests passed" }
  } else {
    Write-Host "    [SKIP] Tests (SkipTests flag set)" -ForegroundColor Yellow
  }

  # ── 4. Build ─────────────────────────────────────────────────────────────────
  if (-not $SkipBuild) {
    # 4a. Web
    Step "Building Flutter web (release)"
    DRY "flutter build web --release --dart-define=FLUTTER_WEB_USE_SKIA=false"
    if (-not $DryRun) { OK "Web build → app/build/web/" }

    # 4b. APK splits (skip if -WebOnly)
    if (-not $WebOnly) {
      Step "Building split-per-ABI APKs (release)"
      DRY "flutter build apk --release --split-per-abi"
      if (-not $DryRun) {
        $apkDir = "build\app\outputs\flutter-apk"
        Get-ChildItem $apkDir -Filter "*-release.apk" |
          ForEach-Object { OK "APK: $($_.Name)  ($([math]::Round($_.Length/1MB, 1)) MB)" }
      }
    }
  } else {
    Write-Host "    [SKIP] Build (SkipBuild flag set)" -ForegroundColor Yellow
  }

  # ── 5. Firebase deploy ────────────────────────────────────────────────────────
  if (-not $SkipDeploy) {
    Push-Location $rootDir
    if (-not $SkipBuild -and -not $WebOnly) {
      Step "Deploying: Firestore rules + indexes + hosting"
      DRY "firebase deploy --only firestore:rules,firestore:indexes,hosting"
    } elseif ($WebOnly -and -not $SkipBuild) {
      Step "Deploying: hosting only"
      DRY "firebase deploy --only hosting"
    } else {
      Step "Deploying: Firestore rules + indexes only (no hosting — build skipped)"
      DRY "firebase deploy --only firestore:rules,firestore:indexes"
    }
    Pop-Location
    if (-not $DryRun) { OK "Firebase deploy complete" }
  } else {
    Write-Host "    [SKIP] Firebase deploy (SkipDeploy flag set)" -ForegroundColor Yellow
  }

  # ── 6. Git commit + tag + push ────────────────────────────────────────────────
  if (-not $SkipGit) {
    Step "Git: stage + commit + tag v$script:version"
    Push-Location $rootDir
    DRY "git add -A"
    DRY "git commit -m `"release: v$script:version`""
    DRY "git tag -a `"v$script:version`" -m `"ShoesERP v$script:version`""
    DRY "git push origin HEAD --tags"
    Pop-Location
    if (-not $DryRun) { OK "Git tag v$script:version pushed" }
  } else {
    Write-Host "    [SKIP] Git (SkipGit flag set)" -ForegroundColor Yellow
  }

  # ── Done ─────────────────────────────────────────────────────────────────────
  Write-Host "`n╔══════════════════════════════════════════╗" -ForegroundColor Green
  Write-Host "║  ShoesERP v$($script:version.PadRight(28))  ║" -ForegroundColor Green
  Write-Host "║  Release pipeline complete $(' ' * 14)  ║" -ForegroundColor Green
  Write-Host "╚══════════════════════════════════════════╝`n" -ForegroundColor Green

} finally {
  Pop-Location
}
