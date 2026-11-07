<#
.SYNOPSIS
    Build an Android APK for W.O.F NAI Studio.

.DESCRIPTION
    Wraps `flutter build apk` with the preflight checks this repository needs:

      * locates the Flutter SDK (WOF_FLUTTER_SDK_ROOT, FLUTTER_ROOT, the SDK
        registered in tool/flutter-sdk.json next to this checkout, or PATH),
      * locates a JDK 17-24 (flutter config jdk-dir, JAVA_HOME, -JavaHome or a
        default Adoptium / Java / Android Studio JBR installation),
      * locates the Android SDK and reports the pinned NDK,
      * refuses to build while assets/databases contains Git LFS pointer
        files instead of real SQLite databases,
      * refuses to build when the generated Dart sources are missing
        (`dart run tool/generate.dart` / `flutter gen-l10n` are not run here),
      * copies the built APKs into -OutputDir and prints their paths.

    The script never edits repository files: every option is passed to
    `flutter build apk` on the command line.

    Full setup and troubleshooting notes: docs/android-port.md.

.PARAMETER Mode
    debug (default) or release. Release currently uses the debug signing
    config from android/app/build.gradle.kts, so it is not publishable yet.

.PARAMETER TargetPlatform
    android-arm, android-arm64 (default) or android-x64.
    Use android-x64 for x86_64 emulators such as the MuMu emulator.

.PARAMETER SplitAbi
    Build one APK per ABI (armeabi-v7a, arm64-v8a, x86_64). When it is set
    and -TargetPlatform is not passed explicitly, all three ABIs are built.

.PARAMETER OutputDir
    Directory that receives the built APKs, relative to the repository root
    unless an absolute path is given. Default: dist/android (gitignored).

.PARAMETER FlutterPath
    Flutter SDK root or the flutter launcher itself. Overrides the automatic
    detection, which otherwise prefers WOF_FLUTTER_SDK_ROOT / FLUTTER_ROOT and
    the SDK registered in tool/flutter-sdk.json before falling back to PATH.

.PARAMETER JavaHome
    JDK 17-24 home directory. Default: auto-detect.

.PARAMETER DryRun
    Run the preflight checks, print the flutter command and the expected APK
    paths, then exit without invoking a build.

.EXAMPLE
    ./scripts/build_android.ps1

    Debug APK for android-arm64 in dist/android.

.EXAMPLE
    ./scripts/build_android.ps1 -Mode debug -TargetPlatform android-x64

    Debug APK for the x86_64 MuMu emulator.

.EXAMPLE
    ./scripts/build_android.ps1 -Mode release -SplitAbi

    Release APKs for armeabi-v7a, arm64-v8a and x86_64.
#>
[CmdletBinding()]
param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'debug',

    [ValidateSet('android-arm', 'android-arm64', 'android-x64')]
    [string]$TargetPlatform = 'android-arm64',

    [switch]$SplitAbi,

    [string]$OutputDir = 'dist/android',

    [string]$FlutterPath,

    [string]$JavaHome,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
# $PSBoundParameters is only meaningful in this script scope; capture it before
# calling helper functions (inside a function it describes that function).
$script:TargetPlatformExplicit = $PSBoundParameters.ContainsKey('TargetPlatform')
$script:SupportedAbis = @('android-arm', 'android-arm64', 'android-x64')
$script:AbiApkNames = @{
    'android-arm'   = 'armeabi-v7a'
    'android-arm64' = 'arm64-v8a'
    'android-x64'   = 'x86_64'
}

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
    # Redirected output can reject the encoding switch; nothing here depends on it.
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARN: $Message" -ForegroundColor Yellow
}

function Stop-Build {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$Hints = @()
    )
    Write-Host ''
    Write-Host "ERROR: $Message" -ForegroundColor Red
    foreach ($hint in $Hints) {
        Write-Host "  - $hint" -ForegroundColor Yellow
    }
    Write-Host ''
    exit 1
}

