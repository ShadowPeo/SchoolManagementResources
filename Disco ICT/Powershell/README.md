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

# Compare-DiscoSnipeAssignedUser.ps1

Cross-checks who a device is assigned to in Disco vs Snipe-IT, matched by serial number, and flags where they disagree. Disco's `DeviceUserAssignments` table stores a sAMAccountName; Snipe-IT stores a UPN, so the full AD user list is pulled once to translate between the two.

1. Queries Disco for every currently-active assignment (`UnassignedDate IS NULL`) - `DeviceSerialNumber`, `AssignedUserId`, `AssignedDate`. The user ID is stripped of any prefix up to and including the last `\`.
2. Pulls every Snipe-IT hardware asset and, for each, resolves the checked-out user's UPN (only when `assigned_to.type` is `user` - assets checked out to a room/location/other asset are left alone).
3. For each Disco assignment, compares the resolved Disco UPN against the Snipe-IT UPN:
   - Exact match - logged to Verbose.
   - No exact match, but the Snipe-IT UPN turns up in the assigned AD user's `proxyAddresses` (split on the first `:`, so it works for `smtp:`, `SIP:`, etc.) - treated as a match and logged to Verbose. This covers a preferred-name change in AD that Snipe-IT hasn't picked up yet, since the old address survives as a proxy address.
   - Genuine mismatch - logged to Information with a recommendation for which system to update, based on whichever side has the more recent assignment date (`AssignedDate` in Disco, `last_checkout` in Snipe-IT).
4. Separately sweeps every Snipe-IT asset with status "Deployed" (`SnipeItDeployedStatusId`):
   - Not assigned to anyone - status is reverted to `SnipeItAvailableStatusId` (gated by `DryRun`).
   - Assigned to a user, but that serial has no active assignment row in Disco - logged to Information as a gap.
   - Assigned to a room/location/other asset - left alone entirely.

No writes to Disco or AD in any case; the only write this script makes is the Snipe-IT status revert above.

## Requirements

- `ActiveDirectory` and `SqlServer` PowerShell modules.
- A SQL login with read access to the Disco database.
- An AD account with permission to read user objects (`UserPrincipalName`, `ProxyAddresses`).
- A Snipe-IT API token with permission to read hardware assets and update their status.

## Setup

All configuration is in the variables block at the top of the script - replace each `<<PLACEHOLDER>>` (or bind to PowerShell Universal variables/secrets of the same names if running there):

| Variable | Purpose |
|---|---|
| `SqlServerInstance`, `SqlDatabase`, `SqlUsername`, `SqlPassword` | Disco SQL connection. Set `SqlUseIntegratedAuth = $true` to use the current identity instead. |
| `ADServer`, `ADUsername`, `ADPassword` | AD connection. Set `ADUseCurrentCredential = $true` to use the current identity instead. |
| `ADUserSearchBase` | Optional OU distinguished name to restrict the AD user pull. Blank searches the whole domain. |
| `SnipeItBaseUrl`, `SnipeItApiToken` | Snipe-IT API connection. |
| `SnipeItDeployedStatusId`, `SnipeItAvailableStatusId` | The `status_id` values for "Deployed" and "Available" (or equivalent) in your Snipe-IT instance. |
| `SnipeItRequestDelayMs`, `SnipeItMaxRetries` | Throttling for the Snipe-IT API - a small delay between calls plus backoff-and-retry on HTTP 429. This script pulls the entire hardware inventory, so it's worth keeping. |
| `DryRun` | Defaults to `$true`. Logs what status revert would happen without making any changes. Set to `$false` once you've validated the output. |

## Output

- `Write-Output`: an action taken (or a dry-run preview of one), and non-fatal anomalies worth a look (e.g. more than one Snipe-IT asset sharing a serial number).
- `Write-Verbose`: confirmed matches (direct or via a legacy proxy address), and non-user checkouts skipped in the Deployed sweep. Pass `-Verbose` to see these.
- `Write-Information`: genuine mismatches (with a recommendation), unresolvable AD lookups, and Deployed-but-unaccounted-for assignments. Pass `-InformationAction Continue` (or `-InformationVariable`) to see these if not already visible.
- `Write-Error`: genuine failures (Snipe-IT status update failed).
