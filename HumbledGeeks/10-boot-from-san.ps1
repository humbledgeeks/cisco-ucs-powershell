#Requires -Version 5.1
<#
.SYNOPSIS
    Section 10 - Boot-from-SAN for a specific server in a mixed FlexPod
    (some blades boot from SAN, others from local/virtual media).

.DESCRIPTION
    Creates a dedicated hg-esx-bfs-template (updating-template) that is
    identical to hg-esx-template except it uses hg-san-boot as the boot
    policy.  Blades that need to boot from SAN are rebound to this template.

    Boot order in hg-san-boot:
      1. SAN (FC)      - UEFI FC driver enumerates zoned FC targets, boots from LUN 0
      2. Virtual Media - read-only (KVM ISO / recovery fallback)

    IMPORTANT: bootMode must be 'uefi' for B200-M5 blades.  Setting it to
    'legacy' causes the UEFI firmware to drop to the EFI shell with
    "map: No mapping found" because the legacy boot path finds no devices.

    ── PREREQUISITES ────────────────────────────────────────────────────────
    • Section 09 FC zones must be active  (.\09-fc-zoning.ps1 -Enable)
    • Boot LUN created and mapped on ASA A30 for each BFS server
    ─────────────────────────────────────────────────────────────────────────

    ── LUN ID NOTE ──────────────────────────────────────────────────────────
    UCSM 4.2 does not expose boot target WWPN/LUN configuration via the
    XML API (lsbootSanImagePath cannot be added to lsbootSan via API).
    After running this script, add the boot target manually in the GUI:

      UCSM → SAN tab → Policies → Boot Policies → hg-san-boot
        → Edit → Add SAN Boot Target
        → Enter target WWPN and LUN ID for each fabric path

    Or, the simpler fix: in ONTAP System Manager remap the boot LUN to
    LUN ID 0 for each server (Storage → Storage Units → Edit host mapping).
    The UCS BIOS enumerates LUN 0 by default when no target is pinned.
    ─────────────────────────────────────────────────────────────────────────

.PARAMETER BfsServers
    List of service profile names that should boot from SAN.
    Default: @('hg-esx-01')

.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.
    Other blades remain on hg-esx-template / hg-flexflash boot.

.EXAMPLE
    # Migrate hg-esx-01 to SAN boot
    $env:UCSM_PASSWORD = 'YourPassword'
    .\10-boot-from-san.ps1

.EXAMPLE
    # Migrate multiple blades to SAN boot
    .\10-boot-from-san.ps1 -BfsServers hg-esx-01,hg-esx-02
#>
param(
    [string[]]$BfsServers = @('hg-esx-01')
)

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h    = $global:UcsHandle
$org  = 'org-root/org-HumbledGeeks'

Write-Host "`n========== 10 - Boot from SAN ==========" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════════════════════════════
# CREATE hg-san-boot POLICY
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[POLICY] hg-san-boot  (SAN order=1, VirtualMedia order=2)"

$policy = Add-UcsBootPolicy -Ucs $h `
    -OrgDn   $org `
    -Name    'hg-san-boot' `
    -Descr   'FC SAN boot - ASA A30' `
    -EnforceVnicName 'yes' `
    -BootMode 'uefi' `
    -RebootOnUpdate 'no' `
    -ModifyPresent

Add-UcsLsbootSan -Ucs $h -LsbootPolicy $policy -Order 1 -ModifyPresent | Out-Null
Write-Host "  [OK] SAN order=1" -ForegroundColor Green

Add-UcsLsbootVirtualMedia -Ucs $h -LsbootPolicy $policy `
    -Access 'read-only' -Order 2 -ModifyPresent | Out-Null
Write-Host "  [OK] VirtualMedia order=2  (read-only)" -ForegroundColor Green

Write-Host "`n  NOTE: Boot target WWPNs and LUN ID must be added via UCSM GUI:" `
           -ForegroundColor Yellow
Write-Host "  SAN tab -> Policies -> Boot Policies -> hg-san-boot -> Edit" `
           -ForegroundColor Yellow
