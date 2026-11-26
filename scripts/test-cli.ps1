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
    $nativeOutput = '_build/native/debug/build/cmd/main'
    $cliPath = @('main.exe', 'main') |
        ForEach-Object { Join-Path $nativeOutput $_ } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (!$cliPath) { throw "MoonTin native executable was not built in $nativeOutput." }
    $cliPath = (Resolve-Path -LiteralPath $cliPath).Path

    $valid = Invoke-MoonTin @('check', 'examples/terrain.xml', '--format', 'json') 0
    $validReport = $valid.Stdout | ConvertFrom-Json
    Assert-Equal $validReport.status 'passed' 'Valid sample status'
    Assert-Equal $validReport.surfaces[0].boundary_edges 3 'Valid sample edge count'
    Assert-Equal $validReport.surfaces[0].geometry.projected_area 0.5 'Valid sample projected area'
    Assert-Equal $validReport.surfaces[0].geometry.measured_faces 1 'Valid sample measured face count'
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

    $sample = Invoke-MoonTin @('sample', 'examples/terrain.xml', '100.25', '200.25', '--format', 'json') 0
    $sampleReport = $sample.Stdout | ConvertFrom-Json
    Assert-Equal $sampleReport.hits[0].elevation 10.75 'Interpolated elevation'

    $outside = Invoke-MoonTin @('sample', 'examples/terrain.xml', '0', '0', '--format', 'json') 1
    Assert-Equal ($outside.Stdout | ConvertFrom-Json).hits.Count 0 'Out-of-coverage sample'

    $unknownSurface = Invoke-MoonTin @('sample', 'examples/terrain.xml', '100', '200', '--surface', 'unknown') 2
    Assert-Equal ($unknownSurface.Stderr -match 'was not found') $true 'Missing sample surface'

    $profile = Invoke-MoonTin @('profile', 'examples/terrain.xml', '100.25', '199.75', '100.25', '201.25', '--format', 'json') 0
    $profileReport = $profile.Stdout | ConvertFrom-Json
    Assert-Equal $profileReport.length 1.5 'Profile length'
    Assert-Equal $profileReport.segments[0].start_distance 0.25 'Profile entry distance'
    Assert-Equal $profileReport.segments[0].end_elevation 11.25 'Profile exit elevation'
    Assert-Equal $profileReport.gaps.Count 2 'Profile coverage gaps'

    $noCoverage = Invoke-MoonTin @('profile', 'examples/terrain.xml', '0', '0', '0', '1', '--format', 'json') 1
    Assert-Equal ($noCoverage.Stdout | ConvertFrom-Json).gaps[0].end_distance 1 'Fully uncovered profile'

    $obj = Invoke-MoonTin @('export', 'examples/terrain.xml', '--local-origin') 0
    Assert-Equal ($obj.Stdout -match '(?m)^# origin 200 100 10$') $true 'OBJ origin'
    Assert-Equal ($obj.Stdout -match '(?m)^v 0 0 0$') $true 'OBJ local coordinate'
    Assert-Equal ($obj.Stdout -match '(?m)^f 1 2 3$') $true 'OBJ one-based face'

    $ply = Invoke-MoonTin @('export', 'examples/terrain.xml', '--format', 'ply') 0
    Assert-Equal ($ply.Stdout -match '(?m)^element vertex 3$') $true 'PLY vertex count'
    Assert-Equal ($ply.Stdout -match '(?m)^3 0 1 2 1 1$') $true 'PLY face mapping'

    $badMesh = Invoke-MoonTin @('export', 'examples/missing-point.xml') 2
    Assert-Equal ([string]::IsNullOrWhiteSpace($badMesh.Stdout)) $true 'Invalid mesh stdout'

    $survey = Invoke-MoonTin @('survey', 'examples/terrain.xml', 'examples/survey-points.json', '0.1', '--format', 'json') 1
    $surveyReport = $survey.Stdout | ConvertFrom-Json
    Assert-Equal $surveyReport.passed_count 1 'Survey accepted count'
    Assert-Equal $surveyReport.outside_tolerance_count 1 'Survey failed count'
    Assert-Equal $surveyReport.uncovered_count 1 'Survey uncovered count'
    Assert-Equal $surveyReport.results[1].max_absolute_error 0.25 'Survey maximum error'

    $badSurvey = Invoke-MoonTin @('survey', 'examples/terrain.xml', 'examples/terrain.xml', '0.1') 2
    Assert-Equal ($badSurvey.Stderr -match 'invalid survey points JSON') $true 'Malformed survey file'

    $contour = Invoke-MoonTin @('contour', 'examples/terrain.xml', '10.5', '--level', '99', '--format', 'json') 0
    $contourReport = $contour.Stdout | ConvertFrom-Json
    Assert-Equal $contourReport.paths.Count 1 'Contour path count'
    Assert-Equal $contourReport.paths[0].elevation 10.5 'Contour elevation'
    Assert-Equal $contourReport.paths[0].points.Count 2 'Contour endpoint count'

    $volume = Invoke-MoonTin @('volume', 'examples/terrain.xml', '11', '--format', 'json') 0
    $volumeReport = $volume.Stdout | ConvertFrom-Json
    Assert-Equal $volumeReport.surfaces[0].crossing_faces 1 'Volume crossing triangle'
    Assert-Equal ([Math]::Round($volumeReport.cut, 10)) ([Math]::Round(1.0 / 12.0, 10)) 'Integrated cut'
    Assert-Equal $volumeReport.fill $volumeReport.cut 'Symmetric fill'

    $plane = Invoke-MoonTin @('volume', 'examples/terrain.xml', '10', '--anchor', '100', '200', '--grade', '2', '1', '--format', 'json') 0
    Assert-Equal ($plane.Stdout | ConvertFrom-Json).surfaces[0].coincident_faces 1 'Sloped reference coincident face'

    $rewritten = Invoke-MoonTin @('rewrite', 'examples/terrain.xml', '--timestamp', '2024-02-29', '10:20:30', '--project', 'Road & Drainage') 0
    [xml]$rewrittenDocument = $rewritten.Stdout
    Assert-Equal $rewrittenDocument.LandXML.date '2024-02-29' 'LandXML export date'
    Assert-Equal $rewrittenDocument.LandXML.Project.name 'Road & Drainage' 'Escaped project'
    Set-Content -LiteralPath $emptyPath -Value $rewritten.Stdout -Encoding utf8
    $roundTrip = Invoke-MoonTin @('diff', 'examples/terrain.xml', $emptyPath, '--format', 'json') 0
    Assert-Equal ($roundTrip.Stdout | ConvertFrom-Json).changed $false 'Rewritten TIN round trip'

    $badDate = Invoke-MoonTin @('rewrite', 'examples/terrain.xml', '--timestamp', '2025-02-29', '10:20:30') 2
    Assert-Equal ($badDate.Stderr -match 'timestamp requires') $true 'Invalid LandXML date'

    $grid = Invoke-MoonTin @('grid', 'examples/terrain.xml', '100', '200', '2', '2', '0.75', '0.75', '--format', 'json') 0
    $gridReport = $grid.Stdout | ConvertFrom-Json
    Assert-Equal $gridReport.covered_cells 3 'Grid covered nodes'
    Assert-Equal $gridReport.uncovered_cells 1 'Grid uncovered nodes'
    Assert-Equal $gridReport.cells[2].max_elevation 11.5 'Grid indexed elevation'
    Assert-Equal ($null -eq $gridReport.cells[3].min_elevation) $true 'Grid no-data elevation'

    $invalidGrid = Invoke-MoonTin @('grid', 'examples/terrain.xml', '100', '200', '1001', '100', '1', '1') 2
    Assert-Equal ($invalidGrid.Stderr -match '100000 nodes') $true 'Grid node limit'

    $gridDiffArgs = @('grid-diff', 'examples/terrain.xml', 'examples/terrain-revised.xml', '100', '200', '2', '2', '0.75', '0.75')
    $delta = Invoke-MoonTin ($gridDiffArgs + @('0.1', '--format', 'json')) 1
    $deltaReport = $delta.Stdout | ConvertFrom-Json
    Assert-Equal $deltaReport.counts.raised 1 'Grid comparison raised count'
    Assert-Equal $deltaReport.counts.within_tolerance 2 'Grid comparison tolerance count'
    Assert-Equal $deltaReport.counts.no_coverage 1 'Grid comparison missing in both revisions'
    Assert-Equal $deltaReport.cells[1].min_delta 0.1875 'Grid comparison elevation change'

    $tolerantDelta = Invoke-MoonTin ($gridDiffArgs + @('0.2', '--format', 'json')) 0
    Assert-Equal ($tolerantDelta.Stdout | ConvertFrom-Json).needs_review $false 'Grid comparison within tolerance'

    $summaryDelta = Invoke-MoonTin ($gridDiffArgs + @('0.1')) 1
    Assert-Equal ($summaryDelta.Stdout -match '1 raised, 0 lowered, 2 within tolerance, 0 ambiguous') $true 'Grid text summary counts'
    Assert-Equal ($summaryDelta.Stdout -match '0 added, 0 lost, 1 uncovered in both revisions') $true 'Grid text coverage counts'

    Write-Output 'MoonTIN CLI integration checks passed (29 cases).'
} finally {
    Remove-Item -LiteralPath $stderrPath, $emptyPath
    Pop-Location
}
