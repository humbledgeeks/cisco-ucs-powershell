#Requires -Version 5.1
<#
.SYNOPSIS
    Section 01 – Create all address pools for HumbledGeeks
.DESCRIPTION
    Creates MAC pools (A+B), UUID suffix pool, WWN pools (WWNN + WWPN A/B),
    and the KVM/ext-mgmt IP pool with all address blocks.
.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.
    To target a different UCSM or org, update $UCSMHost / $OrgName in
    00-prereqs-and-connect.ps1 — no changes needed in this script.

    What you may want to adjust here for a different deployment:
      - MAC pool ranges         (lines starting with -From / -To under [MAC])
      - UUID suffix range       (lines under [UUID])
      - WWNN / WWPN ranges      (lines under [WWN])
      - IP pool range + gateway (lines under [IP])

.EXAMPLE
    # Run standalone
    $env:UCSM_PASSWORD = 'YourPassword'
    .\01-pools.ps1

.EXAMPLE
    # Part of a full deployment — called automatically by run-all.ps1
    .\run-all.ps1
#>

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h   = $global:UcsHandle
$org = $global:HgOrg

Write-Host "`n========== 01 – Pools ==========" -ForegroundColor Cyan

# ── MAC Pool A (Fabric A vNICs: vmnic0/2/4) ───────────────────────────────
Write-Host "`n[MAC] hg-mac-a"
$macA = Add-UcsMacPool -Org $org -Ucs $h `
    -Name          'hg-mac-a' `
    -Descr         'HumbledGeeks MAC pool - Fabric A' `
    -AssignmentOrder 'sequential' `
    -ModifyPresent
Add-UcsMacMemberBlock -MacPool $macA -Ucs $h `
    -From '00:25:B5:11:1A:01' `
    -To   '00:25:B5:11:1C:00' `
    -ModifyPresent
Write-Host "  [OK] hg-mac-a  (00:25:B5:11:1A:01 – 1C:00  /512)" -ForegroundColor Green

# ── MAC Pool B (Fabric B vNICs: vmnic1/3/5) ──────────────────────────────
Write-Host "`n[MAC] hg-mac-b"
$macB = Add-UcsMacPool -Org $org -Ucs $h `
    -Name          'hg-mac-b' `
    -Descr         'HumbledGeeks MAC pool - Fabric B' `
    -AssignmentOrder 'sequential' `
    -ModifyPresent
Add-UcsMacMemberBlock -MacPool $macB -Ucs $h `
    -From '00:25:B5:11:1D:01' `
    -To   '00:25:B5:11:1F:00' `
    -ModifyPresent
Write-Host "  [OK] hg-mac-b  (00:25:B5:11:1D:01 – 1F:00  /512)" -ForegroundColor Green

# ── UUID Suffix Pool ───────────────────────────────────────────────────────
Write-Host "`n[UUID] hg-uuid-pool"
$uuid = Add-UcsUuidSuffixPool -Org $org -Ucs $h `
    -Name            'hg-uuid-pool' `
    -Descr           'HumbledGeeks UUID suffix pool' `
    -AssignmentOrder 'sequential' `
    -Prefix          'derived' `
    -ModifyPresent
Add-UcsUuidSuffixBlock -UuidSuffixPool $uuid -Ucs $h `
    -From '0025-B50000000001' `
    -To   '0025-B500000000A0' `
    -ModifyPresent
Write-Host "  [OK] hg-uuid-pool  (0025-B50000000001 - A0  /160)" -ForegroundColor Green

# ── WWN Pool – WWNN (Node WWN, one per blade) ─────────────────────────────
Write-Host "`n[WWN] hg-wwnn-pool (node)"
$wwnn = $org | Add-UcsManagedObject -ClassId 'FcpoolInitiators' -Ucs $h -PropertyMap @{
    Name            = 'hg-wwnn-pool'
    Descr           = 'HumbledGeeks WWNN pool - node addresses'
    AssignmentOrder = 'sequential'
    Purpose         = 'node-wwn-assignment'
} -ModifyPresent
$wwnn | Add-UcsManagedObject -ClassId 'FcpoolBlock' -Ucs $h -PropertyMap @{
    From = '20:00:00:25:B5:11:1F:01'
    To   = '20:00:00:25:B5:11:1F:A0'
} -ModifyPresent | Out-Null
Write-Host "  [OK] hg-wwnn-pool  (20:00:00:25:B5:11:1F:01 - A0  /160)" -ForegroundColor Green

# ── WWN Pool – WWPN A (Fabric A HBAs: vmhba0) ────────────────────────────
Write-Host "`n[WWN] hg-wwpn-a (port, Fabric A)"
$wwpnA = $org | Add-UcsManagedObject -ClassId 'FcpoolInitiators' -Ucs $h -PropertyMap @{
    Name            = 'hg-wwpn-a'
    Descr           = 'HumbledGeeks WWPN pool - Fabric A'
    AssignmentOrder = 'sequential'
    Purpose         = 'port-wwn-assignment'
} -ModifyPresent
$wwpnA | Add-UcsManagedObject -ClassId 'FcpoolBlock' -Ucs $h -PropertyMap @{
    From = '20:00:00:25:B5:11:1A:01'
    To   = '20:00:00:25:B5:11:1A:A0'
} -ModifyPresent | Out-Null
Write-Host "  [OK] hg-wwpn-a  (20:00:00:25:B5:11:1A:01 - A0  /160)" -ForegroundColor Green

# ── WWN Pool – WWPN B (Fabric B HBAs: vmhba1) ────────────────────────────
Write-Host "`n[WWN] hg-wwpn-b (port, Fabric B)"
$wwpnB = $org | Add-UcsManagedObject -ClassId 'FcpoolInitiators' -Ucs $h -PropertyMap @{
    Name            = 'hg-wwpn-b'
    Descr           = 'HumbledGeeks WWPN pool - Fabric B'
    AssignmentOrder = 'sequential'
    Purpose         = 'port-wwn-assignment'
} -ModifyPresent
$wwpnB | Add-UcsManagedObject -ClassId 'FcpoolBlock' -Ucs $h -PropertyMap @{
    From = '20:00:00:25:B5:11:1B:01'
    To   = '20:00:00:25:B5:11:1B:A0'
} -ModifyPresent | Out-Null
Write-Host "  [OK] hg-wwpn-b  (20:00:00:25:B5:11:1B:01 - A0  /160)" -ForegroundColor Green

# ── IP Pool (KVM / ext-mgmt) ──────────────────────────────────────────────
Write-Host "`n[IP] hg-ext-mgmt"
$ip = Add-UcsIpPool -Org $org -Ucs $h `
    -Name            'hg-ext-mgmt' `
    -Descr           'HumbledGeeks KVM mgmt .180-.188' `
    -AssignmentOrder 'sequential' `
    -ModifyPresent
Add-UcsIpPoolBlock -IpPool $ip -Ucs $h `
    -From       '10.103.12.180' `
    -To         '10.103.12.188' `
    -DefGw      '10.103.12.1' `
    -Subnet     '255.255.255.0' `
    -PrimDns    '0.0.0.0' `
    -ModifyPresent
Write-Host "  [OK] hg-ext-mgmt  (.180–.188 /24 gw .1)" -ForegroundColor Green

Write-Host "`n[DONE] Section 01 – Pools complete.`n" -ForegroundColor Green
