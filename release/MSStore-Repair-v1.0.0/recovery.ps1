[CmdletBinding()]
param(
    [ValidateSet('Soft', 'Default', 'Hard')]
    [string]$Mode,

    [switch]$DryRun,
    [switch]$SkipPrompt,
    [switch]$NoStoreLaunch,
    [switch]$SelfTest,
    [string]$LogPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'MicrosoftStoreRecovery.log')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$script:Version = '1.0.0'
$script:AppName = 'MSStore Repair'
$script:Log = $LogPath
$script:LogAvailable = $true
$script:LogWarningShown = $false
$script:FailedSteps = 0
$script:Warnings = 0
$script:StepNumber = 0
$script:PackageNames = @(
    'Microsoft.WindowsStore',
    'Microsoft.StorePurchaseApp',
    'Microsoft.DesktopAppInstaller',
    'Microsoft.Services.Store.Engagement'
)

function Write-Ui {
    param(
        [string]$Text = '',
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$NoNewline
    )

    $current = [Console]::ForegroundColor
    [Console]::ForegroundColor = $Color
    if ($NoNewline) {
        Write-Host $Text -NoNewline
    } else {
        Write-Host $Text
    }
    [Console]::ForegroundColor = $current
}

function Write-RepairLog {
    param([string]$Message)

    if (-not $script:LogAvailable) {
        return
    }

    try {
        Add-Content -LiteralPath $script:Log -Value $Message -ErrorAction Stop
    } catch {
        $script:LogAvailable = $false
        if (-not $script:LogWarningShown) {
            Write-Ui ('   WARN  Logging disabled: {0}' -f $_.Exception.Message) Yellow
            $script:LogWarningShown = $true
        }
    }
}

function Write-Rule {
    param([ConsoleColor]$Color = [ConsoleColor]::DarkCyan)
    Write-Ui ('=' * 78) $Color
}

function Show-Banner {
    Clear-Host
    Write-Ui ''
    Write-Rule Cyan
    Write-Ui '   MSSTORE REPAIR' Cyan
    Write-Ui ('   Version {0} | PowerShell Recovery Console | Made by Mizae' -f $script:Version) DarkGray
    Write-Rule Cyan
    Write-Ui ''
}

