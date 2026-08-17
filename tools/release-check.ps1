[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versionFile = Join-Path $repoRoot '42/media/lua/shared/trpc/shared/Version.lua'
$changelogFile = Join-Path $repoRoot 'CHANGELOG.md'
$modFiles = @(
    (Join-Path $repoRoot 'mod.info'),
    (Join-Path $repoRoot '42/mod.info')
)

$errors = [System.Collections.Generic.List[string]]::new()
$semVerPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'

if ($ExpectedVersion -notmatch $semVerPattern) {
    $errors.Add("ExpectedVersion '$ExpectedVersion' is not valid SemVer MAJOR.MINOR.PATCH with optional prerelease/build metadata.")
}

if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    $errors.Add("Missing canonical runtime version file: $versionFile")
} else {
    $versionContent = Get-Content -LiteralPath $versionFile -Raw
    $returnMatch = [regex]::Match($versionContent, '(?m)^\s*return\s+["''](?<version>[^"'']*)["'']\s*$')
    $expectedRuntimeVersion = "v$ExpectedVersion"

    if (-not $returnMatch.Success) {
        $errors.Add("$versionFile must return a quoted string exactly equal to '$expectedRuntimeVersion'.")
    } elseif ($returnMatch.Groups['version'].Value -cne $expectedRuntimeVersion) {
        $actualRuntimeVersion = $returnMatch.Groups['version'].Value
        $errors.Add("$versionFile returns '$actualRuntimeVersion'; expected '$expectedRuntimeVersion'.")
    }
}

if (-not (Test-Path -LiteralPath $changelogFile -PathType Leaf)) {
    $errors.Add("Missing public changelog: $changelogFile")
} else {
    $changelogContent = Get-Content -LiteralPath $changelogFile -Raw
    $headingPattern = '(?m)^## \[' + [regex]::Escape($ExpectedVersion) + '\] - (\d{4}-\d{2}-\d{2})\s*$'

    if ($changelogContent -notmatch $headingPattern) {
        $errors.Add("$changelogFile is missing a heading matching '## [$ExpectedVersion] - <ISO date>'.")
    }
}

foreach ($modFile in $modFiles) {
    if (-not (Test-Path -LiteralPath $modFile -PathType Leaf)) {
        $errors.Add("Missing compatibility metadata file: $modFile")
        continue
    }

    $modContent = Get-Content -LiteralPath $modFile -Raw
    if ($modContent -notmatch '(?m)^versionMin=') {
        $errors.Add("$modFile must contain a versionMin= compatibility constraint.")
    }
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) {
        Write-Error -Message $errorMessage -ErrorAction Continue
    }
    exit 1
}

Write-Output "Release checks passed for version $ExpectedVersion."
Write-Output 'Checked files:'
Write-Output "- $versionFile"
Write-Output "- $changelogFile"
foreach ($modFile in $modFiles) {
    Write-Output "- $modFile"
}
exit 0
