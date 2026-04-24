#Requires -Version 5.1
<#
.SYNOPSIS
    Section 06 – Service Profile Template (hg-esx-template)
.DESCRIPTION
    Creates the hg-esx-template Updating Service Profile Template and
    binds all vNICs, vHBAs, and policies to it.

    Identity :  UUID pool hg-uuid-pool
                WWNN pool hg-wwnn-pool
    Networking: vmnic0–5 via hg-vmnic0–5 templates
    Storage   : vmhba0–1 via hg-vmhba0–1 templates
    KVM/mgmt  : ext-mgmt IP pool hg-ext-mgmt (pooled)
    Policies  : local disk, power, maintenance, BIOS
.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.
    Sections 01-05 must have been run first (all pools, policies, and
    templates must exist before the SP template can reference them).

    What you may want to adjust for a different deployment:
      - $vnicDefs / $vhbaDefs — add/remove vNIC or vHBA entries, or change
                                 the adapter profile (VMWare is correct for ESXi)
      - -BootPolicyName       — change if you use a different boot policy name
      - -BiosProfileName      — change if you use a different BIOS policy name
      - Adaptor order         — vNICs are order 1-6, vHBAs are order 7-8;
                                 ESXi presents them as vmnic0-5 and vmhba0-1

.EXAMPLE
    # Run standalone
    $env:UCSM_PASSWORD = 'YourPassword'
    .\06-service-profile-template.ps1

.EXAMPLE
    # Part of a full deployment — called automatically by run-all.ps1
    .\run-all.ps1
#>

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h   = $global:UcsHandle
$org = $global:HgOrg

Write-Host "`n========== 06 – Service Profile Template ==========" -ForegroundColor Cyan

# ── Create / update the SP template ──────────────────────────────────────
Write-Host "`n[SP-TEMPL] hg-esx-template"
$sp = Add-UcsServiceProfile -Org $org -Ucs $h `
    -Name                  'hg-esx-template' `
    -Descr                 'ESXi blade template: FlexFlash boot, user-ack maint' `
    -Type                  'updating-template' `
    -IdentPoolName         'hg-uuid-pool' `
    -LocalDiskPolicyName   'hg-local-disk' `
    -BootPolicyName        'hg-flexflash' `
    -PowerPolicyName       'hg-power' `
    -MaintPolicyName       'hg-maint' `
    -BiosProfileName       'hg-bios' `
    -ExtIPState            'pooled' `
    -ExtIPPoolName         'hg-ext-mgmt' `
    -ModifyPresent

# WWNN pool binding
$sp | Set-UcsServiceProfile -Ucs $h `
    -IdentPoolName 'hg-uuid-pool' -Force | Out-Null
# Note: WWNN binding is done via the storage connectivity profile below.

Write-Host "  [OK]   hg-esx-template  (type=updating-template, boot=hg-flexflash, maint=hg-maint)" -ForegroundColor Green

# ── vNIC bindings (order 1–6) ─────────────────────────────────────────────
Write-Host "`n[vNIC] Binding vNICs to template..."
$vnicDefs = @(
    @{ Name='vmnic0'; Templ='hg-vmnic0'; Order=1; Pool='hg-mac-a' },
    @{ Name='vmnic1'; Templ='hg-vmnic1'; Order=2; Pool='hg-mac-b' },
    @{ Name='vmnic2'; Templ='hg-vmnic2'; Order=3; Pool='hg-mac-a' },
    @{ Name='vmnic3'; Templ='hg-vmnic3'; Order=4; Pool='hg-mac-b' },
    @{ Name='vmnic4'; Templ='hg-vmnic4'; Order=5; Pool='hg-mac-a' },
    @{ Name='vmnic5'; Templ='hg-vmnic5'; Order=6; Pool='hg-mac-b' }
)
foreach ($v in $vnicDefs) {
    Add-UcsVnic -ServiceProfile $sp -Ucs $h `
        -Name            $v.Name `
        -NwTemplName     $v.Templ `
        -IdentPoolName   $v.Pool `
        -AdaptorProfileName 'VMWare' `
        -Order           $v.Order `
        -ModifyPresent | Out-Null
    Write-Host "  [OK]   $($v.Name)  templ=$($v.Templ)  order=$($v.Order)" -ForegroundColor Green
}

# ── vHBA bindings (order 7–8) ─────────────────────────────────────────────
Write-Host "`n[vHBA] Binding vHBAs to template..."
$vhbaDefs = @(
    @{ Name='vmhba0'; Templ='hg-vmhba0'; Order=7; Pool='hg-wwpn-a' },
    @{ Name='vmhba1'; Templ='hg-vmhba1'; Order=8; Pool='hg-wwpn-b' }
)
foreach ($v in $vhbaDefs) {
    Add-UcsVhba -ServiceProfile $sp -Ucs $h `
        -Name            $v.Name `
        -NwTemplName     $v.Templ `
        -IdentPoolName   $v.Pool `
        -AdaptorProfileName 'VMWare' `
        -Order           $v.Order `
        -ModifyPresent | Out-Null
    Write-Host "  [OK]   $($v.Name)  templ=$($v.Templ)  order=$($v.Order)" -ForegroundColor Green
}

# ── WWNN pool (identity) ──────────────────────────────────────────────────
Write-Host "`n[WWNN] Binding WWNN pool..."
# The WWNN pool is set on the storage profile or directly on the SP
$fcNode = $sp | Get-UcsChild -ClassId 'VnicFcNode' -Ucs $h
if ($fcNode) {
    $fcNode | Set-UcsManagedObject -Ucs $h -PropertyMap @{ IdentPoolName = 'hg-wwnn-pool' } -Force | Out-Null
} else {
    $sp | Add-UcsManagedObject -Ucs $h -ClassId 'VnicFcNode' `
        -PropertyMap @{ IdentPoolName = 'hg-wwnn-pool' } | Out-Null
}
Write-Host "  [OK]   WWNN pool = hg-wwnn-pool" -ForegroundColor Green

Write-Host "`n[DONE] Section 06 – Service Profile Template complete.`n" -ForegroundColor Green