function Show-StatusLine {
    param(
        [string]$Label,
        [string]$Value,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Ui ('   {0,-18}: ' -f $Label) DarkGray -NoNewline
    Write-Ui $Value $Color
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-Log {
    $line = '=' * 78

    try {
        Set-Content -LiteralPath $script:Log -Value $line -ErrorAction Stop
    } catch {
        $fallback = Join-Path $PSScriptRoot 'MicrosoftStoreRecovery.log'
        $script:Log = $fallback
        try {
            Set-Content -LiteralPath $script:Log -Value $line -ErrorAction Stop
            Write-Ui ('   WARN  Desktop log was not writable. Using {0}' -f $script:Log) Yellow
        } catch {
            $script:LogAvailable = $false
            Write-Ui ('   WARN  Logging disabled: {0}' -f $_.Exception.Message) Yellow
            return
        }
    }

    Write-RepairLog $script:AppName
    Write-RepairLog ('Version: {0}' -f $script:Version)
    Write-RepairLog ('Mode: {0}' -f $Mode)
    Write-RepairLog ('Dry run: {0}' -f [bool]$DryRun)
    Write-RepairLog ('Started: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-RepairLog ('Log file: {0}' -f $script:Log)
    Write-RepairLog $line
}

function Select-RecoveryMode {
    while ($true) {
        Show-Banner
        Write-Ui '   Select a recovery mode' White
        Write-Ui ''
        Write-Ui '   [1] SOFT     Cache reset, core services, Store package repair' Green
        Write-Ui '   [2] DEFAULT  Soft plus BITS, Delivery Optimization, App Installer flow' Cyan
        Write-Ui '   [3] HARD     Default plus Windows Update backend, network, DISM, SFC' Yellow
        Write-Ui '   [4] Toggle dry-run preview' Magenta
        Write-Ui '   [5] Exit' DarkGray
        Write-Ui ''
        Show-StatusLine 'Dry-run preview' ($(if ($DryRun) { 'ON' } else { 'OFF' })) ($(if ($DryRun) { 'Magenta' } else { 'DarkGray' }))
        Write-Ui ''

        $choice = Read-Host '   Choose [1/2/3/4/5]'
        switch ($choice) {
            '1' { return 'Soft' }
            '2' { return 'Default' }
            '3' { return 'Hard' }
            '4' { $script:DryRun = -not $script:DryRun }
            '5' { exit 0 }
        }
    }
}

function Confirm-Start {
    if ($SkipPrompt) {
        return $true
    }

    Show-Banner
    Show-StatusLine 'Selected mode' $Mode Cyan
    Show-StatusLine 'Dry-run preview' ($(if ($DryRun) { 'ON - no repair actions will be executed' } else { 'OFF - repair actions will change Windows settings' })) ($(if ($DryRun) { 'Magenta' } else { 'Yellow' }))
    Show-StatusLine 'Log file' $script:Log Gray
    Write-Ui ''
    Write-Ui '   Close Microsoft Store before continuing. Hard mode can take a long time.' DarkGray
    Write-Ui '   This tool is provided as-is and should be run only from a trusted copy.' DarkGray
    Write-Ui ''

    $answer = Read-Host '   Continue? [Y/N]'
    return $answer -match '^(y|yes)$'
}

function Get-ModeLevel {
    param([string]$Name)
    switch ($Name) {
        'Soft' { 1 }
        'Default' { 2 }
        'Hard' { 3 }
        default { 2 }
    }
}

function Test-ModeAtLeast {
    param([string]$Required)
    return (Get-ModeLevel $Mode) -ge (Get-ModeLevel $Required)
}

function Invoke-Step {
    param(
        [string]$Title,
        [scriptblock]$Action,
        [string]$MinimumMode = 'Soft',
        [switch]$AlwaysRunInDryRun
    )

    if (-not (Test-ModeAtLeast $MinimumMode)) {
        return
    }

    $script:StepNumber++
    Write-Ui ''
    Write-Rule DarkCyan
    Write-Ui ('   [{0:00}] {1}' -f $script:StepNumber, $Title.ToUpperInvariant()) Cyan
    Write-Rule DarkCyan
    Write-RepairLog ''
    Write-RepairLog ('[{0:00}] {1}' -f $script:StepNumber, $Title)
    Write-RepairLog ('-' * 78)

    try {
        $global:LASTEXITCODE = 0
        & $Action
        $code = if (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) { $global:LASTEXITCODE } else { 0 }
        if ($code -ne 0) {
            $script:Warnings++
            Write-Ui ('   WARN  Exit code {0}. Check the log for details.' -f $code) Yellow
            Write-RepairLog ('Warning: exit code {0}' -f $code)
        } else {
            Write-Ui '   OK    Step completed.' Green
        }
    } catch {
        $script:FailedSteps++
        Write-Ui ('   FAIL  {0}' -f $_.Exception.Message) Red
        Write-RepairLog ('Failure: {0}' -f $_.Exception.Message)
    }
}

function Invoke-RepairAction {
    param(
        [string]$Description,
        [scriptblock]$Action
    )

    if ($DryRun) {
        Write-Ui ('   DRY   {0}' -f $Description) Magenta
        Write-RepairLog ('DRY RUN: {0}' -f $Description)
        return
    }

    Write-Ui ('   RUN   {0}' -f $Description) Gray
    Write-RepairLog ('RUN: {0}' -f $Description)
    & $Action
}

function Invoke-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$Description = $FilePath,
        [switch]$TrackProgress
    )

    if ($DryRun) {
        Write-Ui ('   DRY   {0} {1}' -f $FilePath, ($Arguments -join ' ')) Magenta
        Write-RepairLog ('DRY RUN: {0} {1}' -f $FilePath, ($Arguments -join ' '))
        $global:LASTEXITCODE = 0
        return 0
    }

    Write-Ui ('   RUN   {0}' -f $Description) Gray
    Write-RepairLog ('Running: {0} {1}' -f $FilePath, ($Arguments -join ' '))

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
    }) -join ' '
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $buffer = New-Object System.Text.StringBuilder
    $lastPercent = 0

    if ($TrackProgress) {
        Show-ProgressLine $Description 0
    }

    while (-not $process.HasExited -or $process.StandardOutput.Peek() -ge 0 -or $process.StandardError.Peek() -ge 0) {
        while ($process.StandardOutput.Peek() -ge 0) {
            $char = [char]$process.StandardOutput.Read()
            if ($char -eq "`r" -or $char -eq "`n") {
                $line = $buffer.ToString()
                if ($line.Trim().Length -gt 0) {
                    Write-RepairLog $line
                    if ($TrackProgress -and $line -match '(\d+(?:\.\d+)?)\s*%') {
                        $lastPercent = [int][Math]::Round([double]$matches[1])
                        Show-ProgressLine $Description $lastPercent
                    }
                }
                [void]$buffer.Clear()
            } else {
                [void]$buffer.Append($char)
                $current = $buffer.ToString()
                if ($TrackProgress -and $current -match '(\d+(?:\.\d+)?)\s*%') {
                    $lastPercent = [int][Math]::Round([double]$matches[1])
                    Show-ProgressLine $Description $lastPercent
                }
            }
        }

        while ($process.StandardError.Peek() -ge 0) {
            $errorLine = $process.StandardError.ReadLine()
            if ($null -ne $errorLine -and $errorLine.Trim().Length -gt 0) {
                Write-RepairLog $errorLine
            }
        }

        Start-Sleep -Milliseconds 120
    }

    $process.WaitForExit()
    $remaining = $buffer.ToString()
    if ($remaining.Trim().Length -gt 0) {
        Write-RepairLog $remaining
    }

    if ($TrackProgress) {
        if ($process.ExitCode -eq 0) { Show-ProgressLine $Description 100 } else { Show-ProgressLine $Description $lastPercent }
        Write-Host ''
    }

    Write-RepairLog ('Exit code: {0}' -f $process.ExitCode)
    $global:LASTEXITCODE = $process.ExitCode
    return $process.ExitCode
}

