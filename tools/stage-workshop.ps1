<#
.SYNOPSIS
    Stages a clean TotalRPChat Workshop package from the repository contents.

.DESCRIPTION
    Creates a staging folder ready for the Steam Workshop upload workflow.
    It copies the B42 implementation (42/), the shared media (common/), the
    workshop descriptor (workshop.txt), and the public docs, excluding
    development artifacts such as .git, local saves, logs, editor files, and
    temporary directories.

.PARAMETER Destination
    Output folder for the staged package. Defaults to dist/workshop under the
    repository root.

.PARAMETER PreviewImage
    Optional preview image (e.g. preview.png) to copy into the staged package
    root for the Workshop item.

.EXAMPLE
    pwsh -File tools/stage-workshop.ps1

.EXAMPLE
    pwsh -File tools/stage-workshop.ps1 -Destination dist/workshop -PreviewImage docs/preview.png
#>
[CmdletBinding()]
param(
    [string]$Destination,
    [string]$PreviewImage
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Destination) {
    $Destination = Join-Path $repoRoot 'dist/workshop'
}
$dest = (Resolve-Path (Join-Path $repoRoot $Destination) -ErrorAction SilentlyContinue) ?? (New-Item -ItemType Directory -Path (Join-Path $repoRoot $Destination) -Force)

$required = @(
    (Join-Path $repoRoot '42/mod.info'),
    (Join-Path $repoRoot '42/media/lua/shared/trpc/shared/Version.lua'),
    (Join-Path $repoRoot 'workshop.txt')
)
$missing = $required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($missing) {
    foreach ($m in $missing) {
        Write-Error -Message "Missing required file: $m" -ErrorAction Continue
    }
    exit 1
}

# Reset the staging folder to guarantee a clean package.
if (Test-Path -LiteralPath $dest) {
    Remove-Item -LiteralPath $dest -Recurse -Force
}
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# Copy the game content (B42 descriptor + implementation, shared media).
Copy-Item -LiteralPath (Join-Path $repoRoot '42') -Destination $dest -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'common') -Destination $dest -Recurse -Force

# Copy the workshop descriptor and public docs.
Copy-Item -LiteralPath (Join-Path $repoRoot 'workshop.txt') -Destination $dest -Force
if (Test-Path -LiteralPath (Join-Path $repoRoot 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination $dest -Force
}
if (Test-Path -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Destination $dest -Force
}

# Optional preview image for the Workshop item.
if ($PreviewImage) {
    $preview = Join-Path $repoRoot $PreviewImage
    if (-not (Test-Path -LiteralPath $preview -PathType Leaf)) {
        Write-Error -Message "Preview image not found: $preview"
        exit 1
    }
    Copy-Item -LiteralPath $preview -Destination $dest -Force
}

# Verify the staged package layout.
$stagedRequired = @(
    (Join-Path $dest '42/mod.info'),
    (Join-Path $dest '42/media/lua/shared/trpc/shared/Version.lua'),
    (Join-Path $dest 'common/media/ui/trpc/bubble/radio/bubble-center.png'),
    (Join-Path $dest 'workshop.txt')
)
$stagedMissing = $stagedRequired | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($stagedMissing) {
    foreach ($m in $stagedMissing) {
        Write-Error -Message "Staged package is missing: $m" -ErrorAction Continue
    }
    exit 1
}

# Reject stray development artifacts inside the staged package.
$forbidden = Get-ChildItem -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\(\.git|sdd|\.vscode|\.atl|\.codegraph)(\\|$)' -or $_.Name -in @('console.txt', 'server-console.txt') }
if ($forbidden) {
    foreach ($f in $forbidden) {
        Write-Error -Message "Staged package contains a forbidden artifact: $($f.FullName)" -ErrorAction Continue
    }
    exit 1
}

$fileCount = (Get-ChildItem -LiteralPath $dest -Recurse -File).Count
Write-Output "Workshop package staged at: $dest"
Write-Output "Files: $fileCount"
Write-Output "Layout:"
Write-Output "  - 42/mod.info (B42 descriptor)"
Write-Output "  - 42/media/... (implementation)"
Write-Output "  - common/media/... (shared assets)"
Write-Output "  - workshop.txt (Workshop descriptor)"
if ($PreviewImage) {
    Write-Output "  - $(Split-Path $PreviewImage -Leaf) (preview image)"
}
Write-Output "Next: upload this folder through the established Steam Workshop workflow (title, description, and release notes are prepared in docs/workshop-publication.md)."