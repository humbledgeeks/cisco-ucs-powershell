#Requires -Version 5.1
<#
.SYNOPSIS
    Section 05 – vHBA templates (Fibre Channel)
.DESCRIPTION
    Creates two Updating-Template vHBA templates:
      hg-vmhba0  Fabric A  WWPN pool hg-wwpn-a  VSAN hg-vsan-a (ID 10)
      hg-vmhba1  Fabric B  WWPN pool hg-wwpn-b  VSAN hg-vsan-b (ID 11)

    Both are bound to the VMWare adapter policy for ESXi HBA optimisation.
.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.
    Section 02 (VSANs) and 01 (WWPN pools) must have been run first.

    What you may want to adjust for a different deployment:
      - -Vsan parameter  — must match the VSAN names created in 02-vlans-vsans.ps1
      - -WwpnPool        — must match the pool names created in 01-pools.ps1
      - -MaxDataFieldSize — 2048 is standard for FC; increase to 8192 for
                            FCoE if required by your storage array

.EXAMPLE
    # Run standalone
    $env:UCSM_PASSWORD = 'YourPassword'
    .\05-vhba-templates.ps1

.EXAMPLE
    # Part of a full deployment — called automatically by run-all.ps1
    .\run-all.ps1
#>

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h   = $global:UcsHandle
$org = $global:HgOrg

Write-Host "`n========== 05 – vHBA Templates ==========" -ForegroundColor Cyan

function New-HgVhbaTemplate {
    param(
        [string]$Name,
        [string]$Fabric,
        [string]$WwpnPool,
        [string]$Vsan,
        [string]$Descr
    )
    Write-Host "`n[vHBA] $Name  fabric=$Fabric  pool=$WwpnPool  vsan=$Vsan"
    $t = Add-UcsVhbaTemplate -Org $org -Ucs $h `
        -Name               $Name `
        -Descr              $Descr `
        -SwitchId           $Fabric `
        -TemplType          'updating-template' `
        -IdentPoolName      $WwpnPool `
        -MaxDataFieldSize   2048 `
        -QosPolicyName      '' `
        -StatsPolicyName    'default' `
        -ModifyPresent

    # Bind VSAN via vnicFcIf child
    Add-UcsVhbaInterface -VhbaTemplate $t -Ucs $h `
        -Name       $Vsan `
        -ModifyPresent | Out-Null

    Write-Host "  [OK]   $Name  VSAN=$Vsan" -ForegroundColor Green
}

New-HgVhbaTemplate -Name 'hg-vmhba0' -Fabric 'A' `
    -WwpnPool 'hg-wwpn-a' -Vsan 'hg-vsan-a' `
    -Descr    'HumbledGeeks vmhba0 Fabric-A VSAN-10'

New-HgVhbaTemplate -Name 'hg-vmhba1' -Fabric 'B' `
    -WwpnPool 'hg-wwpn-b' -Vsan 'hg-vsan-b' `
    -Descr    'HumbledGeeks vmhba1 Fabric-B VSAN-11'

Write-Host "`n[DONE] Section 05 – vHBA Templates complete.`n" -ForegroundColor Green