function Show-ProgressLine {
    param(
        [string]$Label,
        [int]$Percent
    )

    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    $width = 34
    $done = [Math]::Floor($Percent * $width / 100)
    $left = $width - $done
    $bar = ('#' * $done) + ('-' * $left)
    [Console]::Write(("`r   PROG  {0,-22} [{1}] {2,3}%" -f $Label, $bar, $Percent))
}

function Set-ServiceStartup {
    param(
        [string]$Name,
        [string]$StartMode
    )

    Invoke-RepairAction "Set service $Name startup to $StartMode" {
        & sc.exe config $Name start= $StartMode >> $script:Log 2>&1
    }
}

function Start-RepairService {
    param([string]$Name)

    Invoke-RepairAction "Start service $Name" {
        & net.exe start $Name >> $script:Log 2>&1
    }
}

function Stop-RepairService {
    param([string]$Name)

    Invoke-RepairAction "Stop service $Name" {
        & net.exe stop $Name >> $script:Log 2>&1
    }
}

function Remove-RepairPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Ui ('   SKIP  Not found: {0}' -f $Path) DarkGray
        Write-RepairLog ('SKIP missing path: {0}' -f $Path)
        return
    }

    Invoke-RepairAction "Remove $Path" {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
}

function Remove-RepairItems {
    param([string]$Pattern)

    $items = @(Get-ChildItem -Path $Pattern -Force -ErrorAction SilentlyContinue)
    if ($items.Count -eq 0) {
        Write-Ui ('   SKIP  No matches: {0}' -f $Pattern) DarkGray
        Write-RepairLog ('SKIP no matches: {0}' -f $Pattern)
        return
    }

    foreach ($item in $items) {
        Remove-RepairPath $item.FullName
    }
}

