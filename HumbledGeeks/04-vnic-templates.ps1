#Requires -Version 5.1
<#
.SYNOPSIS
    Section 04 – vNIC templates (Ethernet)
.DESCRIPTION
    Creates six Updating-Template vNIC templates for a six-vNIC VMware ESXi / VCF
    design targeting a NetApp FlexPod with direct-attached ASA A30 (FC storage).
    All Ethernet interfaces use MTU 1500 — jumbo frames are not required here because
    block storage runs over Fibre Channel vHBAs, and MTU 1500 avoids fragmentation
    risk on any path that might not be uniformly jumbo-enabled.

    Fabric A and B are mirrored for active-active redundancy:

    vmnic0 (A) / vmnic1 (B)  MTU 1500  – ESXi Management + vMotion
    vmnic2 (A) / vmnic3 (B)  MTU 1500  – VM workloads trunk (apps/core/docker/gns3)
    vmnic4 (A) / vmnic5 (B)  MTU 1500  – VCF overlay / NSX TEP (dedicated path)

    Block storage (NetApp ASA A30) is accessed exclusively via the FC vHBAs
    defined in 05-vhba-templates.ps1 — no iSCSI or NFS paths needed.

    Each template is bound to the hg-netcon network control policy and the
    appropriate MAC pool (hg-mac-a for A-side, hg-mac-b for B-side).
.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.
    Sections 01-03 must have been run first (pools and policies must exist).

    What you may want to adjust for a different deployment:
      - $mgmtVlans      — add/remove VLANs carried on vmnic0/1 (management path)
      - $workloadVlans  — add/remove VLANs on the vmnic2/3 workload trunk
      - $vcfOverlayVlans — replace dc3-mgmt placeholder with your actual NSX
                           TEP VLAN before deploying NSX
      - MTU             — all templates use 1500; increase if your network supports
                           jumbo frames and you add NFS/iSCSI vNICs

.EXAMPLE
    # Run standalone
    $env:UCSM_PASSWORD = 'YourPassword'
    .\04-vnic-templates.ps1

.EXAMPLE
    # Part of a full deployment — called automatically by run-all.ps1
    .\run-all.ps1
#>

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h   = $global:UcsHandle
$org = $global:HgOrg

Write-Host "`n========== 04 – vNIC Templates ==========" -ForegroundColor Cyan

function New-HgVnicTemplate {
    param(
        [string]$Name,
        [string]$Fabric,
        [string]$MacPool,
        [int]   $Mtu,
        [string]$Descr,
        [hashtable[]]$Vlans
    )
    Write-Host "`n[vNIC] $Name  fabric=$Fabric  mtu=$Mtu"
    $t = Add-UcsVnicTemplate -Org $org -Ucs $h `
        -Name              $Name `
        -Descr             $Descr `
        -SwitchId          $Fabric `
        -TemplType         'updating-template' `
        -IdentPoolName     $MacPool `
        -Mtu               $Mtu `
        -NwCtrlPolicyName  'hg-netcon' `
        -StatsPolicyName   'default' `
        -QosPolicyName     '' `
        -Target            'adaptor' `
        -ModifyPresent

    foreach ($v in $Vlans) {
        Add-UcsVnicInterface -VnicTemplate $t -Ucs $h `
            -Name       $v.Name `
            -DefaultNet $v.Default `
            -ModifyPresent | Out-Null
    }
    Write-Host "  [OK]   $Name  VLANs: $(($Vlans | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Green
}

# ── vmnic0 / vmnic1 — ESXi Management + vMotion (MTU 1500) ────────────────
# Carries vmk0 (ESXi management) and vmk1 (vMotion).
# VCF uses this path for host management and cluster vMotion traffic.
$mgmtVlans = @(
    @{ Name = 'default';     Default = 'yes' }   # VLAN  1 — native/untagged
    @{ Name = 'dc3-mgmt';    Default = 'no'  }   # VLAN 16 — ESXi management
    @{ Name = 'dc3-vmotion'; Default = 'no'  }   # VLAN 17 — vMotion
)
New-HgVnicTemplate -Name 'hg-vmnic0' -Fabric 'A' -MacPool 'hg-mac-a' -Mtu 1500 `
    -Descr 'FlexPod vmnic0 Fabric-A ESXi mgmt+vMotion MTU1500' `
    -Vlans $mgmtVlans