function Read-FlutterSettings {
    # Flutter stores `flutter config` values in .flutter_settings in the user
    # profile. On Windows the file lives in %APPDATA%; older layouts and
    # non-Windows hosts use the home directory. Values are read, never written.
    $settingsFiles = @(
        (Join-Path $env:APPDATA '.flutter_settings'),
        (Join-Path $env:USERPROFILE '.flutter_settings')
    )
    foreach ($settingsFile in $settingsFiles) {
        if ([string]::IsNullOrWhiteSpace($settingsFile)) { continue }
        if (-not (Test-Path -LiteralPath $settingsFile -PathType Leaf)) { continue }
        try {
            $settings = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
            return $settings
        } catch {
            continue
        }
    }
    return $null
}

function Get-FlutterSetting {
    param([string]$Name)
    $settings = Read-FlutterSettings
    if ($null -eq $settings) { return $null }
    $property = $settings.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    $value = [string]$property.Value
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value
}

function Resolve-FlutterLauncher {
    $candidates = New-Object System.Collections.Generic.List[string]

    $pinnedVersion = $null
    $pinnedEngineRevision = $null
    $sdkJson = Join-Path $script:RepoRoot 'tool/flutter-sdk.json'
    if (Test-Path -LiteralPath $sdkJson -PathType Leaf) {
        try {
            $sdkInfo = Get-Content -LiteralPath $sdkJson -Raw | ConvertFrom-Json
            $pinnedVersion = $sdkInfo.flutterVersion
            $pinnedEngineRevision = $sdkInfo.engineRevision
        } catch {
            $pinnedVersion = $null
            $pinnedEngineRevision = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($FlutterPath)) {
        $explicit = $FlutterPath.Trim().Trim('"')
        $explicitCandidates = New-Object System.Collections.Generic.List[string]
        if (Test-Path -LiteralPath $explicit -PathType Container) {
            $explicitCandidates.Add((Join-Path $explicit 'bin\flutter.bat'))
            $explicitCandidates.Add((Join-Path $explicit 'bin/flutter'))
        } else {
            $explicitCandidates.Add($explicit)
        }
        $resolvedExplicit = $explicitCandidates | Where-Object {
            Test-Path -LiteralPath $_ -PathType Leaf
        } | Select-Object -First 1
        if ($null -eq $resolvedExplicit) {
            Stop-Build "Invalid -FlutterPath: $explicit" @(
                'Pass the Flutter SDK root (contains bin\flutter.bat) or the flutter launcher itself.',
                'The path is used as given; it is not silently replaced by PATH.'
            )
        }
        $resolvedExplicit = (Resolve-Path -LiteralPath $resolvedExplicit).Path
        Assert-FlutterVersionCompatible -Launcher $resolvedExplicit -PinnedVersion $pinnedVersion -PinnedEngineRevision $pinnedEngineRevision
        return $resolvedExplicit
    }

    # Repository convention: an SDK selected through WOF_FLUTTER_SDK_ROOT /
    # FLUTTER_ROOT or the SDK registered in tool/flutter-sdk.json wins over
    # PATH. This mirrors scripts/flutter_studio.ps1.
    if (-not [string]::IsNullOrWhiteSpace($env:WOF_FLUTTER_SDK_ROOT)) {
        $candidates.Add((Join-Path $env:WOF_FLUTTER_SDK_ROOT 'bin\flutter.bat'))
        $candidates.Add((Join-Path $env:WOF_FLUTTER_SDK_ROOT 'bin/flutter'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:FLUTTER_ROOT)) {
        $candidates.Add((Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'))
        $candidates.Add((Join-Path $env:FLUTTER_ROOT 'bin/flutter'))
    }
    if (-not [string]::IsNullOrWhiteSpace($pinnedVersion)) {
        # Same locations as scripts/flutter_studio.ps1: <parent>/sdk and
        # <parent>/.devin/sdk next to this checkout.
        $candidates.Add((Join-Path $script:RepoRoot "..\..\sdk\flutter-$pinnedVersion\bin\flutter.bat"))
        $candidates.Add((Join-Path $script:RepoRoot "..\.devin\sdk\flutter-$pinnedVersion\bin\flutter.bat"))
    }

    $command = Get-Command 'flutter' -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        $candidates.Add($command.Source)
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            Assert-FlutterVersionCompatible -Launcher $resolved -PinnedVersion $pinnedVersion -PinnedEngineRevision $pinnedEngineRevision
            return $resolved
        }
    }

    Stop-Build 'No Flutter SDK found.' @(
        'Pass -FlutterPath <sdk-root-or-flutter-launcher>.',
        'Or set WOF_FLUTTER_SDK_ROOT / FLUTTER_ROOT / add flutter to PATH.',
        'See docs/android-port.md (Prerequisites).'
    )
}

function Assert-FlutterVersionCompatible {
    param(
        [string]$Launcher,
        [string]$PinnedVersion,
        [string]$PinnedEngineRevision
    )
    if ([string]::IsNullOrWhiteSpace($PinnedVersion)) { return }
    $info = Get-FlutterVersionInfo -Launcher $Launcher
    if ($info.Version -eq 'unknown') {
        # A freshly unzipped/git-cloned SDK has no bin/cache/flutter.version.json
        # until `flutter` runs once. Fall back to the engine revision that
        # tool/flutter-sdk.json pins, which is available in the SDK checkout.
        $engineFile = Join-Path $info.Root 'bin/internal/engine.version'
        if (-not [string]::IsNullOrWhiteSpace($PinnedEngineRevision) -and
            (Test-Path -LiteralPath $engineFile -PathType Leaf)) {
            $engineRevision = (Get-Content -LiteralPath $engineFile -Raw).Trim()
            if ($engineRevision -eq $PinnedEngineRevision) {
                Write-Ok "Flutter version file is not generated yet; SDK engine revision matches $PinnedVersion."
                return
            }
        }
        Write-Warn "Could not read the Flutter version of $Launcher; tool/flutter-sdk.json registers $PinnedVersion."
        return
    }
    if ($info.Version -ne $PinnedVersion) {
        Stop-Build "Flutter $($info.Version) is not the SDK this repository requires (Flutter $PinnedVersion)." @(
            "Launcher: $Launcher",
            "Use: scripts/flutter_studio.ps1 -SdkRoot <flutter-$PinnedVersion> -FlutterArgs @('build','apk','--debug',...)",
            "Or set WOF_FLUTTER_SDK_ROOT to the Flutter $PinnedVersion SDK, or pass -FlutterPath.",
            'A mismatched SDK fails with confusing compile errors (for example "No named parameter with the name ...") because the Android scaffold and the source target the pinned SDK.'
        )
    }
}

function Get-FlutterVersionInfo {
    param([string]$Launcher)
    $flutterRoot = Split-Path -Parent (Split-Path -Parent $Launcher)
    $versionFile = Join-Path $flutterRoot 'bin/cache/flutter.version.json'
    $version = 'unknown'
    $dartVersion = $null
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        try {
            $json = Get-Content -LiteralPath $versionFile -Raw | ConvertFrom-Json
            if (-not [string]::IsNullOrWhiteSpace($json.flutterVersion)) { $version = $json.flutterVersion }
            if (-not [string]::IsNullOrWhiteSpace($json.dartSdkVersion)) { $dartVersion = $json.dartSdkVersion }
        } catch {
            # Fall through with the "unknown" version; the build itself still works.
        }
    }
    return [pscustomobject]@{
        Root        = $flutterRoot
        Version     = $version
        DartVersion = $dartVersion
    }
}

function Get-JdkMajorVersion {
    param([string]$JdkHome)
    $releaseFile = Join-Path $JdkHome 'release'
    if (-not (Test-Path -LiteralPath $releaseFile -PathType Leaf)) {
        # macOS-style JDK home: bin/java exists but there is no release file.
        $javaExe = Join-Path $JdkHome 'bin/java'
        if (Test-Path -LiteralPath $javaExe -PathType Leaf) { return $null }
        return $null
    }
    $match = Select-String -LiteralPath $releaseFile -Pattern '^JAVA_VERSION="([^"]+)"' |
        Select-Object -First 1
    if ($null -eq $match) { return $null }
    $raw = $match.Matches[0].Groups[1].Value
    if ($raw -match '^1\.(\d+)') { return [int]$Matches[1] }
    if ($raw -match '^(\d+)') { return [int]$Matches[1] }
    return $null
}

function Resolve-JavaHome {
    $candidates = New-Object System.Collections.Generic.List[string]
    $rejected = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($JavaHome)) {
        $candidates.Add($JavaHome.Trim().Trim('"'))
    } else {
        $configured = Get-FlutterSetting -Name 'jdk-dir'
        if ($null -ne $configured) { $candidates.Add($configured) }
        if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) { $candidates.Add($env:JAVA_HOME) }

        $patterns = @()
        if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
            $patterns += (Join-Path $env:ProgramFiles 'Eclipse Adoptium\jdk-*')
            $patterns += (Join-Path $env:ProgramFiles 'Java\jdk-*')
            $patterns += (Join-Path $env:ProgramFiles 'Microsoft\jdk-*')
            $patterns += (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr')
        }
        $programFilesX86 = ${env:ProgramFiles(x86)}
        if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
            $patterns += (Join-Path $programFilesX86 'Eclipse Adoptium\jdk-*')
        }
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $patterns += (Join-Path $env:LOCALAPPDATA 'Programs\Eclipse Adoptium\jdk-*')
            $patterns += (Join-Path $env:LOCALAPPDATA 'Programs\Android Studio\jbr')
        }
        foreach ($pattern in $patterns) {
            $found = @(Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue)
            if ($found.Count -eq 0) { continue }
            # Prefer the highest JDK number found in the directory name.
            $sorted = $found | Sort-Object -Property @{
                Expression = {
                    if ($_.Name -match '(\d+)(?:\.\d+)?') { [int]$Matches[1] } else { 0 }
                }
            } -Descending
            foreach ($directory in $sorted) { $candidates.Add($directory.FullName) }
        }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $trimmed = $candidate.Trim().Trim('"').TrimEnd('\', '/')
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $key = $trimmed.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $hasJava = (Test-Path -LiteralPath (Join-Path $trimmed 'bin\java.exe') -PathType Leaf) -or
            (Test-Path -LiteralPath (Join-Path $trimmed 'bin/java') -PathType Leaf)
        if (-not $hasJava) { continue }

        $major = Get-JdkMajorVersion -JdkHome $trimmed
        if ($null -eq $major) {
            # JDK 17 shipped in Android Studio has a release file, so an
            # unknown version is only tolerated for a configured JDK.
            $rejected.Add("$trimmed (unknown version)")
            continue
        }
        if ($major -lt 17) {
            $rejected.Add("$trimmed (JDK $major)")
            continue
        }
        if ($major -gt 24) {
            $rejected.Add("$trimmed (JDK $major; Gradle 8.14 supports up to JDK 24)")
            continue
        }
        return [pscustomobject]@{ Home = $trimmed; Major = $major }
    }

    $hints = @()
    if ($rejected.Count -gt 0) {
        $hints += ('Ignored unsuitable JDKs: ' + ($rejected -join '; '))
    }
    $hints += 'Install Eclipse Temurin JDK 17, then run: flutter config --jdk-dir="<jdk-17-home>"'
    $hints += 'Or pass -JavaHome <jdk-17-home>.'
    Stop-Build 'No JDK 17+ installation found (Gradle 8.14 / AGP 8.11 need JDK 17-24).' $hints
}