function Get-StorePackagePlan {
    $plan = foreach ($name in $script:PackageNames) {
        $packages = @()
        $accessNote = ''

        try {
            $packages = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop)
        } catch {
            $accessNote = 'AllUsers check unavailable; checking current user'
            Write-RepairLog ('Package check fallback for {0}: {1}' -f $name, $_.Exception.Message)
            try {
                $packages = @(Get-AppxPackage -Name $name -ErrorAction Stop)
            } catch {
                $packages = @()
            }
        }

        if ($packages.Count -eq 0) {
            [pscustomobject]@{
                Name = $name
                PackageFound = $false
                ManifestFound = $false
                Manifest = ''
                Status = if ($accessNote) { "Package missing ($accessNote)" } else { 'Package missing' }
            }
            continue
        }

        foreach ($package in $packages) {
            $manifest = if ([string]::IsNullOrWhiteSpace($package.InstallLocation)) { '' } else { Join-Path $package.InstallLocation 'AppXManifest.xml' }
            $manifestFound = -not [string]::IsNullOrWhiteSpace($manifest) -and (Test-Path -LiteralPath $manifest)
            [pscustomobject]@{
                Name = $name
                PackageFound = $true
                ManifestFound = $manifestFound
                Manifest = $manifest
                Status = if ($manifestFound -and $accessNote) { "Ready ($accessNote)" } elseif ($manifestFound) { 'Ready' } else { 'Manifest missing' }
            }
        }
    }

    return @($plan)
}

function Show-PackagePlan {
    param([object[]]$Plan)

    Write-Ui ''
    Write-Ui '   Package preflight' White
    foreach ($item in $Plan) {
        $color = if ($item.ManifestFound) { [ConsoleColor]::Green } elseif ($item.PackageFound) { [ConsoleColor]::Yellow } else { [ConsoleColor]::DarkYellow }
        Write-Ui ('   {0,-42} {1}' -f $item.Name, $item.Status) $color
        Write-RepairLog ('Package check: {0} - {1} - {2}' -f $item.Name, $item.Status, $item.Manifest)
    }
}

function Repair-StorePackages {
    $plan = Get-StorePackagePlan
    Show-PackagePlan $plan

    foreach ($item in $plan) {
        if (-not $item.ManifestFound) {
            $script:Warnings++
            Write-Ui ('   SKIP  {0}: {1}' -f $item.Name, $item.Status) Yellow
            continue
        }

        Invoke-RepairAction "Re-register $($item.Name)" {
            Add-AppxPackage -DisableDevelopmentMode -Register $item.Manifest -ErrorAction Stop
        }
    }
}

function New-RepairRestorePoint {
    Invoke-RepairAction 'Create restore point' {
        try {
            Checkpoint-Computer -Description 'MSStore Repair' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            Write-RepairLog 'Restore point created.'
        } catch {
            $script:Warnings++
            Write-Ui ('   WARN  Restore point skipped: {0}' -f $_.Exception.Message) Yellow
            Write-RepairLog ('Restore point skipped: {0}' -f $_.Exception.Message)
        }
    }
}

function Test-RecoverySelf {
    Show-Banner
    Write-Ui '   Self-test passed: recovery.ps1 loaded successfully.' Green
    Write-Ui ('   PowerShell: {0}' -f $PSVersionTable.PSVersion) Gray
    Write-Ui ('   Script: {0}' -f $PSCommandPath) Gray
}

if ($SelfTest) {
    Test-RecoverySelf
    exit 0
}

if (-not $Mode) {
    $Mode = Select-RecoveryMode
}

