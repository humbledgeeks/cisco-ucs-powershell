<#
.SYNOPSIS
    Retrieves a basic inventory of Cisco UCS blades and their Service Profile associations.
.DESCRIPTION
    Connects to a Cisco UCS Manager domain and outputs a summary of all blade servers,
    their current power state, associated Service Profile, and operational state.
    Read-only — no changes are made to the environment.
.PARAMETER UCSManager
    FQDN or IP address of the UCS Manager (Fabric Interconnect).
.EXAMPLE
    .\get-ucs-inventory.ps1 -UCSManager ucsm.lab.local
.NOTES
    Author  : humbledgeeks-allen
    Date    : 2026-03-16
    Version : 1.0
    Module  : Cisco.UCSManager
    Repo    : cisco-ucs-powershell
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$UCSManager
)

$ErrorActionPreference = "Stop"

# ── Connect ──────────────────────────────────────────────────────────────────
Write-Output "Connecting to UCS Manager: $UCSManager"
$creds  = Get-Credential -Message "Enter UCS Manager credentials"
$handle = Connect-Ucs -Name $UCSManager -Credential $creds

# ── Blade Inventory ───────────────────────────────────────────────────────────
Write-Output "`n=== UCS Blade Inventory ==="
Get-UcsBlade | Select-Object `
    @{N="Server";   E={$_.Dn}},
    @{N="Model";    E={$_.Model}},
    @{N="Serial";   E={$_.Serial}},
    @{N="Power";    E={$_.OperPower}},
    @{N="Profile";  E={$_.AssignedToDn}},
    @{N="State";    E={$_.OperState}} |
    Format-Table -AutoSize

# ── Service Profile Summary ───────────────────────────────────────────────────
Write-Output "`n=== Service Profile Associations ==="
Get-UcsServiceProfile | Select-Object `
    @{N="Profile";  E={$_.Name}},
    @{N="Template"; E={$_.SrcTemplName}},
    @{N="Server";   E={$_.PnDn}},
    @{N="State";    E={$_.AssocState}} |
    Format-Table -AutoSize

# ── Active Faults ─────────────────────────────────────────────────────────────
Write-Output "`n=== Active Faults (Critical / Major) ==="
$faults = Get-UcsFault | Where-Object { $_.Severity -in "critical","major" }
if ($faults) {
    $faults | Select-Object Severity, Dn, Descr | Format-Table -AutoSize
} else {
    Write-Output "No critical or major faults found."
}

# ── Disconnect ────────────────────────────────────────────────────────────────
Disconnect-Ucs
Write-Output "`nDone."
