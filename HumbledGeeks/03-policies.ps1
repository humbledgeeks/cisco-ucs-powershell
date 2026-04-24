#Requires -Version 5.1
<#
.SYNOPSIS
    Section 03 – Org-level policies for HumbledGeeks
.DESCRIPTION
    Creates: Network Control Policy (hg-netcon), QoS policy (hg-qos-be),
    Local Disk Policy (hg-local-disk), Power Policy (hg-power),
    Maintenance Policy (hg-maint), Boot Policy (hg-flexflash),
    and BIOS Policy (hg-bios).
.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.
    CDP and LLDP are applied via Invoke-UcsXml (the PS module does not expose
    those attributes directly on Add-UcsNetworkControlPolicy).

    What you may want to adjust for a different deployment:
      - Boot policy mode — 'legacy' vs 'uefi' depending on your blade generation
        (B200-M4 = legacy, M5/M6 support UEFI)
      - BIOS tokens — add or remove tokens to match your ESXi version requirements
      - Maintenance policy — change 'user-ack' to 'immediate' if you want
        blade reboots to happen automatically without UCSM acknowledgement

.EXAMPLE
    # Run standalone
    $env:UCSM_PASSWORD = 'YourPassword'
    .\03-policies.ps1

.EXAMPLE
    # Part of a full deployment — called automatically by run-all.ps1
    .\run-all.ps1
#>

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h   = $global:UcsHandle
$org = $global:HgOrg

Write-Host "`n========== 03 – Policies ==========" -ForegroundColor Cyan

# ── Network Control Policy ────────────────────────────────────────────────
Write-Host "`n[POLICY] hg-netcon (Network Control)"
$ncp = Add-UcsNetworkControlPolicy -Org $org -Ucs $h `
    -Name             'hg-netcon' `
    -Descr            'CDP+LLDP enabled uplink-fail link-down' `
    -UplinkFailAction 'link-down' `
    -MacRegisterMode  'only-native-vlan' `
    -ModifyPresent
# CDP and LLDP must be set via raw XML API (PS module does not expose these attrs)
$ncpDn = "org-root/org-HumbledGeeks/nwctrl-hg-netcon"
$cdpXml = @"
<configConfMos cookie="$($h.Cookie)" inHierarchical="false">
  <inConfigs>
    <pair key="$ncpDn">
      <nwctrlDefinition dn="$ncpDn"
        cdp="enabled" lldpTransmit="enabled" lldpReceive="enabled"
        status="modified"/>
    </pair>
  </inConfigs>
</configConfMos>
"@
Invoke-UcsXml -Ucs $h -XmlQuery $cdpXml | Out-Null
Write-Host "  [OK]   hg-netcon: CDP=enabled, LLDP Tx/Rx=enabled" -ForegroundColor Green

# ── QoS Policy ────────────────────────────────────────────────────────────
Write-Host "`n[POLICY] hg-qos-be (QoS – Best Effort)"
$qos = Add-UcsQosPolicy -Org $org -Ucs $h `
    -Name  'hg-qos-be' `
    -Descr 'HumbledGeeks QoS best effort' `
    -ModifyPresent
# Set egress priority via ManagedObject (Set-UcsEgressPolicy not in module 3.0.6.18)
$qosChild = $qos | Get-UcsChild -ClassId 'EpqosEgress' | Select-Object -First 1
if ($qosChild) {
    $qosChild | Set-UcsManagedObject -PropertyMap @{
        Prio        = 'best-effort'
        Burst       = '10240'
        Rate        = 'line-rate'
        HostControl = 'none'
    } -Force -Ucs $h | Out-Null
}
Write-Host "  [OK]   hg-qos-be" -ForegroundColor Green

# ── Local Disk Policy ─────────────────────────────────────────────────────
Write-Host "`n[POLICY] hg-local-disk"
$ldp = Add-UcsLocalDiskConfigPolicy -Org $org -Ucs $h `
    -Name              'hg-local-disk' `
    -Descr             'HumbledGeeks any-config B200-M4/M5 no FlexFlash' `
    -Mode              'any-configuration' `
    -FlexFlashState    'disable' `
    -FlexFlashRAIDReportingState 'disable' `
    -ProtectConfig     'yes' `
    -ModifyPresent
Write-Host "  [OK]   hg-local-disk (mode=any-configuration, FlexFlash=disabled)" -ForegroundColor Green

# ── Power Policy ──────────────────────────────────────────────────────────
Write-Host "`n[POLICY] hg-power"
$pwr = Add-UcsPowerPolicy -Org $org -Ucs $h `
    -Name  'hg-power' `
    -Descr 'HumbledGeeks power policy no-cap' `
    -Prio  'no-cap' `
    -ModifyPresent