if (-not $DryRun -and -not (Test-Administrator)) {
    Show-Banner
    Write-Ui '   Administrator required' Red
    Write-Ui ''
    Write-Ui '   Right-click Windows PowerShell and choose Run as administrator, then run:' Gray
    Write-Ui ('   powershell -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath) White
    Write-Ui ''
    Read-Host '   Press Enter to exit'
    exit 1
}

if (-not (Confirm-Start)) {
    Write-Ui 'Cancelled.' Yellow
    exit 0
}

Initialize-Log
Show-Banner
Show-StatusLine 'Selected mode' $Mode Cyan
Show-StatusLine 'Dry-run preview' ($(if ($DryRun) { 'ON' } else { 'OFF' })) ($(if ($DryRun) { 'Magenta' } else { 'Yellow' }))
Show-StatusLine 'Log file' $script:Log Gray

Invoke-Step 'Preflight checks and restore point' {
    $plan = Get-StorePackagePlan
    Show-PackagePlan $plan
    New-RepairRestorePoint
}

Invoke-Step 'Closing Microsoft Store processes' {
    foreach ($name in @('WinStore.App', 'Microsoft.StorePurchaseApp', 'StoreExperienceHost', 'ApplicationFrameHost', 'RuntimeBroker')) {
        Invoke-RepairAction "Stop process $name" {
            Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $DryRun) { Start-Sleep -Seconds 2 }
}

Invoke-Step 'Starting core services' {
    Set-ServiceStartup bits demand
    Set-ServiceStartup wuauserv demand
    Set-ServiceStartup dosvc demand
    Set-ServiceStartup InstallService demand
    Set-ServiceStartup AppXSvc demand
    Set-ServiceStartup ClipSVC demand
    Set-ServiceStartup cryptsvc auto

    foreach ($service in @('bits', 'wuauserv', 'dosvc', 'InstallService', 'AppXSvc', 'ClipSVC', 'cryptsvc')) {
        Start-RepairService $service
    }
}

Invoke-Step 'Resetting Microsoft Store cache' {
    [void](Invoke-NativeCommand -FilePath 'wsreset.exe' -Description 'wsreset.exe')
    if (-not $DryRun) { Start-Sleep -Seconds 5 }
}

Invoke-Step 'Cleaning user Store cache' {
    $storePackage = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsStore_8wekyb3d8bbwe'
    Remove-RepairPath (Join-Path $storePackage 'LocalCache')
    Remove-RepairPath (Join-Path $storePackage 'LocalState\Cache')
    Remove-RepairPath (Join-Path $storePackage 'TempState')
}

Invoke-Step 'Resetting BITS and Delivery Optimization' {
    [void](Invoke-NativeCommand -FilePath 'bitsadmin.exe' -Arguments @('/reset', '/allusers') -Description 'BITS queue reset')
    Stop-RepairService bits
    Stop-RepairService dosvc
    Remove-RepairItems (Join-Path $env:ALLUSERSPROFILE 'Microsoft\Network\Downloader\qmgr*.dat')
    Remove-RepairItems (Join-Path $env:ProgramData 'Microsoft\Network\Downloader\qmgr*.dat')
    Remove-RepairPath (Join-Path $env:ProgramData 'Microsoft\Windows\DeliveryOptimization\Cache')
    Start-RepairService bits
    Start-RepairService dosvc
} -MinimumMode 'Default'

Invoke-Step 'Hard resetting Windows Store backend' {
    foreach ($service in @('wuauserv', 'bits', 'dosvc', 'cryptsvc', 'msiserver')) {
        Stop-RepairService $service
    }

    Remove-RepairItems (Join-Path $env:windir 'SoftwareDistribution\Download\*')
    Remove-RepairItems (Join-Path $env:windir 'SoftwareDistribution\DataStore\Logs\*')

    $catroot = Join-Path $env:windir 'System32\catroot2'
    $backup = Join-Path $env:windir ('System32\catroot2.msstore_repair_old_{0}' -f (Get-Random))
    if (Test-Path -LiteralPath $catroot) {
        Invoke-RepairAction "Rename catroot2 to $backup" {
            Rename-Item -LiteralPath $catroot -NewName (Split-Path -Leaf $backup) -ErrorAction Stop
        }
    }

    foreach ($service in @('cryptsvc', 'msiserver', 'bits', 'dosvc', 'wuauserv')) {
        Start-RepairService $service
    }
} -MinimumMode 'Hard'

Invoke-Step 'Resetting network stack' {
    [void](Invoke-NativeCommand -FilePath 'ipconfig.exe' -Arguments @('/flushdns') -Description 'Flush DNS')
    [void](Invoke-NativeCommand -FilePath 'netsh.exe' -Arguments @('winsock', 'reset') -Description 'Winsock reset')
    [void](Invoke-NativeCommand -FilePath 'netsh.exe' -Arguments @('int', 'ip', 'reset') -Description 'IP stack reset')
} -MinimumMode 'Hard'

Invoke-Step 'Re-registering Microsoft Store packages' {
    Repair-StorePackages
}

Invoke-Step 'Running DISM health restore' {
    [void](Invoke-NativeCommand -FilePath 'DISM.exe' -Arguments @('/Online', '/Cleanup-Image', '/RestoreHealth') -Description 'DISM RestoreHealth' -TrackProgress)
} -MinimumMode 'Hard'

Invoke-Step 'Running System File Checker' {
    [void](Invoke-NativeCommand -FilePath 'sfc.exe' -Arguments @('/scannow') -Description 'System File Checker' -TrackProgress)
} -MinimumMode 'Hard'

Invoke-Step 'Verifying services' {
    foreach ($service in @('bits', 'wuauserv', 'dosvc', 'InstallService', 'AppXSvc', 'ClipSVC', 'cryptsvc')) {
        $state = (Get-Service -Name $service -ErrorAction SilentlyContinue).Status
        if ($null -eq $state) {
            $script:Warnings++
            Write-Ui ('   WARN  {0,-16} not found' -f $service) Yellow
            Write-RepairLog ('Service not found: {0}' -f $service)
        } else {
            Write-Ui ('   INFO  {0,-16} {1}' -f $service, $state) Gray
            Write-RepairLog ('Service: {0} = {1}' -f $service, $state)
        }
    }
}

Invoke-Step 'Opening Microsoft Store' {
    if ($NoStoreLaunch) {
        Write-Ui '   SKIP  Store launch disabled.' DarkGray
        Write-RepairLog 'Store launch disabled.'
        return
    }

    Invoke-RepairAction 'Open Microsoft Store' {
        Start-Process 'ms-windows-store:'
    }
}

Write-RepairLog ''
Write-RepairLog ('Finished: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-RepairLog ('Failed steps: {0}' -f $script:FailedSteps)
Write-RepairLog ('Warnings: {0}' -f $script:Warnings)

Write-Ui ''
Write-Rule Green
Write-Ui '   RECOVERY COMPLETE' Green
Write-Rule Green
Show-StatusLine 'Completed mode' $Mode Cyan
Show-StatusLine 'Dry-run preview' ($(if ($DryRun) { 'ON' } else { 'OFF' })) ($(if ($DryRun) { 'Magenta' } else { 'Gray' }))
Show-StatusLine 'Warnings' ([string]$script:Warnings) ($(if ($script:Warnings -gt 0) { 'Yellow' } else { 'Green' }))
Show-StatusLine 'Failed steps' ([string]$script:FailedSteps) ($(if ($script:FailedSteps -gt 0) { 'Red' } else { 'Green' }))
Show-StatusLine 'Log file' $script:Log Gray
Write-Ui ''
Write-Ui '   Recommended next steps: restart your PC, open Microsoft Store, then choose Library > Get updates.' White
Write-Ui ''

if (-not $SkipPrompt) {
    Read-Host '   Press Enter to exit'
}

if ($script:FailedSteps -gt 0) {
    exit 1
}

exit 0
