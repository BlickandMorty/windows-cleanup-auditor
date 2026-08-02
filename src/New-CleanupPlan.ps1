[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\cleanup.example.json'),
    [string]$OutputPath
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath) -Raw | ConvertFrom-Json
if ($config.schemaVersion -ne 1) { throw 'Unsupported configuration schema.' }
$candidates = [Collections.Generic.List[object]]::new()

if ([bool]$config.includeSteamOrphanAudit) {
    foreach ($root in Get-SteamRoots) {
        $steamApps = Join-Path $root 'steamapps'
        $installed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        Get-ChildItem -LiteralPath $steamApps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $text = Get-Content -LiteralPath $_.FullName -Raw
            $name = [regex]::Match($text, '"installdir"\s+"([^"]+)"').Groups[1].Value
            if ($name) { [void]$installed.Add($name) }
        }
        $common = Join-Path $steamApps 'common'
        Get-ChildItem -LiteralPath $common -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not $installed.Contains($_.Name) } | ForEach-Object {
            $candidate = New-Candidate -Path $_.FullName -Category 'Steam orphan' -Reason 'No matching installed Steam app manifest.' -Config $config
            if ($candidate) { $candidates.Add($candidate) }
        }
    }
}

if ([bool]$config.includeCaches) {
    foreach ($cache in @(
        @{ path = (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'); name = 'NVIDIA shader cache' },
        @{ path = (Join-Path $env:LOCALAPPDATA 'D3DSCache'); name = 'Windows D3D shader cache' },
        @{ path = (Join-Path $env:LOCALAPPDATA 'CrashDumps'); name = 'Application crash dumps' },
        @{ path = (Join-Path $env:LOCALAPPDATA 'EpicGamesLauncher\Saved\webcache'); name = 'Epic launcher web cache' }
    )) {
        $candidate = New-Candidate -Path $cache.path -Category 'Regenerable cache' -Reason $cache.name -Config $config
        if ($candidate) { $candidates.Add($candidate) }
    }
}

foreach ($entry in @($config.explicitCandidates)) {
    $path = Expand-Value ([string]$entry.path)
    $candidate = New-Candidate -Path $path -Category 'Explicit candidate' -Reason ([string]$entry.reason) -Config $config
    if ($candidate) { $candidates.Add($candidate) }
}

$xboxPackages = try {
    @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -match '(?i)xbox|gaming' } | Select-Object Name, PackageFullName, InstallLocation, Status)
} catch {
    @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)xbox|gaming' } | Select-Object Name, PackageFullName, InstallLocation, Status)
}
$planId = [guid]::NewGuid().ToString('N')
$plan = [ordered]@{
    schemaVersion = 1
    planId = $planId
    generatedAt = (Get-Date).ToString('o')
    computer = $env:COMPUTERNAME
    warning = 'Review every item. A candidate is not proof that data is unwanted.'
    totalBytes = [int64]($candidates | Measure-Object bytes -Sum).Sum
    candidates = @($candidates)
    reportOnlyXboxPackages = $xboxPackages
}
if (-not $OutputPath) {
    $reportRoot = Expand-Value ([string]$config.reportRoot)
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    $OutputPath = Join-Path $reportRoot ("cleanup-plan-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
[IO.File]::WriteAllText($OutputPath, ($plan | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Write-Host "Plan: $OutputPath"
Write-Host "Candidates: $($candidates.Count); bytes: $($plan.totalBytes); plan ID: $planId"
$plan | ConvertTo-Json -Depth 10
