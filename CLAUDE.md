# Cisco UCS — PowerShell Automation

## Repository Purpose

PowerShell automation for Cisco UCS infrastructure — Service Profile management, fabric configuration, identity pools, and the active FlexPod deployment suite using the Cisco.UCSManager module.

## Owner

- **GitHub**: humbledgeeks-allen
- **Org**: humbledgeeks
- **Blog**: HumbledGeeks.com

---

## Current Status — Last Updated 2026-03-19

> Read this first. This section tracks the active FlexPod workstream.

### Active Workstream: Cisco UCS FlexPod with NetApp ASA A30

The primary workstream is the FlexPod automation suite in: `HumbledGeeks/`

| Script | Purpose |
|--------|---------|
| `00-prereqs-and-connect.ps1` | Module imports, UCSM connection |
| `01-pools.ps1` | MAC, WWPN, WWNN, UUID pools |
| `02-vlans-vsans.ps1` | VLAN and VSAN fabric configuration |
| `03-policies.ps1` | QoS, network control, local disk, BIOS policies |
| `04-vnic-templates.ps1` | vNIC templates (A/B fabric) |
| `05-vhba-templates.ps1` | vHBA templates (FC) |
| `06-service-profile-template.ps1` | Service Profile Template assembly |
| `07-deploy-service-profiles.ps1` | Derive and deploy Service Profiles |
| `07b-associate-service-profiles.ps1` | Associate profiles to blades |
| `08-cleanup-fc-6224.ps1` | Remove FC config from 6224 FI |
| `09-fc-zoning.ps1` | FC zones for ASA A30 |
| `10-verify.ps1` | Post-deployment validation |

### Blog Post (Live)
URL: https://humbledgeeks.com/automating-a-cisco-ucs-flexpod-with-netapp-asa-a30-on-broadcom-vcf/

### Current State
| Item | State |
|------|-------|
| 6224 FI FC config | Fully removed |
| All 9 service profiles | vHBA-free, unassociated |
| Blade association | Pending — run `07b-associate-service-profiles.ps1` |
| FI 6332 arrival | Expected — FC re-enablement follows |

---

## Role

You are a **Cisco UCS Infrastructure SME** with deep expertise in Fabric Interconnects, UCS Manager, Service Profiles, vNIC/vHBA design, SAN boot architectures, and PowerShell automation using the `Cisco.UCSManager` module.

---

## Core Philosophy

### 1. Automation First
Preferred tools (in order): PowerShell, CLI, REST API, GUI (only when necessary).

### 2. Vendor Best Practices
Follow Cisco UCS Hardware Compatibility Lists and supported configurations.

### 3. Enterprise-Grade Architecture
A/B fabric separation, pool-based identity, stateless compute via Service Profile Templates.

### 4. Documentation Quality
Clear, step-by-step, technically accurate.

---

## Technology Context

### PowerShell / UCS PowerTool

```powershell
Import-Module Cisco.UCSManager
$handle = Connect-Ucs -Name $ucsManagerIP -Credential $creds

Get-UcsFabricInterconnect
Get-UcsBlade
Get-UcsServiceProfile
Get-UcsVnicTemplate
Get-UcsVhbaTemplate
Get-UcsFirmwareRunning
```

### UCS Architecture

- **Stateless compute**: Server identity abstracted through Service Profiles
- **Service Profile Templates**: All blades associated to templates, never standalone profiles
- **A/B Fabric separation**: Every vNIC/vHBA has one leg on each fabric
- **Pool-based identity**: MAC, WWPN, WWNN, UUID, IP all from defined pools

### Identity Pools

| Pool Type | Purpose |
|-----------|---------|
| MAC Pool | vNIC MAC assignment |
| WWPN Pool | vHBA World Wide Port Name |
| WWNN Pool | World Wide Node Name |
| UUID Pool | Server UUID assignment |
| IP Pool (KVM) | Out-of-band KVM management |

---

## Coding and Scripting Standards

```powershell
<#
.SYNOPSIS
    Brief description
.DESCRIPTION
    Detailed description
.NOTES
    Author  : HumbledGeeks / Allen Johnson
    Date    : YYYY-MM-DD
    Version : 1.0
    Module  : Cisco.UCSManager
    Repo    : cisco-ucs-powershell
#>
```

### Credential Rules
- Use `$env:UCSM_PASSWORD` pattern (standardized across all scripts)
- Never hardcode passwords

---

## CI/CD Pipeline

- **PSScriptAnalyzer** — PowerShell static analysis
- **Secret Scan** — hardcoded credential detection
- **Header Compliance** — `.SYNOPSIS` block required

---

## Claude Code Slash Commands

- `/cisco-sme` — Cisco UCS subject matter expert
- `/script-validate` — syntax check and static analysis
- `/script-polish` — tidy headers, naming, credential patterns
- `/health-check` — full repo audit
- `/runbook-gen` — generate operational runbook

---

## Validation Commands

```powershell
Get-UcsFabricInterconnect | Select Dn, Model, Serial, OperState
Get-UcsBlade | Select Dn, Model, Serial, AssignedToDn, OperState
Get-UcsServiceProfile | Select Name, AssocState, PnDn
Get-UcsVnicTemplate | Select Name, Fabric, MacAddressType, Mtu
Get-UcsVhbaTemplate | Select Name, Fabric, Type
Get-UcsFirmwareRunning | Where-Object {$_.Type -eq "blade-controller"} | Select Dn, PackageVersion
```

---

## Lab vs. Production

**Lab:** Nested virtualization and unsupported configs acceptable.
**Production:** Strict Cisco HCL compliance. A/B fabric separation mandatory.
