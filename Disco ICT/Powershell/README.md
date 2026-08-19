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

# Set-DiscoSnipeAssignments.ps1 + Compare-DiscoSnipeAssignedUser.ps1

A pair of scripts that keep Disco and Snipe-IT's device-assignment data converging, matched by serial number. Disco's `DeviceUserAssignments` table stores a sAMAccountName; Snipe-IT stores a UPN, so both scripts pull the full AD user list to translate between the two.

They're split specifically so they can run on different PowerShell Universal schedules: `Set-DiscoSnipeAssignments.ps1` is cheap and safe to run often (e.g. every ~30 minutes via a PSU workflow) since it only writes, never reports; `Compare-DiscoSnipeAssignedUser.ps1` is read-only and meant for a slower cadence (e.g. once a day) since its whole purpose is to be read by a person.

Both scripts independently pull the same data and duplicate the same helper functions (`Invoke-SnipeItRequest`, `ConvertTo-SnipeItDateTime`) rather than sharing a module, so either can run standalone in PSU without dependency wiring.

## Set-DiscoSnipeAssignments.ps1 (writes only)

All actions gated by `$DryRun`:

1. Any assignment where the user's CASES Status is `'LEFT'` and the user no longer exists in AD (accounts are retained ~30 days after exit, so still existing in AD means it's too soon) is unassigned in **both** Disco (`UnassignedDate` set) and Snipe-IT (checked in).
2. Any mismatch where the Disco assignment is strictly newer than Snipe-IT's is applied to Snipe-IT: checked in first if it's currently assigned to someone else (Snipe-IT refuses to check an asset out while it's still checked out), then checked out to the Disco-assigned user with `status_id` set to `SnipeItDeployedStatusId`.
   - If the Disco user can't be resolved to an AD account, or has no matching Snipe-IT user account, this is logged to `Write-Information` and skipped rather than guessed at.
   - Records already matching (directly, or via a legacy AD `proxyAddress` covering a preferred-name change) are left alone - see the matching logic under Compare below.
3. Any Snipe-IT asset sitting at "Deployed" with nobody assigned has its status reverted to `SnipeItAvailableStatusId`.

The reverse direction (Snipe-IT newer than Disco) is **not** written back automatically - Disco is treated as the authoritative side for auto-remediation; a Snipe-IT-newer mismatch only ever shows up as a recommendation in the Compare script.

## Compare-DiscoSnipeAssignedUser.ps1 (read-only)

Makes no writes to Disco, Snipe-IT, or AD.

1. Queries Disco for every currently-active assignment (`UnassignedDate IS NULL`) - `DeviceSerialNumber`, `AssignedUserId`, `AssignedDate`. The user ID is stripped of any prefix up to and including the last `\`.
2. Pulls every Snipe-IT hardware asset and, for each, resolves the checked-out user's UPN (only when `assigned_to.type` is `user` - assets checked out to a room/location/other asset are left alone).
3. For each Disco assignment, compares the resolved Disco UPN against the Snipe-IT UPN:
   - Exact match - logged to Verbose.
   - No exact match, but the Snipe-IT UPN turns up in the assigned AD user's `proxyAddresses` (split on the first `:`, so it works for `smtp:`, `SIP:`, etc.) - treated as a match and logged to Verbose. This covers a preferred-name change in AD that Snipe-IT hasn't picked up yet, since the old address survives as a proxy address.
   - Genuine mismatch - logged to Information with a recommendation for which system to update, based on whichever side has the more recent assignment date (`AssignedDate` in Disco, `last_checkout` in Snipe-IT). Note: a "recommend updating Snipe-IT" mismatch here is exactly what `Set-DiscoSnipeAssignments.ps1` acts on automatically - if that script is running on schedule, this recommendation should be transient.
4. Separately flags every Snipe-IT asset with status "Deployed" (`SnipeItDeployedStatusId`) that's checked out to a non-user (room/location/other asset) as skipped (Verbose), and silently ignores Deployed assets assigned to a user with no active Disco assignment record (Disco isn't the source of truth for every asset Snipe-IT tracks, e.g. staff-only or non-Disco stock).

## Requirements (both scripts)

- `ActiveDirectory` and `SqlServer` PowerShell modules.
- A SQL login with read access to the Disco database (`Set-DiscoSnipeAssignments.ps1` also needs write access to `DeviceUserAssignments`).
- An AD account with permission to read user objects (`UserPrincipalName`, `ProxyAddresses`).
- A Snipe-IT API token with permission to read hardware/users; `Set-DiscoSnipeAssignments.ps1` also needs checkin/checkout and status-update permissions.

## Setup

All configuration is in the variables block at the top of each script - replace each `<<PLACEHOLDER>>` (or bind to PowerShell Universal variables/secrets of the same names if running there):

| Variable | Purpose |
|---|---|
| `SqlServerInstance`, `SqlDatabase`, `SqlUsername`, `SqlPassword` | Disco SQL connection. Set `SqlUseIntegratedAuth = $true` to use the current identity instead. |
| `ADServer`, `ADUsername`, `ADPassword` | AD connection. Set `ADUseCurrentCredential = $true` to use the current identity instead. |
| `ADUserSearchBase` | Optional OU distinguished name to restrict the AD user pull. Blank searches the whole domain. |
| `SnipeItBaseUrl`, `SnipeItApiToken` | Snipe-IT API connection. |
| `SnipeItDeployedStatusId` | The `status_id` for "Deployed" in your Snipe-IT instance. |
| `SnipeItAvailableStatusId` (`Set-DiscoSnipeAssignments.ps1` only) | The `status_id` to revert a Deployed-but-unassigned asset to. |
| `SnipeItRequestDelayMs`, `SnipeItMaxRetries` | Throttling for the Snipe-IT API - a small delay between calls plus backoff-and-retry on HTTP 429. Both scripts pull the entire hardware inventory, so it's worth keeping. |
| `DryRun` (`Set-DiscoSnipeAssignments.ps1` only) | Defaults to `$true`. Logs what would change without making any changes. Set to `$false` once you've validated the output. |

## Output

- `Write-Output`: an action taken (or a dry-run preview of one), and non-fatal anomalies worth a look (e.g. more than one Snipe-IT asset sharing a serial number).
- `Write-Verbose`: confirmed matches (direct or via a legacy proxy address), and non-user checkouts skipped in the Deployed sweep. Pass `-Verbose` to see these.
- `Write-Information`: genuine mismatches (with a recommendation), unresolvable AD/Snipe-IT lookups. Pass `-InformationAction Continue` (or `-InformationVariable`) to see these if not already visible.
- `Write-Error`: genuine failures (SQL update failed, Snipe-IT API call failed).

# Set-SnipeItDeployedStatus.ps1

One-off (but safely re-runnable) Snipe-IT-only cleanup, no Disco/AD involved: finds every asset sitting in a "Ready to Deploy"-type status (`SnipeItReadyToDeployStatusIds`, an array so you can list more than one) that is actually checked out - to a user, a location, or another asset, it doesn't matter which - and corrects its status to "Deployed" (`SnipeItDeployedStatusId`).

## Requirements

- A Snipe-IT API token with permission to read hardware assets and update their status.

## Setup

| Variable | Purpose |
|---|---|
| `SnipeItBaseUrl`, `SnipeItApiToken` | Snipe-IT API connection. |
| `SnipeItReadyToDeployStatusIds` | Array of `status_id`(s) considered "Ready to Deploy" in your Snipe-IT instance. |
| `SnipeItDeployedStatusId` | The `status_id` to set on any matched asset. |
| `SnipeItRequestDelayMs`, `SnipeItMaxRetries` | Throttling for the Snipe-IT API. |
| `DryRun` | Defaults to `$true`. Set to `$false` once you've validated the output. |

## Output

- `Write-Output`: an action taken (or a dry-run preview of one).
- `Write-Error`: genuine failures (Snipe-IT status update failed).

# Remove-SnipeItExitedUsers.ps1

Deletes Snipe-IT users who are no longer current, matched to AD by username (UPN). AD's `Enabled` flag is deliberately **not** used as a signal here - a disabled account can just as easily mean new/not-yet-provisioned, temporarily locked, or suspended, none of which mean the person has left. The only signals treated as "exited":

- The account no longer exists in AD at all, or
- It exists but AD's CASES status attribute marks them as left, or
- It sits in a compliance-retained OU (`$ADComplianceRetainedOUs` - some staff accounts are deliberately kept enabled for records-keeping reasons even after leaving; accounts under these OUs are treated as exited regardless of any other state).

Any of those - checks in and sets `SnipeItUnassignedStatusId` on any assets still assigned to them, then deletes the Snipe-IT user (all gated by `$DryRun`). Anything else - left alone. Usernames in `$ExcludedSnipeUsernames` (service/admin accounts) are always skipped first, before any AD lookup.

## Requirements

- `ActiveDirectory` PowerShell module.
- An AD account with permission to read user objects (`UserPrincipalName` and the CASES status attribute).
- A Snipe-IT API token with permission to read/checkin/update hardware assets, **and `users.delete`** on its own Snipe-IT account. This is a separate permission from asset checkin/status-update rights - without it, checkin and status-update calls succeed but the delete call fails with a generic `"This action is unauthorized."`, even after every asset has been successfully checked in. Confirmed against `UsersController::destroy()` in the Snipe-IT source, which requires the `users` permission column on the caller's role.

## Setup

| Variable | Purpose |
|---|---|
| `SnipeItBaseUrl`, `SnipeItApiToken` | Snipe-IT API connection. |
| `SnipeItUnassignedStatusId` | The `status_id` to set on assets checked in from a deleted user. |
| `SnipeItRequestDelayMs`, `SnipeItMaxRetries` | Throttling for the Snipe-IT API. |
| `ADServer`, `ADUsername`, `ADPassword` | AD connection. Set `ADUseCurrentCredential = $true` to use the current identity instead. |
| `ADCasesStatusAttribute` | The AD attribute holding CASES status - `userCASESStatus` confirmed correct against live WPSC data. |
| `ADCasesStatusLeftValue` | The value of that attribute meaning "exited" - `Left` confirmed correct against live WPSC data. |
| `ADComplianceRetainedOUs` | Array of OU distinguished names kept enabled for records-keeping only. Defaults to empty - not needed yet, just a hook for if/when this comes into play. |
| `ADUsersSearchBase` | Optional OU distinguished name to restrict the AD user pull (should cover `ADComplianceRetainedOUs` too, since AD search is subtree from this base). Blank searches the whole domain. |
| `ExcludedSnipeUsernames` | Array of Snipe-IT usernames to always skip, e.g. service/admin accounts. |
| `DryRun` | Defaults to `$true`. Set to `$false` once you've validated the output. |

## Output

- `Write-Output`: an action taken (or a dry-run preview of one).
- `Write-Verbose`: routine no-op skips (excluded username, still current per AD/CASES).
- `Write-Information`: accounts that can't be matched at all (no username on the Snipe-IT record to match against AD).
- `Write-Error`: genuine failures (Snipe-IT API call failed).
