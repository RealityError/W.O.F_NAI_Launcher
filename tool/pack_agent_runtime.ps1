# Packs the bundled NAI Agent Node runtime for Android.
#
# The Android app cannot execute binaries, so the whole Pi host (host.mjs,
# lib/, skills/ and node_modules/) ships as one gzipped tar asset and is
# extracted on first use. Run from the repository root:
#
#   ./tool/pack_agent_runtime.ps1
#
# Bump AndroidNodeRuntimeBundle.bundleVersion in
# lib/core/nai_agent/node_runtime_bundle.dart when the packed content changes;
# existing installs then re-extract the runtime.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot 'nai_agent'
$output = Join-Path $root 'assets\nai_agent\runtime.tar.gz'
$entries = @(
  'host.mjs',
  'lib',
  'skills',
  'node_modules',
  'package.json',
  'package-lock.json',
  'PI-LICENSE'
)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
Push-Location $source
try {
  tar -czf $output @entries
  if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
$size = (Get-Item $output).Length
Write-Host ("packed {0:N1} MB -> {1}" -f ($size / 1MB), (Resolve-Path $output))
