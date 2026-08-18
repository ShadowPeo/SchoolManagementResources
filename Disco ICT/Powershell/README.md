# Remove-DecommissionedDevices.ps1

Cleans up devices that have been marked decommissioned in Disco (`DecommissionedDate IS NOT NULL`):

1. Queries Disco for `ComputerName` and `SerialNumber` of every decommissioned device.
2. Strips any NetBIOS-style prefix from `ComputerName` (everything up to and including the last `\`) and deletes the matching AD computer object - but only if it's found inside one of the configured OUs (`$ADSearchBases`). Devices outside those OUs are left untouched, so a decommissioned record can't reach out and delete an unrelated object elsewhere in AD.
3. Looks up the same device in Snipe-IT by `SerialNumber`, checks it in if currently assigned, and sets its status to the configured decommissioned status ID.

## Requirements

- `ActiveDirectory` and `SqlServer` PowerShell modules.
- A SQL login with read access to the Disco database.
- An AD account with permission to delete computer objects in the target OU(s).
- A Snipe-IT API token with permission to check in and update hardware assets.

## Setup

All configuration is in the variables block at the top of the script - replace each `<<PLACEHOLDER>>` (or bind to PowerShell Universal variables/secrets of the same names if running there):

| Variable | Purpose |
|---|---|
| `SqlServerInstance`, `SqlDatabase`, `SqlUsername`, `SqlPassword` | Disco SQL connection. Set `SqlUseIntegratedAuth = $true` to use the current identity instead. |
| `ADServer`, `ADUsername`, `ADPassword` | AD connection. Set `ADUseCurrentCredential = $true` to use the current identity instead. |
| `ADSearchBases` | One or more OU distinguished names. Only computer objects under these OUs (subtree search) can be matched and deleted. |
| `SnipeItBaseUrl`, `SnipeItApiToken` | Snipe-IT API connection. |
| `SnipeItDecommissionedStatusId` | The `status_id` of the archived/decommissioned status label in your Snipe-IT instance - check via the API (e.g. `GET /api/v1/hardware/byserial/{serial}` and read the `status.id` field of a known-decommissioned asset). |
| `SnipeItRequestDelayMs`, `SnipeItMaxRetries` | Throttling for the Snipe-IT API - a small delay between calls plus backoff-and-retry on HTTP 429. |
| `DryRun` | Defaults to `$true`. Logs what would be deleted/decommissioned without making any changes. Set to `$false` once you've validated the output. |

## Output

- `Write-Output`: an action taken (or a dry-run preview of one), and non-fatal anomalies worth a look (e.g. more than one Snipe-IT asset sharing a serial number).
- `Write-Verbose`: routine no-op skips (device not found in the allowed OUs / not found in Snipe-IT / already decommissioned). Pass `-Verbose` to see these.
- `Write-Error`: genuine failures (AD deletion failed, Snipe-IT API call failed).
