#Requires -Version 5.1
<#
.SYNOPSIS
    Section 10 - Post-deployment verification report
.DESCRIPTION
    Queries UCSM and prints a full health summary of the HumbledGeeks environment:
      - Pool utilisation (MAC, UUID, WWNN, WWPN, IP)
      - VLAN and VSAN state
      - vNIC and vHBA template list
      - Service profile association states and assigned identities
      - FC zone profile and zone count
      - Active faults (critical/major/warning)
      - Uplink port channel states

    Safe to run at any time — read-only, no changes are made.
.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.
    READ-ONLY — this script makes no changes to UCSM.
    Safe to run at any point during deployment to confirm current state.

    What to check at each milestone:
      After 01-03  : Pools and VLANs/VSANs appear, no faults
      After 04-05  : vNIC and vHBA templates listed
      After 06-07  : Service profiles created, AssocState = unassociated
      After 07b    : AssocState = associated, OperState = ok
      After 09     : FC zone profile AdminState = enabled, 16 zones present
      Final state  : No unacknowledged critical/major/warning faults

    Nothing to configure — the script reads from whatever $global:UcsHandle
    was established by 00-prereqs-and-connect.ps1, which picks up the UCSM
    host and org name from that file's DEPLOYMENT CONFIGURATION block.

.EXAMPLE
    # Run standalone — verifies current UCSM state
    $env:UCSM_PASSWORD = 'YourPassword'
    .\10-verify.ps1

.EXAMPLE
    # Quick check during a run-all deployment — called automatically
    .\run-all.ps1   # 10-verify.ps1 runs as the final step automatically
#>

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h   = $global:UcsHandle
$org = $global:HgOrg

Write-Host "`n========== 10 - HumbledGeeks Verification Report ==========" -ForegroundColor Cyan

# ── Pools ──────────────────────────────────────────────────────────────────
Write-Host "`n--- Address Pools ---" -ForegroundColor Yellow
Get-UcsMacPool -Ucs $h | Where-Object { $_.Dn -like '*HumbledGeeks*' } |
    Select-Object Name, Size, Assigned, AssignmentOrder | Format-Table -AutoSize

Get-UcsUuidSuffixPool -Ucs $h | Where-Object { $_.Dn -like '*HumbledGeeks*' } |
    Select-Object Name, Size, Assigned | Format-Table -AutoSize

Get-UcsManagedObject -ClassId FcpoolInitiators -Ucs $h | Where-Object { $_.Dn -like '*HumbledGeeks*' } |
    Select-Object Name, Purpose, Size, Assigned | Format-Table -AutoSize

Get-UcsIpPool -Ucs $h | Where-Object { $_.Dn -like '*HumbledGeeks*' } |
    Select-Object Name, Size, Assigned | Format-Table -AutoSize

# ── VLANs ─────────────────────────────────────────────────────────────────
Write-Host "`n--- VLANs (LAN Cloud) ---" -ForegroundColor Yellow
Get-UcsVlan -Ucs $h | Sort-Object { [int]$_.Id } |
    Select-Object Id, Name, DefaultNet | Format-Table -AutoSize

# ── VSANs ─────────────────────────────────────────────────────────────────
Write-Host "`n--- VSANs (FC Storage Cloud) ---" -ForegroundColor Yellow
Get-UcsVsan -Ucs $h |
    Select-Object Name, Id, FcoeVlan, FabricId, OperState | Format-Table -AutoSize

# ── vNIC Templates ────────────────────────────────────────────────────────
Write-Host "`n--- vNIC Templates ---" -ForegroundColor Yellow
Get-UcsVnicTemplate -Ucs $h | Where-Object { $_.Dn -like '*HumbledGeeks*' } |
    Select-Object Name, SwitchId, TemplType, Mtu, IdentPoolName, NwCtrlPolicyName |
    Sort-Object Name | Format-Table -AutoSize

# ── vHBA Templates ────────────────────────────────────────────────────────
Write-Host "`n--- vHBA Templates ---" -ForegroundColor Yellow
Get-UcsVhbaTemplate -Ucs $h | Where-Object { $_.Dn -like '*HumbledGeeks*' } |
    Select-Object Name, SwitchId, TemplType, IdentPoolName, MaxDataFieldSize |
    Sort-Object Name | Format-Table -AutoSize

# ── Service Profiles ──────────────────────────────────────────────────────
Write-Host "`n--- Service Profiles ---" -ForegroundColor Yellow
Get-UcsServiceProfile -Ucs $h | Where-Object { $_.Dn -like '*HumbledGeeks*' } |
    Select-Object Name, Type, SrcTemplName, AssocState, OperState, PnDn |
    Sort-Object Name | Format-Table -AutoSize

# ── Assigned vHBA WWPNs ───────────────────────────────────────────────────
Write-Host "`n--- Assigned vHBA WWPNs ---" -ForegroundColor Yellow
Get-UcsManagedObject -ClassId VnicFc -Ucs $h |
    Where-Object { $_.Dn -like '*HumbledGeeks*ls-hg-esx*' } |
    Select-Object @{N='Profile'; E={ ($_.Dn -split '/')[2] -replace '^ls-' }}, Name, Addr |
    Sort-Object Profile, Name | Format-Table -AutoSize

# ── FC Zone Profile ───────────────────────────────────────────────────────
Write-Host "`n--- FC Zone Profile ---" -ForegroundColor Yellow
$zp = Get-UcsFabricFcZoneProfile -Ucs $h | Where-Object { $_.Name -eq 'hg-fc-zones' }
if ($zp) {
    $zp | Select-Object Name, AdminState, OperState, Dn | Format-Table -AutoSize
    $zoneCount = (Get-UcsFabricFcUserZone -Ucs $h | Where-Object { $_.Dn -like '*hg-fc-zones*' }).Count
    Write-Host "  Zones defined: $zoneCount (expect 16 for 8 blades x 2 fabrics)" -ForegroundColor DarkGray
} else {
    Write-Warning "  FC zone profile 'hg-fc-zones' not found - run 09-fc-zoning.ps1"
}

# ── Active Faults ─────────────────────────────────────────────────────────
Write-Host "`n--- Active Faults (critical / major / warning) ---" -ForegroundColor Yellow
$faults = Get-UcsFault -Ucs $h | Where-Object {
    $_.Severity -in 'critical', 'major', 'warning' -and $_.Ack -eq 'no'
}
if ($faults) {
    $faults | Select-Object Severity, Code, Dn, Description | Sort-Object Severity | Format-Table -AutoSize
} else {
    Write-Host "  No unacknowledged critical/major/warning faults." -ForegroundColor Green
}

# ── Uplink Port Channels ──────────────────────────────────────────────────
Write-Host "`n--- Ethernet Uplink Port Channels ---" -ForegroundColor Yellow
Get-UcsFabricEthLanPc -Ucs $h |
    Select-Object Name, PortId, OperState, OperSpeed, Transport | Format-Table -AutoSize

Write-Host "`n[DONE] Verification complete.`n" -ForegroundColor Green