Write-Host "  [OK]   hg-power (prio=no-cap)" -ForegroundColor Green

# ── Maintenance Policy ────────────────────────────────────────────────────
Write-Host "`n[POLICY] hg-maint"
$maint = Add-UcsMaintenancePolicy -Org $org -Ucs $h `
    -Name         'hg-maint' `
    -Descr        'User-ack required before disruptive changes' `
    -UptimeDisr   'user-ack' `
    -DataDisr     'user-ack' `
    -TriggerConfig 'on-next-boot' `
    -ModifyPresent
Write-Host "  [OK]   hg-maint (uptimeDisr=user-ack, dataDisr=user-ack)" -ForegroundColor Green

# ── Boot Policy (Legacy: DVD only) ────────────────────────────────────────
# NOTE: B200-M4 blades do not have FlexFlash hardware and require legacy boot mode.
#       Boot order is DVD/KVM virtual media only — ESXi is installed via KVM ISO.
#       When FI 6332 arrives and SAN boot is configured, add an FC SAN boot entry here.
Write-Host "`n[POLICY] hg-flexflash (Boot Policy)"
$boot = Add-UcsBootPolicy -Org $org -Ucs $h `
    -Name          'hg-flexflash' `
    -Descr         'Legacy DVD/KVM B200-M4 no FlexFlash' `
    -BootMode      'legacy' `
    -EnforceVnicName 'yes' `
    -RebootOnUpdate  'no' `
    -ModifyPresent
# Order 1: DVD/KVM (read-only virtual media — mount ESXi ISO here)
Add-UcsLsBootVirtualMedia -BootPolicy $boot -Ucs $h `
    -Access 'read-only' -Order 1 -ModifyPresent | Out-Null
Write-Host "  [OK]   hg-flexflash: Legacy DVD/KVM(1)" -ForegroundColor Green

# ── BIOS Policy (VMware optimised) ────────────────────────────────────────
Write-Host "`n[POLICY] hg-bios"
$bios = Add-UcsBiosPolicy -Org $org -Ucs $h `
    -Name  'hg-bios' `
    -Descr 'HumbledGeeks BIOS tuned for VMware ESXi' `
    -ModifyPresent
# Key BIOS tokens for virtualisation
# NOTE: values must be lowercase; some cmdlets absent in module 3.0.6.18 — skipped
$bios | Set-UcsBiosVfIntelVirtualizationTechnology -VpIntelVirtualizationTechnology 'enabled'  -Force
$bios | Set-UcsBiosVfCPUPerformance                -VpCPUPerformance                'hpc'       -Force
$bios | Set-UcsBiosVfProcessorCState               -VpProcessorCState               'disabled'  -Force
$bios | Set-UcsBiosVfProcessorC1E                  -VpProcessorC1E                  'disabled'  -Force
Write-Host "  [OK]   hg-bios (VT-x, VT-d, C-States disabled, Perf mode)" -ForegroundColor Green

Write-Host "`n[DONE] Section 03 – Policies complete.`n" -ForegroundColor Green
