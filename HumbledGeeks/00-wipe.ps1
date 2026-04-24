#Requires -Version 5.1
<#
.SYNOPSIS
    00-wipe - Remove all HumbledGeeks config for a clean rebuild
.DESCRIPTION
    Destructive reset script. Deletes:
      - The HumbledGeeks sub-org and ALL child objects (pools, policies,
        templates, service profiles)
      - VLANs at IDs 13-22, 32, 34, 253 (recreated by 02-vlans-vsans.ps1)
      - VSANs named FabricA, FabricB, hg-vsan-a, hg-vsan-b
      - FC zone profile hg-fc-zones

    Safe to re-run — uses -ErrorAction SilentlyContinue throughout.
    Port channels, uplink port configs, and chassis/FI hardware config
    are NOT touched.

.NOTES
    Run BEFORE the numbered scripts (01 through 09) when starting from scratch.
    ── CUSTOMISE FOR YOUR DEPLOYMENT ──────────────────────────────────────
    Update $UCSMHost and $OrgName below to match your environment.
    ────────────────────────────────────────────────────────────────────────

.EXAMPLE
    # Set password, then wipe
    $env:UCSM_PASSWORD = 'YourPassword'
    .\00-wipe.ps1

.EXAMPLE
    # Interactive credential prompt (no env var needed)
    .\00-wipe.ps1
#>

# ══════════════════════════════════════════════════════════════════════════
# DEPLOYMENT CONFIGURATION — change these for a new environment
# ══════════════════════════════════════════════════════════════════════════
$UCSMHost = '10.103.12.20'    # UCSM Virtual IP
$OrgName  = 'HumbledGeeks'    # Sub-org to wipe
# ══════════════════════════════════════════════════════════════════════════

# ── Connect ────────────────────────────────────────────────────────────────
if ($env:UCSM_PASSWORD) {
    $secPwd = ConvertTo-SecureString $env:UCSM_PASSWORD -AsPlainText -Force
    $cred   = New-Object System.Management.Automation.PSCredential('admin', $secPwd)
    Write-Host "[INFO] Using UCSM_PASSWORD env var for authentication" -ForegroundColor DarkGray
} else {
    $cred = Get-Credential -UserName 'admin' -Message "Enter UCSM credentials for $UCSMHost"
}

$h = Connect-Ucs -Name $UCSMHost -Credential $cred -NotDefault

Write-Host "`n========== 00-wipe - Cleaning UCSM for fresh deployment ==========" -ForegroundColor Red

# ── 1. Delete sub-org (removes all child objects recursively) ──────────────
Write-Host "`n[WIPE] $OrgName org..."
$org = Get-UcsOrg -Ucs $h | Where-Object { $_.Name -eq $OrgName }
if ($org) {
    $org | Remove-UcsOrg -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK]   $OrgName org removed" -ForegroundColor Green
} else {
    Write-Host "  [SKIP] HumbledGeeks org not found" -ForegroundColor DarkGray
}

# ── 2. Delete stale VLANs ──────────────────────────────────────────────────
Write-Host "`n[WIPE] Stale VLANs..."
$staleVlanIds = @(13, 14, 15, 16, 17, 18, 20, 22, 32, 34, 253)
foreach ($id in $staleVlanIds) {
    $vlan = Get-UcsVlan -Ucs $h | Where-Object { $_.Id -eq $id }
    if ($vlan) {
        $vlan | Remove-UcsVlan -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK]   Removed VLAN $id ($($vlan.Name))" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] VLAN $id not found" -ForegroundColor DarkGray
    }
}

# ── 3. Delete VSANs (stale and current names) ─────────────────────────────
Write-Host "`n[WIPE] VSANs..."
$staleVsanNames = @('FabricA', 'FabricB', 'hg-vsan-a', 'hg-vsan-b')
foreach ($name in $staleVsanNames) {
    $vsan = Get-UcsVsan -Ucs $h | Where-Object { $_.Name -eq $name }
    if ($vsan) {
        $vsan | ForEach-Object { $_ | Remove-UcsVsan -Force -ErrorAction SilentlyContinue }
        Write-Host "  [OK]   Removed VSAN '$name'" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] VSAN '$name' not found" -ForegroundColor DarkGray
    }
}

# ── 4. Delete FC zone profile ──────────────────────────────────────────────
Write-Host "`n[WIPE] FC Zone profile..."
$zoneProfile = Get-UcsFabricFcZoneProfile -Ucs $h | Where-Object { $_.Name -eq 'hg-fc-zones' }
if ($zoneProfile) {
    $zoneProfile | Remove-UcsFabricFcZoneProfile -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK]   Removed FC zone profile hg-fc-zones" -ForegroundColor Green
} else {
    Write-Host "  [SKIP] FC zone profile hg-fc-zones not found" -ForegroundColor DarkGray
}

# ── 5. Final verification ──────────────────────────────────────────────────
Write-Host "`n[VERIFY] Remaining orgs:"
Get-UcsOrg -Ucs $h | Select-Object Name, Dn | Format-Table -AutoSize

Write-Host "[VERIFY] Remaining dc3-* VLANs:"
Get-UcsVlan -Ucs $h | Where-Object { $_.Name -ne 'default' } |
    Sort-Object { [int]$_.Id } | Select-Object Id, Name | Format-Table -AutoSize

Write-Host "[VERIFY] Remaining VSANs:"
Get-UcsVsan -Ucs $h | Where-Object { $_.Name -ne 'default' } |
    Select-Object Name, Id, FabricId | Format-Table -AutoSize

Disconnect-Ucs -Ucs $h
Write-Host "`n[DONE] Wipe complete. Ready to run scripts 01 through 09.`n" -ForegroundColor Green
