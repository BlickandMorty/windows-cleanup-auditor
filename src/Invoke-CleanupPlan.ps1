[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$ApprovePlanId,
    [Parameter(Mandatory)][string[]]$ItemId,
    [ValidateSet('Quarantine', 'Permanent')][string]$Disposition = 'Quarantine',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\cleanup.example.json'),
    [switch]$Apply,
    [string]$PermanentAcknowledgement
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath) -Raw | ConvertFrom-Json
$plan = Get-Content -LiteralPath (Resolve-Path -LiteralPath $PlanPath) -Raw | ConvertFrom-Json
if ($plan.schemaVersion -ne 1) { throw 'Unsupported plan schema.' }
if ($ApprovePlanId -cne [string]$plan.planId) { throw 'Approved plan ID does not match.' }
if ($Disposition -eq 'Permanent' -and $PermanentAcknowledgement -cne 'DELETE APPROVED ITEMS PERMANENTLY') {
    throw "Permanent deletion requires -PermanentAcknowledgement 'DELETE APPROVED ITEMS PERMANENTLY'"
}

$selected = @($plan.candidates | Where-Object itemId -in $ItemId)
if ($selected.Count -ne @($ItemId | Sort-Object -Unique).Count) { throw 'One or more requested item IDs are missing from the plan.' }
$verified = foreach ($item in $selected) {
    $path = Assert-SafeCleanupPath ([string]$item.path)
    if (Test-ProtectedCandidate $path $config) { throw "Protected candidate refused: $path" }
    if (-not (Test-Path -LiteralPath $path)) { throw "Candidate no longer exists: $path" }
    $current = Get-Item -LiteralPath $path -Force
    $bytes = Get-TreeBytes $path
    $fingerprint = Get-Fingerprint -Path $path -Bytes $bytes -LastWriteUtc $current.LastWriteTimeUtc
    if ($fingerprint -ne [string]$item.fingerprint) { throw "Candidate changed after the plan was created; create a new plan: $path" }
    [pscustomobject]@{ item = $item; path = $path }
}

foreach ($entry in $verified) { Write-Host "${Disposition}: $($entry.path)" }
if (-not $Apply) { Write-Host 'Audit only. Add -Apply after reviewing the exact paths.'; return }

$results = [Collections.Generic.List[object]]::new()
$quarantineRoot = Expand-Value ([string]$config.quarantineRoot)
if ($Disposition -eq 'Quarantine') { New-Item -ItemType Directory -Path $quarantineRoot -Force | Out-Null }
foreach ($entry in $verified) {
    $path = $entry.path
    if (-not $PSCmdlet.ShouldProcess($path, $Disposition)) { continue }
    try {
        if ($Disposition -eq 'Quarantine') {
            $destination = Join-Path $quarantineRoot ("{0}-{1}" -f $entry.item.itemId, [IO.Path]::GetFileName($path))
            if (Test-Path -LiteralPath $destination) { throw "Quarantine destination already exists: $destination" }
            Move-Item -LiteralPath $path -Destination $destination
            $results.Add([pscustomobject]@{ itemId = $entry.item.itemId; original = $path; disposition = 'Quarantine'; destination = $destination; status = 'Moved' })
        } else {
            Remove-Item -LiteralPath $path -Recurse -Force
            $results.Add([pscustomobject]@{ itemId = $entry.item.itemId; original = $path; disposition = 'Permanent'; destination = $null; status = 'Deleted' })
        }
    } catch {
        $results.Add([pscustomobject]@{ itemId = $entry.item.itemId; original = $path; disposition = $Disposition; destination = $null; status = 'Failed'; error = $_.Exception.Message })
    }
}

$reportRoot = Expand-Value ([string]$config.reportRoot)
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
$reportPath = Join-Path $reportRoot ("cleanup-apply-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$report = [ordered]@{ planId = [string]$plan.planId; appliedAt = (Get-Date).ToString('o'); disposition = $Disposition; results = @($results) }
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Host "Apply report: $reportPath"
if (@($results | Where-Object status -eq 'Failed').Count) { exit 2 }
