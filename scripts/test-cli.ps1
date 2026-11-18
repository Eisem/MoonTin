# Run from any directory with PowerShell and the MoonBit toolchain.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Assert-Equal($Actual, $Expected, [string]$Context) {
    if ($Actual -ne $Expected) {
        throw "$Context expected '$Expected', got '$Actual'."
    }
}

function Invoke-MoonTin([string[]]$Arguments, [int]$ExpectedExit) {
    $stdout = & $cliPath @Arguments 2> $stderrPath
    $exitCode = $LASTEXITCODE
    Assert-Equal $exitCode $ExpectedExit ($Arguments -join ' ')
    [pscustomobject]@{
        Stdout = $stdout -join "`n"
        Stderr = Get-Content -LiteralPath $stderrPath -Raw
    }
}

Push-Location (Join-Path $PSScriptRoot '..')
$stderrPath = [IO.Path]::GetTempFileName()
$emptyPath = [IO.Path]::GetTempFileName()
try {
    & moon build --target native cmd/main
    Assert-Equal $LASTEXITCODE 0 'Native build exit'
    $binary = if ($IsWindows) { 'main.exe' } else { 'main' }
    $cliPath = (Resolve-Path (Join-Path '_build/native/debug/build/cmd/main' $binary)).Path

    $valid = Invoke-MoonTin @('check', 'examples/terrain.xml', '--format', 'json') 0
    $validReport = $valid.Stdout | ConvertFrom-Json
    Assert-Equal $validReport.status 'passed' 'Valid sample status'
    Assert-Equal $validReport.surfaces[0].boundary_edges 3 'Valid sample edge count'
    Assert-Equal ([string]::IsNullOrWhiteSpace($valid.Stderr)) $true 'Valid sample stderr'

    $invalid = Invoke-MoonTin @('check', 'examples/missing-point.xml', '--format', 'json') 1
    $invalidReport = $invalid.Stdout | ConvertFrom-Json
    Assert-Equal $invalidReport.diagnostics[0].code 'missing_point' 'Invalid sample rule'
    Assert-Equal $invalidReport.diagnostics[0].location.line 12 'Invalid sample line'
    Assert-Equal $invalidReport.diagnostics[0].point_ids[0] '99' 'Invalid sample point ID'
    Assert-Equal ([string]::IsNullOrWhiteSpace($invalid.Stderr)) $true 'Invalid sample stderr'

    $missing = Invoke-MoonTin @('check', "$emptyPath.missing") 2
    Assert-Equal ([string]::IsNullOrWhiteSpace($missing.Stdout)) $true 'Missing file stdout'
    Assert-Equal ($missing.Stderr -match 'moontin:') $true 'Missing file stderr'

    $empty = Invoke-MoonTin @('check', $emptyPath, '--format', 'json') 2
    Assert-Equal ([string]::IsNullOrWhiteSpace($empty.Stdout)) $true 'Empty file stdout'
    Assert-Equal ($empty.Stderr -match 'moontin:') $true 'Empty file stderr'

    $capped = Invoke-MoonTin @('check', 'examples/missing-point.xml', '--max-diagnostics', '0', '--format', 'json') 1
    $cappedReport = $capped.Stdout | ConvertFrom-Json
    Assert-Equal $cappedReport.error_count 1 'Truncated report full error count'
    Assert-Equal $cappedReport.truncated $true 'Truncated report flag'
    Assert-Equal $cappedReport.diagnostics.Count 0 'Truncated report output count'

    $same = Invoke-MoonTin @('diff', 'examples/terrain.xml', 'examples/terrain.xml', '--format', 'json') 0
    Assert-Equal ($same.Stdout | ConvertFrom-Json).changed $false 'Identical files'

    $diff = Invoke-MoonTin @('diff', 'examples/terrain.xml', 'examples/terrain-revised.xml', '--format', 'json') 1
    $diffReport = $diff.Stdout | ConvertFrom-Json
    Assert-Equal $diffReport.surfaces[0].moved_point_count 1 'Revised point count'
    Assert-Equal $diffReport.surfaces[0].moved_points[0].id '2' 'Revised point ID'

    $incompatible = Invoke-MoonTin @('diff', 'examples/terrain.xml', 'examples/missing-point.xml') 2
    Assert-Equal ($incompatible.Stderr -match 'missing point') $true 'Invalid comparison input'

    Write-Output 'MoonTIN CLI integration checks passed (8 cases).'
} finally {
    Remove-Item -LiteralPath $stderrPath, $emptyPath
    Pop-Location
}