New-HgVnicTemplate -Name 'hg-vmnic1' -Fabric 'B' -MacPool 'hg-mac-b' -Mtu 1500 `
    -Descr 'FlexPod vmnic1 Fabric-B ESXi mgmt+vMotion MTU1500' `
    -Vlans $mgmtVlans

# ── vmnic2 / vmnic3 — VM Workloads trunk (MTU 1500) ───────────────────────
# Carries all guest VM traffic. MTU 1500 is used throughout this design to
# avoid fragmentation — no jumbo frames are required since block storage runs
# over FC vHBAs and is completely off the Ethernet data path.
$workloadVlans = @(
    @{ Name = 'default';       Default = 'yes' }  # VLAN   1 — native
    @{ Name = 'dc3-apps';      Default = 'no'  }  # VLAN  18 — application VMs
    @{ Name = 'dc3-core';      Default = 'no'  }  # VLAN  20 — core network
    @{ Name = 'dc3-docker';    Default = 'no'  }  # VLAN  22 — container workloads
    @{ Name = 'dc3-gns3-mgmt'; Default = 'no'  }  # VLAN  32 — GNS3 management
    @{ Name = 'dc3-gns3-data'; Default = 'no'  }  # VLAN  34 — GNS3 data plane
    @{ Name = 'dc3-jumbbox';   Default = 'no'  }  # VLAN 253 — overlay workloads
)
New-HgVnicTemplate -Name 'hg-vmnic2' -Fabric 'A' -MacPool 'hg-mac-a' -Mtu 1500 `
    -Descr 'FlexPod vmnic2 Fabric-A VM workloads trunk MTU1500' `
    -Vlans $workloadVlans
New-HgVnicTemplate -Name 'hg-vmnic3' -Fabric 'B' -MacPool 'hg-mac-b' -Mtu 1500 `
    -Descr 'FlexPod vmnic3 Fabric-B VM workloads trunk MTU1500' `
    -Vlans $workloadVlans

# ── vmnic4 / vmnic5 — VCF Overlay / NSX TEP (MTU 1500) ───────────────────
# Dedicated path for VCF/NSX Tunnel Endpoint (TEP) overlay encapsulation.
# Isolating TEP traffic onto its own vNIC pair keeps overlay encapsulation
# off the VM workload path and simplifies NSX transport zone configuration.
# MTU 1500 is intentional — avoids the need to validate jumbo-frame
# consistency across every switch in the TEP path.
#
# NOTE: If this host will be part of a VCF management domain using vSAN,
# repurpose this vNIC pair for vSAN VMkernel traffic instead.
$vcfOverlayVlans = @(
    @{ Name = 'dc3-mgmt'; Default = 'yes' }  # VLAN 16 — placeholder; set to your NSX TEP VLAN
)
New-HgVnicTemplate -Name 'hg-vmnic4' -Fabric 'A' -MacPool 'hg-mac-a' -Mtu 1500 `
    -Descr 'FlexPod vmnic4 Fabric-A VCF overlay NSX TEP MTU1500' `
    -Vlans $vcfOverlayVlans
New-HgVnicTemplate -Name 'hg-vmnic5' -Fabric 'B' -MacPool 'hg-mac-b' -Mtu 1500 `
    -Descr 'FlexPod vmnic5 Fabric-B VCF overlay NSX TEP MTU1500' `
    -Vlans $vcfOverlayVlans

Write-Host "`n[DONE] Section 04 – vNIC Templates complete.`n" -ForegroundColor Green
