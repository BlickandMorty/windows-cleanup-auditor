# Windows Cleanup Auditor

Find orphaned game folders, stale launcher data, shader caches, crash dumps, and old temporary files—then require a second, explicit approval step before anything moves or deletes.

This project comes from cleanup passes that reconciled Steam manifests, Epic registrations, Xbox/Appx packages, Riot/anti-cheat dependencies, and exact residual folders. The key lesson was that “looks unused” is not enough evidence for deletion.

## Two-stage workflow

1. Generate a read-only plan:

```powershell
.\src\New-CleanupPlan.ps1 -ConfigPath .\config\cleanup.example.json
```

2. Open the JSON report and review every candidate.
3. Apply only selected item IDs. Quarantine is the default:

```powershell
.\src\Invoke-CleanupPlan.ps1 `
  -PlanPath C:\path\cleanup-plan.json `
  -ApprovePlanId PLAN-ID-FROM-REPORT `
  -ItemId steam-orphan-001 `
  -Apply
```

Permanent deletion requires both `-Disposition Permanent` and this exact phrase:

```text
DELETE APPROVED ITEMS PERMANENTLY
```

## What it audits

- Steam libraries: installed app manifests versus directories under `steamapps\common`.
- Explicit candidate paths supplied in configuration.
- Old files under allowlisted temp/crash/cache roots.
- Epic launcher web cache.
- NVIDIA DirectX and Windows D3D shader caches.
- Windows Appx/Xbox packages are reported, never directly deleted; use normal package removal.

## Preservation defaults

The example configuration protects Steam, Riot, Vanguard, Easy Anti-Cheat, Microsoft/Xbox infrastructure, current Epic manifests, saved-game folders, Wallpaper Engine workshop content, and all permanent-lockdown artifacts.

## Why quarantine first

Quarantine makes an incorrect classification recoverable. The apply report records original and quarantine paths, sizes, timestamps, and outcomes. Quarantine cleanup should happen only after the computer has been used normally for long enough to expose missing dependencies.

## License

MIT.