function Get-AndroidSdkCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) { $candidates.Add($env:ANDROID_HOME) }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) { $candidates.Add($env:ANDROID_SDK_ROOT) }

    $localProperties = Join-Path $script:RepoRoot 'android/local.properties'
    if (Test-Path -LiteralPath $localProperties -PathType Leaf) {
        $match = Select-String -LiteralPath $localProperties -Pattern '^sdk\.dir=(.+)$' |
            Select-Object -First 1
        if ($null -ne $match) {
            # Java properties escape backslashes: C:\\Users\\... -> C:\Users\...
            $candidates.Add(($match.Matches[0].Groups[1].Value.Trim() -replace '\\\\', '\'))
        }
    }

    $configured = Get-FlutterSetting -Name 'android-sdk'
    if ($null -ne $configured) { $candidates.Add($configured) }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Android\sdk'))
    }
    return $candidates
}

function Resolve-AndroidSdk {
    foreach ($candidate in Get-AndroidSdkCandidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $trimmed = $candidate.Trim().Trim('"').TrimEnd('\', '/')
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $hasPlatformTools = Test-Path -LiteralPath (Join-Path $trimmed 'platform-tools') -PathType Container
        $hasPlatforms = Test-Path -LiteralPath (Join-Path $trimmed 'platforms') -PathType Container
        if ($hasPlatformTools -or $hasPlatforms) { return $trimmed }
    }
    Stop-Build 'Android SDK not found.' @(
        'Set ANDROID_HOME / ANDROID_SDK_ROOT, or run: flutter config --android-sdk="<sdk-path>"',
        'Typical Windows path: %LOCALAPPDATA%\Android\sdk',
        'See docs/android-port.md (Prerequisites).'
    )
}

function Get-PinnedNdkVersion {
    $gradleFile = Join-Path $script:RepoRoot 'android/app/build.gradle.kts'
    if (-not (Test-Path -LiteralPath $gradleFile -PathType Leaf)) { return $null }
    $match = Select-String -LiteralPath $gradleFile -Pattern 'ndkVersion\s*=\s*"([^"]+)"' |
        Select-Object -First 1
    if ($null -eq $match) { return $null }
    return $match.Matches[0].Groups[1].Value
}

function Assert-BundledDatabases {
    $databaseDirectory = Join-Path $script:RepoRoot 'assets/databases'
    if (-not (Test-Path -LiteralPath $databaseDirectory -PathType Container)) {
        Write-Warn 'assets/databases is missing; tag and wiki features will be unavailable in the APK.'
        return
    }
    $databaseFiles = @(Get-ChildItem -LiteralPath $databaseDirectory -File -Filter '*.db' -ErrorAction SilentlyContinue)
    if ($databaseFiles.Count -eq 0) {
        Write-Warn 'assets/databases has no *.db files; tag and wiki features will be unavailable in the APK.'
        return
    }

    $sample = $databaseFiles[0]
    $read = 0
    $buffer = New-Object byte[] 64
    $stream = [System.IO.File]::OpenRead($sample.FullName)
    try {
        $read = $stream.Read($buffer, 0, $buffer.Length)
    } finally {
        $stream.Dispose()
    }
    if ($read -eq 0) {
        Stop-Build "$($sample.Name) is empty." @(
            'Run: git lfs install; git lfs pull'
        )
    }
    $head = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
    if ($head.StartsWith('version https://git-lfs')) {
        Stop-Build "$($sample.Name) is still a Git LFS pointer file." @(
            'Run: git lfs install; git lfs pull',
            'The APK would bundle placeholder databases instead of real SQLite files.'
        )
    }
}

function Assert-GeneratedSources {
    # *.g.dart / *.freezed.dart are gitignored and regenerated by
    # `dart run tool/generate.dart`; the tracked ARB localizations are produced
    # by `flutter gen-l10n`. This script does not run code generation because it
    # writes files; it fails with the exact commands instead.
    $libDirectory = Join-Path $script:RepoRoot 'lib'
    $generatedFiles = @(Get-ChildItem -LiteralPath $libDirectory -Recurse -Filter '*.g.dart' -File -ErrorAction SilentlyContinue)
    $localizations = Join-Path $libDirectory 'l10n/app_localizations.dart'
    if ($generatedFiles.Count -eq 0 -or -not (Test-Path -LiteralPath $localizations -PathType Leaf)) {
        Stop-Build 'Generated Dart sources are missing; a fresh checkout cannot build directly.' @(
            'Run, from the repository root:',
            '  flutter pub get',
            '  dart run tool/generate.dart',
            '  flutter gen-l10n',
            'See docs/android-port.md (Build) and AGENTS.md.'
        )
    }
}

function Get-ExpectedApkNames {
    param(
        [string]$BuildMode,
        [string[]]$TargetPlatforms,
        [bool]$Split
    )
    if ($Split) {
        return @($TargetPlatforms | ForEach-Object { "app-$($script:AbiApkNames[$_])-$BuildMode.apk" })
    }
    return @("app-$BuildMode.apk")
}

function Get-BuildPlan {
    $buildArguments = New-Object System.Collections.Generic.List[string]
    $buildArguments.Add('build')
    $buildArguments.Add('apk')
    $buildArguments.Add("--$Mode")

    if ($SplitAbi) {
        $buildArguments.Add('--split-per-abi')
        if ($script:TargetPlatformExplicit) {
            $buildArguments.Add('--target-platform')
            $buildArguments.Add($TargetPlatform)
            $targetPlatforms = @($TargetPlatform)
        } else {
            $targetPlatforms = @($script:SupportedAbis)
        }
    } else {
        $buildArguments.Add('--target-platform')
        $buildArguments.Add($TargetPlatform)
        $targetPlatforms = @($TargetPlatform)
    }

    return [pscustomobject]@{
        Arguments       = @($buildArguments)
        TargetPlatforms = @($targetPlatforms)
    }
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

Write-Step 'Android build preflight'

$flutterLauncher = Resolve-FlutterLauncher
$flutter = Get-FlutterVersionInfo -Launcher $flutterLauncher
$java = Resolve-JavaHome
$androidSdk = Resolve-AndroidSdk

Write-Ok "Repository: $($script:RepoRoot)"
Write-Ok "Flutter:    $flutterLauncher"
Write-Ok "Flutter version: $($flutter.Version)$(if ($flutter.DartVersion) { " (Dart $($flutter.DartVersion))" })"
Write-Ok "Java:       $($java.Home) (JDK $($java.Major))"
Write-Ok "Android SDK: $androidSdk"

if (-not [string]::IsNullOrWhiteSpace($JavaHome)) {
    # Flutter resolves the Gradle JDK from `flutter config jdk-dir` first, then
    # Android Studio, then JAVA_HOME, so -JavaHome cannot override the config.
    $configuredJdk = Get-FlutterSetting -Name 'jdk-dir'
    if (-not [string]::IsNullOrWhiteSpace($configuredJdk) -and
        ($configuredJdk.TrimEnd('\', '/').ToLowerInvariant() -ne $java.Home.TrimEnd('\', '/').ToLowerInvariant())) {
        Write-Warn "flutter config jdk-dir is $configuredJdk; Flutter uses it for Gradle instead of -JavaHome."
        Write-Warn "To switch the build JDK, run: flutter config --jdk-dir=`"$($java.Home)`""
    }
}

$pinnedNdk = Get-PinnedNdkVersion
if (-not [string]::IsNullOrWhiteSpace($pinnedNdk)) {
    $ndkDirectory = Join-Path $androidSdk "ndk/$pinnedNdk"
    if (Test-Path -LiteralPath $ndkDirectory -PathType Container) {
        Write-Ok "NDK:        $pinnedNdk"
    } else {
        Write-Warn "NDK $pinnedNdk is not installed in $androidSdk (Gradle will download it on the first build; that is ~1 GB)."
    }
}

$licensesDirectory = Join-Path $androidSdk 'licenses'
if (-not (Test-Path -LiteralPath $licensesDirectory -PathType Container)) {
    Write-Warn 'The Android SDK licenses directory is missing; Gradle cannot auto-download platforms, build-tools or the NDK.'
    Write-Warn "Run: $androidSdk\cmdline-tools\latest\bin\sdkmanager.bat --licenses"
}

$expectedCompileSdk = 'android-36'
if (-not (Test-Path -LiteralPath (Join-Path $androidSdk "platforms/$expectedCompileSdk") -PathType Container)) {
    Write-Warn "Android platform $expectedCompileSdk is not installed; Gradle will download it if the SDK licenses are accepted."
}

Assert-BundledDatabases
Assert-GeneratedSources

# Gradle and the Flutter tool inherit these from the process environment.
$env:JAVA_HOME = $java.Home

$plan = Get-BuildPlan
$expectedApks = Get-ExpectedApkNames -BuildMode $Mode -TargetPlatforms $plan.TargetPlatforms -Split:$SplitAbi
$apkDirectory = Join-Path $script:RepoRoot 'build/app/outputs/flutter-apk'

Write-Host ''
Write-Step "Planned command"
Write-Host ("    flutter " + ($plan.Arguments -join ' ')) -ForegroundColor White
Write-Ok ("Target ABI(s): " + ($plan.TargetPlatforms -join ', '))
Write-Ok ("Expected APK(s): " + ($expectedApks -join ', '))
if ($Mode -eq 'release') {
    Write-Warn 'Release APKs use the debug signing config (TODO in android/app/build.gradle.kts); do not distribute them.'
}

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run: preflight checks finished, no build was started.' -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

Write-Host ''
Write-Step "Building $Mode APK"
Push-Location -LiteralPath $script:RepoRoot
try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $flutterArguments = $plan.Arguments
    & $flutterLauncher @flutterArguments
    $buildExitCode = $LASTEXITCODE
    $stopwatch.Stop()
} finally {
    Pop-Location
}

if ($buildExitCode -ne 0) {
    Stop-Build "flutter build apk failed with exit code $buildExitCode." @(
        'Read the Gradle/Flutter output above.',
        'See the Troubleshooting section of docs/android-port.md.'
    )
}

# ---------------------------------------------------------------------------
# Collect and copy artifacts
# ---------------------------------------------------------------------------

$artifacts = New-Object System.Collections.Generic.List[string]
foreach ($apkName in $expectedApks) {
    $apkPath = Join-Path $apkDirectory $apkName
    if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
        $available = @(Get-ChildItem -LiteralPath $apkDirectory -File -Filter '*.apk' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name })
        $availableHint = if ($available.Count -gt 0) { $available -join ', ' } else { '(none)' }
        Stop-Build "Expected APK was not produced: $apkPath" @(
            "Files in $apkDirectory : $availableHint",
            'If the Gradle output naming changed, update Get-ExpectedApkNames in this script.'
        )
    }
    $artifacts.Add($apkPath)
}

$outputDirectory = $OutputDir
if (-not [System.IO.Path]::IsPathRooted($outputDirectory)) {
    $outputDirectory = Join-Path $script:RepoRoot $outputDirectory
}
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$outputDirectory = (Resolve-Path -LiteralPath $outputDirectory).Path

$copiedArtifacts = New-Object System.Collections.Generic.List[string]
foreach ($apkPath in $artifacts) {
    $destination = Join-Path $outputDirectory (Split-Path -Leaf $apkPath)
    Copy-Item -LiteralPath $apkPath -Destination $destination -Force
    $copiedArtifacts.Add($destination)
}

Write-Host ''
Write-Host ("Build finished in {0:N1} min." -f $stopwatch.Elapsed.TotalMinutes) -ForegroundColor Green
foreach ($copiedArtifact in $copiedArtifacts) {
    $sizeMb = (Get-Item -LiteralPath $copiedArtifact).Length / 1MB
    Write-Host ("  {0}  ({1:N1} MB)" -f $copiedArtifact, $sizeMb) -ForegroundColor Green
}

$adb = Join-Path $androidSdk 'platform-tools/adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    $adbCommand = Get-Command 'adb' -ErrorAction SilentlyContinue
    $adb = if ($null -ne $adbCommand) { $adbCommand.Source } else { $null }
}
if (-not [string]::IsNullOrWhiteSpace($adb)) {
    Write-Host ''
    Write-Host 'Install on a connected device or emulator:' -ForegroundColor Cyan
    foreach ($copiedArtifact in $copiedArtifacts) {
        Write-Host ("  `"{0}`" install -r `"{1}`"" -f $adb, $copiedArtifact)
    }
    if ($TargetPlatform -eq 'android-x64' -and -not $SplitAbi) {
        Write-Host '  (android-x64 APKs only run on x86_64 emulators, for example the MuMu emulator at 127.0.0.1:16384.)'
    }
} else {
    Write-Warn 'adb was not found; install it through the Android SDK platform-tools package to deploy the APK.'
}

exit 0
