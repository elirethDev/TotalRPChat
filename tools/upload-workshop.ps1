<#
.SYNOPSIS
    Uploads the staged TotalRPChat Workshop package to Steam Workshop via SteamCMD.

.DESCRIPTION
    Generates the SteamCMD workshopitem VDF from the staged package and runs
    the upload. The VDF is written to the repository temp/scratch area (never
    into the staged package) and removed after the upload.

    Before running:
      - SteamCMD must be installed (default: C:\Program Files (x86)\SteamCMD\steamcmd.exe)
      - You must be able to log in to Steam from SteamCMD (Steam Guard may prompt)
      - The staged package must exist (run tools/stage-workshop.ps1 first)

.PARAMETER Package
    Staged Workshop package folder. Defaults to dist/workshop under the repo root.

.PARAMETER SteamCmdPath
    Path to steamcmd.exe. Defaults to C:\Program Files (x86)\SteamCMD\steamcmd.exe.

.PARAMETER SteamUser
    Steam account name. If omitted, steamcmd will prompt.

.PARAMETER PublishedFileId
    Existing Workshop item ID for updates. Defaults to 0 (creates a new item).
    After the first upload SteamCMD reports the new ID; update this value for
    future updates.

.PARAMETER Visibility
    Workshop visibility: 0=public, 1=friends only, 2=private. Defaults to 0.

.PARAMETER Title
    Workshop item title. Defaults to TotalRPChat.

.PARAMETER Description
    Workshop item description. Defaults to the description line from workshop.txt.

.PARAMETER KeepVdf
    Keeps the generated VDF file instead of deleting it after the upload.

.EXAMPLE
    pwsh -File tools/upload-workshop.ps1

.EXAMPLE
    pwsh -File tools/upload-workshop.ps1 -PublishedFileId 1234567890 -Visibility 0
#>
[CmdletBinding()]
param(
    [string]$Package,
    [string]$SteamCmdPath = 'C:\Program Files (x86)\SteamCMD\steamcmd.exe',
    [string]$SteamUser,
    [string]$PublishedFileId = '0',
    [int]$Visibility = 0,
    [string]$Title = 'TotalRPChat',
    [string]$Description,
    [switch]$KeepVdf
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Package) {
    $Package = Join-Path $repoRoot 'dist/workshop'
}
$package = (Resolve-Path -LiteralPath $Package -ErrorAction SilentlyContinue)
if (-not $package) {
    Write-Error "Staged package not found: $Package. Run tools/stage-workshop.ps1 first."
    exit 1
}

# Validate required package files.
$workshopTxt = Join-Path $package 'workshop.txt'
$previewFile = Join-Path $package 'preview.png'
if (-not (Test-Path -LiteralPath $workshopTxt -PathType Leaf)) {
    Write-Error "Missing $workshopTxt in the staged package."
    exit 1
}
if (-not (Test-Path -LiteralPath $previewFile -PathType Leaf)) {
    Write-Error "Missing $previewFile in the staged package."
    exit 1
}

if (-not (Test-Path -LiteralPath $SteamCmdPath -PathType Leaf)) {
    Write-Error "SteamCMD not found at: $SteamCmdPath. Install it or pass -SteamCmdPath."
    exit 1
}

# Derive the description from workshop.txt when not overridden.
if (-not $Description) {
    $match = Select-String -LiteralPath $workshopTxt -Pattern '^description=(.*)$' | Select-Object -First 1
    if ($match) {
        $Description = $match.Matches[0].Groups[1].Value
    } else {
        $Description = 'A full rework of the chat and radio systems for Project Zomboid, built with roleplay servers in mind.'
    }
}

# Write the VDF outside the package so the staged content stays clean.
$scratch = Join-Path $repoRoot '.workshop-upload'
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$vdfPath = Join-Path $scratch 'workshop.vdf'
$vdf = @(
    '"workshopitem"'
    '{'
    "`t`"appid`" `"108600`""
    "`t`"publishedfileid`" `"$PublishedFileId`""
    "`t`"contentfolder`" `"$package`""
    "`t`"previewfile`" `"$previewFile`""
    "`t`"visibility`" `"$Visibility`""
    "`t`"title`" `"$Title`""
    "`t`"description`" `"$Description`""
    '}'
) -join [Environment]::NewLine
Set-Content -LiteralPath $vdfPath -Value $vdf -Encoding utf8

Write-Output '=== SteamCMD upload ==='
Write-Output "VDF:      $vdfPath"
Write-Output "Package:  $package"
Write-Output "Preview:  $previewFile"
Write-Output "Item ID:  $PublishedFileId"
Write-Output "Title:    $Title"

$loginArgs = @('+login')
if ($SteamUser) {
    $loginArgs += $SteamUser
}
$loginArgs += @(
    '+workshop_build_item', $vdfPath,
    '+quit'
)

# Run steamcmd. It may prompt for the password and Steam Guard code.
& $SteamCmdPath @loginArgs
$exitCode = $LASTEXITCODE

# Keep the VDF on failure so the user can retry without regenerating it.
if ($exitCode -eq 0 -and -not $KeepVdf) {
    Remove-Item -LiteralPath $vdfPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue
}

if ($exitCode -ne 0) {
    Write-Error "SteamCMD exited with code $exitCode. Check the output above."
    Write-Output "The generated VDF was kept at: $vdfPath"
    Write-Output 'Retry by running this script again, or upload the VDF directly with:'
    Write-Output "  & `"$SteamCmdPath`" +login <user> +workshop_build_item `"$vdfPath`" +quit"
    exit $exitCode
}

Write-Output 'Upload finished. If this was a new item, note the publishedfileid printed by SteamCMD and update tools/upload-workshop.ps1 (-PublishedFileId) and workshop.txt (id=) for future updates.'
exit 0