Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Expand-Value([string]$Value) { [Environment]::ExpandEnvironmentVariables($Value) }

function Get-TreeBytes {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return [int64]$item.Length }
    [int64](Get-ChildItem -LiteralPath $item.FullName -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}

function Assert-SafeCleanupPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $broad = @(
        [IO.Path]::GetPathRoot($full).TrimEnd('\'),
        $env:SystemRoot.TrimEnd('\'),
        $env:ProgramFiles.TrimEnd('\'),
        ${env:ProgramFiles(x86)}.TrimEnd('\'),
        $env:ProgramData.TrimEnd('\'),
        $env:USERPROFILE.TrimEnd('\')
    ) | Where-Object { $_ }
    if ($full -in $broad) { throw "Broad cleanup path refused: $full" }
    if ($full -match '(?i)\\WindowsLockdownKit(?:\\|$)') { throw 'Permanent-lockdown artifacts are outside cleanup scope.' }
    if ([IO.Path]::GetFileName($full) -match '^(?i:AGENTS\.md|PERMANENT-HARD-RULE\.md)$') { throw 'Permanent rule files are outside cleanup scope.' }
    $full
}

function Test-ProtectedCandidate {
    param([string]$Text, $Config)
    foreach ($pattern in @($Config.protectedNamePatterns)) {
        if ($Text -match [regex]::Escape([string]$pattern)) { return $true }
    }
    return $false
}

function Get-Fingerprint {
    param([string]$Path, [int64]$Bytes, [datetime]$LastWriteUtc)
    $text = '{0}|{1}|{2:o}' -f ([IO.Path]::GetFullPath($Path).ToLowerInvariant()), $Bytes, $LastWriteUtc
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-SteamRoots {
    $roots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @((Join-Path ${env:ProgramFiles(x86)} 'Steam'), (Join-Path $env:ProgramFiles 'Steam'))) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { [void]$roots.Add((Resolve-Path $candidate).Path) }
    }
    foreach ($root in @($roots)) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        $text = Get-Content -LiteralPath $vdf -Raw
        foreach ($match in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
            $path = $match.Groups[1].Value -replace '\\\\', '\'
            if (Test-Path -LiteralPath $path) { [void]$roots.Add((Resolve-Path $path).Path) }
        }
    }
    @($roots)
}

function New-Candidate {
    param([string]$Path, [string]$Category, [string]$Reason, $Config)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = Assert-SafeCleanupPath $Path
    if (Test-ProtectedCandidate $full $Config) { return }
    $item = Get-Item -LiteralPath $full -Force
    $bytes = Get-TreeBytes $full
    $fingerprint = Get-Fingerprint -Path $full -Bytes $bytes -LastWriteUtc $item.LastWriteTimeUtc
    [pscustomobject]@{
        itemId = '{0}-{1}' -f $Category.ToLowerInvariant().Replace(' ', '-'), $fingerprint.Substring(0, 10)
        path = $full
        category = $Category
        reason = $Reason
        kind = if ($item.PSIsContainer) { 'Directory' } else { 'File' }
        bytes = $bytes
        lastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
        fingerprint = $fingerprint
    }
}

