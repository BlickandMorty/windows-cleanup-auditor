$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scripts = Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.ps1' -File
foreach ($script in $scripts) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$($script.Name): $($errors -join '; ')" }
}
. (Join-Path $root 'src\Common.ps1')
foreach ($path in @($env:SystemRoot, $env:ProgramData, $env:USERPROFILE, 'C:\ProgramData\WindowsLockdownKit\Guardian')) {
    $threw = $false
    try { [void](Assert-SafeCleanupPath $path) } catch { $threw = $true }
    if (-not $threw) { throw "Safety check did not refuse: $path" }
}
$config = Get-Content -LiteralPath (Join-Path $root 'config\cleanup.example.json') -Raw | ConvertFrom-Json
if (@($config.explicitCandidates).Count) { throw 'Example explicitCandidates list must be empty.' }
Write-Host "Static checks passed for $($scripts.Count) scripts."