Write-Host "  -> Add SAN Boot Target -> enter WWPN + LUN ID for each fabric path" `
           -ForegroundColor Yellow

# ══════════════════════════════════════════════════════════════════════════════
# CREATE hg-esx-bfs-template  (clone of hg-esx-template with SAN boot)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[TEMPLATE] Creating hg-esx-bfs-template"

$srcTemplate = Get-UcsServiceProfile -Ucs $h -Name 'hg-esx-template' |
               Where-Object { $_.Dn -like "*$org*" }

$bfsTemplate = Add-UcsServiceProfile -Ucs $h `
    -OrgDn              $org `
    -Name               'hg-esx-bfs-template' `
    -Type               'updating-template' `
    -Descr              'FlexPod ESXi BFS (boot from SAN)' `
    -BootPolicyName     'hg-san-boot' `
    -MaintPolicyName    $srcTemplate.MaintPolicyName `
    -IdentPoolName      $srcTemplate.IdentPoolName `
    -LocalDiskPolicyName $srcTemplate.LocalDiskPolicyName `
    -PowerPolicyName    $srcTemplate.PowerPolicyName `
    -ModifyPresent

Write-Host "  [OK] hg-esx-bfs-template  bootPolicyName=hg-san-boot" -ForegroundColor Green

# Copy all vNIC bindings from the original template
$vNics = Get-UcsVnic -Ucs $h | Where-Object { $_.Dn -like "*ls-hg-esx-template*" }
foreach ($v in $vNics) {
    Add-UcsVnic -Ucs $h -ServiceProfile $bfsTemplate `
        -Name         $v.Name `
        -NwTemplName  $v.NwTemplName `
        -Order        $v.Order `
        -SwitchId     $v.SwitchId `
        -ModifyPresent | Out-Null
    Write-Host "  [vNIC] $($v.Name)  tmpl=$($v.NwTemplName)  sw=$($v.SwitchId)" `
               -ForegroundColor DarkGray
}

# Copy all vHBA bindings
$vHbas = Get-UcsVhba -Ucs $h | Where-Object { $_.Dn -like "*ls-hg-esx-template*" }
foreach ($v in $vHbas) {
    Add-UcsVhba -Ucs $h -ServiceProfile $bfsTemplate `
        -Name         $v.Name `
        -NwTemplName  $v.NwTemplName `
        -Order        $v.Order `
        -SwitchId     $v.SwitchId `
        -ModifyPresent | Out-Null
    Write-Host "  [vHBA] $($v.Name)  tmpl=$($v.NwTemplName)  sw=$($v.SwitchId)" `
               -ForegroundColor DarkGray
}

# ══════════════════════════════════════════════════════════════════════════════
# REBIND SPECIFIED SERVERS TO hg-esx-bfs-template
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[REBIND] Moving servers to BFS template"
foreach ($spName in $BfsServers) {
    $sp = Get-UcsServiceProfile -Ucs $h -Name $spName |
          Where-Object { $_.Dn -like "*$org*" -and $_.Type -eq 'instance' }
    if (-not $sp) {
        Write-Warning "  Service profile '$spName' not found — skipping"
        continue
    }
    Set-UcsServiceProfile -ServiceProfile $sp `
        -SrcTemplName 'hg-esx-bfs-template' -Force | Out-Null
    Write-Host "  [OK] $spName -> hg-esx-bfs-template  (bootPolicy=hg-san-boot)" `
               -ForegroundColor Green
}

# ══════════════════════════════════════════════════════════════════════════════
# VERIFY
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n--- Verification ---" -ForegroundColor Yellow
Get-UcsServiceProfile -Ucs $h |
    Where-Object { $_.Dn -like "*$org*" -and $_.Type -eq 'instance' } |
    Select-Object Name, BootPolicyName, SrcTemplName, AssocState |
    Sort-Object Name | Format-Table -AutoSize

Write-Host "[DONE]`n" -ForegroundColor Green
Write-Host "  ┌─ Next steps:" -ForegroundColor DarkGray
Write-Host "  │  1. Add boot target WWPNs + LUN ID via UCSM GUI (see NOTE above)" -ForegroundColor DarkGray
Write-Host "  │     OR remap boot LUN to LUN ID=0 in ONTAP System Manager" -ForegroundColor DarkGray
Write-Host "  │  2. Power-cycle the blade from UCSM" -ForegroundColor DarkGray
Write-Host "  │  3. Watch KVM console — blade should boot ESXi from SAN" -ForegroundColor DarkGray
Write-Host "  └─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
