[CmdletBinding()]
param(
    [string]$ProfileDirectory = $env:CODEX_STREAM_DECK_PROFILE,
    [string]$BackupDirectory,
    [switch]$SkipProcessCheck,
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"
$productName = "Codex Control Page"
$pageName = "Codex Controls"
$streamDeckXlModel = "20GAT9901"
$root = Split-Path -Parent $PSScriptRoot
$profilesRoot = Join-Path $env:APPDATA "Elgato\StreamDeck\ProfilesV3"
$layoutPath = Join-Path $root "layout.json"
$buttonsRoot = Join-Path $root "buttons"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-JsonFile([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonFile([string]$Path, $Value) {
    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function New-BlankHotkey {
    return [ordered]@{
        KeyCmd = $false
        KeyCtrl = $false
        KeyModifiers = 0
        KeyOption = $false
        KeyShift = $false
        NativeCode = 146
        QTKeyCode = 33554431
        VKeyCode = -1
    }
}

function New-HotkeyAction($Item, [string]$Image) {
    $key = $Item.key
    $modifiers = 0
    if ([bool]$key.shift) { $modifiers += 1 }
    if ([bool]$key.ctrl) { $modifiers += 2 }
    if ([bool]$key.alt) { $modifiers += 4 }
    if ([bool]$key.cmd) { $modifiers += 8 }
    $primary = [ordered]@{
        KeyCmd = [bool]$key.cmd
        KeyCtrl = [bool]$key.ctrl
        KeyModifiers = $modifiers
        KeyOption = [bool]$key.alt
        KeyShift = [bool]$key.shift
        NativeCode = [int]$key.native
        QTKeyCode = [int]$key.qt
        VKeyCode = [int]$key.vkey
    }
    return [ordered]@{
        ActionID = [guid]::NewGuid().ToString()
        LinkedTitle = $true
        Name = ([string]$Item.label).Replace("`n", " ")
        Plugin = [ordered]@{ Name = "Activate a Key Command"; UUID = "com.elgato.streamdeck.system.hotkey"; Version = "1.0" }
        Resources = $null
        Settings = [ordered]@{ Coalesce = $true; Hotkeys = @($primary, (New-BlankHotkey), (New-BlankHotkey), (New-BlankHotkey)) }
        State = 0
        States = @([ordered]@{ Image = $Image })
        UUID = "com.elgato.streamdeck.system.hotkey"
    }
}

function New-TextAction($Item, [string]$Image) {
    return [ordered]@{
        ActionID = [guid]::NewGuid().ToString()
        LinkedTitle = $true
        Name = ([string]$Item.label).Replace("`n", " ")
        Plugin = [ordered]@{ Name = "Text"; UUID = "com.elgato.streamdeck.system.text"; Version = "1.0" }
        Resources = $null
        Settings = [ordered]@{
            Hotkey = [ordered]@{ KeyModifiers = 0; QTKeyCode = 33554431; VKeyCode = -1 }
            isSendingEnter = $true
            isTypingMode = $false
            pastedText = [string]$Item.text
        }
        State = 0
        States = @([ordered]@{ Image = $Image })
        UUID = "com.elgato.streamdeck.system.text"
    }
}

function New-PageAction($Item, [string]$Image) {
    $previous = [string]$Item.type -eq "page.previous"
    return [ordered]@{
        ActionID = [guid]::NewGuid().ToString()
        LinkedTitle = $true
        Name = $(if ($previous) { "Previous Page" } else { "Next Page" })
        Plugin = [ordered]@{ Name = "Pages"; UUID = "com.elgato.streamdeck.page"; Version = "1.0" }
        Resources = $null
        Settings = [ordered]@{}
        State = 0
        States = @([ordered]@{ Image = $Image })
        UUID = $(if ($previous) { "com.elgato.streamdeck.page.previous" } else { "com.elgato.streamdeck.page.next" })
    }
}

Write-Host "Installing $productName..." -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $profilesRoot)) {
    throw "Stream Deck profiles were not found. Install and open Elgato Stream Deck before running this installer."
}

$wasRunning = @(Get-Process -Name "StreamDeck" -ErrorAction SilentlyContinue).Count -gt 0
$streamDeckExecutable = $null
if ($wasRunning) {
    $candidateProcess = Get-Process -Name "StreamDeck" -ErrorAction SilentlyContinue | Select-Object -First 1
    try { $streamDeckExecutable = $candidateProcess.Path } catch {}
}

if ($wasRunning -and -not $SkipProcessCheck) {
    Write-Host ""
    Write-Host "Stream Deck must be closed so it does not overwrite the installed page." -ForegroundColor Yellow
    Write-Host "Close Stream Deck from the system tray, then press Enter here."
    [void](Read-Host)
    if (@(Get-Process -Name "StreamDeck" -ErrorAction SilentlyContinue).Count -gt 0) {
        throw "Stream Deck is still running. Close it completely and run the installer again."
    }
}

$profiles = @()
foreach ($directory in Get-ChildItem -LiteralPath $profilesRoot -Directory -Filter "*.sdProfile") {
    $manifestPath = Join-Path $directory.FullName "manifest.json"
    try {
        $manifest = Read-JsonFile $manifestPath
        if ([string]$manifest.Device.Model -eq $streamDeckXlModel) {
            $profiles += [pscustomobject]@{ Directory = $directory; Manifest = $manifest; ManifestPath = $manifestPath }
        }
    } catch {}
}

$selected = $null
if ($ProfileDirectory) {
    $selected = $profiles | Where-Object { $_.Directory.Name -eq $ProfileDirectory } | Select-Object -First 1
} else {
    $selected = $profiles | Where-Object { [string]$_.Manifest.Name -eq "Default Profile" } | Select-Object -First 1
    if (-not $selected -and $profiles.Count -eq 1) { $selected = $profiles[0] }
}

if (-not $selected) {
    $available = ($profiles | ForEach-Object { $_.Directory.Name }) -join ", "
    throw "A single Stream Deck XL profile could not be selected. Available XL profiles: $available. Set CODEX_STREAM_DECK_PROFILE to the intended .sdProfile directory name and run again."
}

$profileRoot = $selected.Directory.FullName
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupBase = if ($BackupDirectory) { $BackupDirectory } else { Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Codex Stream Deck Control Page Backups" }
$backupParent = Join-Path $backupBase $stamp
$backupRoot = Join-Path $backupParent $selected.Directory.Name
New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
Copy-Item -LiteralPath $profileRoot -Destination $backupRoot -Recurse
Write-Host "Backup created: $backupRoot" -ForegroundColor Green

$profileManifest = Read-JsonFile $selected.ManifestPath
$pageId = $null
foreach ($candidate in @($profileManifest.Pages.Pages)) {
    $candidateManifest = Join-Path $profileRoot "Profiles\$candidate\manifest.json"
    if (Test-Path -LiteralPath $candidateManifest) {
        try {
            $candidateData = Read-JsonFile $candidateManifest
            if ([string]$candidateData.Name -eq $pageName) { $pageId = [string]$candidate; break }
        } catch {}
    }
}

$isUpdate = [bool]$pageId
if (-not $pageId) { $pageId = [guid]::NewGuid().ToString() }
$pageRoot = Join-Path $profileRoot "Profiles\$pageId"
$imageRoot = Join-Path $pageRoot "Images"
New-Item -ItemType Directory -Path $imageRoot -Force | Out-Null

$layout = @(Read-JsonFile $layoutPath)
if ($layout.Count -ne 32) { throw "The bundled layout is incomplete. Expected 32 buttons but found $($layout.Count)." }
$actions = [ordered]@{}
foreach ($item in $layout) {
    $assetName = ([string]$item.position).Replace(",", "-") + ".png"
    $sourceImage = Join-Path $buttonsRoot $assetName
    if (-not (Test-Path -LiteralPath $sourceImage)) { throw "Missing button image: $assetName" }
    $installedName = "CODEX-$assetName"
    Copy-Item -LiteralPath $sourceImage -Destination (Join-Path $imageRoot $installedName) -Force
    $imageReference = "Images/$installedName"
    $action = switch ([string]$item.type) {
        "hotkey" { New-HotkeyAction $item $imageReference; break }
        "text" { New-TextAction $item $imageReference; break }
        "page.previous" { New-PageAction $item $imageReference; break }
        "page.next" { New-PageAction $item $imageReference; break }
        default { throw "Unsupported action type: $($item.type)" }
    }
    $actions.Add([string]$item.position, $action)
}

$pageManifest = [ordered]@{
    Controllers = @([ordered]@{ Actions = $actions; Type = "Keypad" })
    Icon = ""
    Name = $pageName
}
Write-JsonFile (Join-Path $pageRoot "manifest.json") $pageManifest

if (-not $isUpdate) {
    $profileManifest.Pages.Pages = @($profileManifest.Pages.Pages) + $pageId
}
$profileManifest.Pages.Current = $pageId
Write-JsonFile $selected.ManifestPath $profileManifest

$verifiedPage = Read-JsonFile (Join-Path $pageRoot "manifest.json")
$verifiedImages = @(Get-ChildItem -LiteralPath $imageRoot -File -Filter "CODEX-*.png")
$verifiedActions = @($verifiedPage.Controllers[0].Actions.psobject.Properties)
if ($verifiedActions.Count -ne 32 -or $verifiedImages.Count -ne 32) {
    throw "Installed page did not pass verification. Restore the backup at $backupRoot."
}

Write-Host ""
Write-Host $(if ($isUpdate) { "Updated the existing Codex Controls page." } else { "Added a new Codex Controls page." }) -ForegroundColor Green
Write-Host "Verified 32 actions and 32 button images."

if ($wasRunning -and -not $NoRestart) {
    if (-not $streamDeckExecutable) {
        $candidates = @(
            (Join-Path $env:ProgramFiles "Elgato\StreamDeck\StreamDeck.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "Elgato\StreamDeck\StreamDeck.exe")
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
        $streamDeckExecutable = $candidates | Select-Object -First 1
    }
    if ($streamDeckExecutable -and (Test-Path -LiteralPath $streamDeckExecutable)) {
        Start-Process -FilePath $streamDeckExecutable
        Write-Host "Stream Deck restarted."
    } else {
        Write-Host "Open Stream Deck to use the new page."
    }
}
