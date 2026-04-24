# HumbledGeeks – UCS FlexPod Deployment Scripts

PowerShell automation for building the complete HumbledGeeks Cisco UCS environment
on a **6332-16UP Fabric Interconnect** pair with a **NetApp ASA A30** all-flash
SAN over direct-attach Fibre Channel. Targets an 8-blade VCF 4+4 design
(4 Management Domain blades + 4 VI Workload Domain blades).

---

## Environment

| Item | Value |
| --- | --- |
| UCSM VIP | 10.103.12.20 |
| UCSM version | 4.2(3p) |
| Fabric Interconnects | UCS 6332-16UP (FI-A and FI-B) |
| Chassis | UCS 5108, 8x B200-M4/M5 blades |
| Storage | NetApp ASA A30 (direct-attach FC) |
| PS module | Cisco.UCSManager 3.0.6.18 |
| PowerShell | 7.x (macOS/Linux) or 5.1+ (Windows) |

### FC Cabling (UCS 6332-16UP storage ports 1-2 per FI)

```text
ASA A30 node-1  n1_fc_a_1a  -->  FI-A  storage port 1   (VSAN hg-vsan-a, ID 10)
ASA A30 node-1  n1_fc_b_1d  -->  FI-B  storage port 1   (VSAN hg-vsan-b, ID 11)
ASA A30 node-2  n2_fc_a_1a  -->  FI-A  storage port 2   (VSAN hg-vsan-a, ID 10)
ASA A30 node-2  n2_fc_b_1d  -->  FI-B  storage port 2   (VSAN hg-vsan-b, ID 11)

```

### Ethernet Uplinks

FI-A and FI-B both use ports 11-12 for upstream Ethernet uplinks to the top-of-rack switches.

---

## Prerequisites

### 1. Install the Cisco UCS PowerTool module

```powershell
Install-Module Cisco.UCSManager -Scope CurrentUser -Force

```powershell

**2. Set your UCSM password as an environment variable** (avoids credential prompts on every script)

```powershell
$env:UCSM_PASSWORD = 'YourPassword'

```

If `UCSM_PASSWORD` is not set, each script will prompt interactively via `Get-Credential`.

---

## Running Everything at Once

For a full deployment from scratch:

```powershell

# Optional: wipe any existing HumbledGeeks config first

$env:UCSM_PASSWORD = 'YourPassword'
.\00-wipe.ps1

# Full automated deployment (pauses before blade association for pre-flight check)

.\run-all.ps1

```text

`run-all.ps1` pauses before blade association so you can confirm physical readiness.

**Useful flags:**

```powershell

# Build all config objects but skip blade association (defer physical work)

.\run-all.ps1 -SkipAssociation

# Resume a partial run from a specific section (e.g. after fixing an error in section 4)

.\run-all.ps1 -StartAt 4

```

---

## Running Scripts Individually

Each numbered script dot-sources `00-prereqs-and-connect.ps1` automatically —
just run the section script directly. All scripts are idempotent (`-ModifyPresent`)
and safe to re-run.

---

### `00-prereqs-and-connect.ps1`

Shared connection helper — **not run directly**. Dot-sourced by all other scripts.
Loads the Cisco.UCS module, connects to UCSM, verifies/creates the HumbledGeeks org,
and sets `$global:UcsHandle` and `$global:HgOrg`.

---

### `00-wipe.ps1` — Wipe all HumbledGeeks config

Removes the HumbledGeeks org and all children (pools, policies, templates, service profiles),
stale VLANs, VSANs, and the FC zone profile. Use before a clean rebuild.

```powershell
.\00-wipe.ps1

```text

> **Caution:** Destructive. Port channels and uplink configurations are not touched.

---

### `01-pools.ps1` — Address pools

| Pool | Type | Range | Size |
| --- | --- | --- | --- |
| hg-mac-a | MAC (Fabric A) | 00:25:B5:11:1A:01 – 1C:00 | 512 |
| hg-mac-b | MAC (Fabric B) | 00:25:B5:11:1D:01 – 1F:00 | 512 |
| hg-uuid-pool | UUID suffix | 0025-B50000000001 – A0 | 160 |
| hg-wwnn-pool | WWNN | 20:00:00:25:B5:11:1F:01 – A0 | 160 |
| hg-wwpn-a | WWPN (Fabric A) | 20:00:00:25:B5:11:1A:01 – A0 | 160 |
| hg-wwpn-b | WWPN (Fabric B) | 20:00:00:25:B5:11:1B:01 – A0 | 160 |
| hg-ext-mgmt | IP (KVM mgmt) | 10.103.12.180 – .188 /24 | 9 |

```powershell
.\01-pools.ps1

```

---

### `02-vlans-vsans.ps1` — VLANs and VSANs

**VLANs** (verified/created in global LAN cloud):

| ID | Name | Purpose |
| --- | --- | --- |
| 1 | default | Native/untagged |
| 13 | dc3-iscsi-a | iSCSI (legacy reference) |
| 14 | dc3-iscsi-b | iSCSI (legacy reference) |
| 15 | dc3-nfs | NFS |
| 16 | dc3-mgmt | ESXi management |
| 17 | dc3-vmotion | vMotion |
| 18 | dc3-apps | Application VMs |
| 20 | dc3-core | Core network |
| 22 | dc3-docker | Container workloads |
| 32 | dc3-gns3-mgmt | GNS3 management |
| 34 | dc3-gns3-data | GNS3 data plane |
| 253 | dc3-jumbbox | Overlay workloads |

**VSANs** (created in FC Storage Cloud via XML API):

| Name | ID | FCoE VLAN | Fabric |
| --- | --- | --- | --- |
| hg-vsan-a | 10 | 1010 | A |
| hg-vsan-b | 11 | 1011 | B |

```powershell
.\02-vlans-vsans.ps1

```text

---

### `03-policies.ps1` — Org policies

| Type | Name | Key Settings |
| --- | --- | --- |
| Network Control | hg-netcon | CDP=enabled, LLDP Tx/Rx=enabled, uplink-fail=link-down |
| QoS | hg-qos-be | Best-effort egress, line-rate |
| Local Disk | hg-local-disk | any-configuration, FlexFlash=disabled |
| Power | hg-power | no-cap |
| Maintenance | hg-maint | user-ack required before disruptive changes |
| Boot | hg-flexflash | Legacy DVD/KVM (ESXi install via KVM ISO) |
| BIOS | hg-bios | VT-x enabled, C-states disabled, HPC performance mode |

```powershell
.\03-policies.ps1

```

> **Note:** CDP and LLDP settings are applied via raw XML API (`Invoke-UcsXml`) because
> the Cisco.UCS PowerShell module does not expose those attributes directly.

---

### `04-vnic-templates.ps1` — vNIC templates (Ethernet)

All vNICs use MTU 1500. Block storage runs over FC vHBAs so there is no iSCSI/NFS
on the Ethernet path and jumbo frames are not needed.

| Template | Fabric | Pool | VLANs |
| --- | --- | --- | --- |
| hg-vmnic0 | A | hg-mac-a | default, dc3-mgmt, dc3-vmotion |
| hg-vmnic1 | B | hg-mac-b | default, dc3-mgmt, dc3-vmotion |
| hg-vmnic2 | A | hg-mac-a | default, dc3-apps, dc3-core, dc3-docker, dc3-gns3-mgmt, dc3-gns3-data, dc3-jumbbox |
| hg-vmnic3 | B | hg-mac-b | (same as vmnic2) |
| hg-vmnic4 | A | hg-mac-a | dc3-mgmt (NSX TEP placeholder — update to your TEP VLAN) |
| hg-vmnic5 | B | hg-mac-b | (same as vmnic4) |

```powershell
.\04-vnic-templates.ps1

```text

---

### `05-vhba-templates.ps1` — vHBA templates (Fibre Channel)

| Template | Fabric | Pool | VSAN |
| --- | --- | --- | --- |
| hg-vmhba0 | A | hg-wwpn-a | hg-vsan-a (ID 10) |
| hg-vmhba1 | B | hg-wwpn-b | hg-vsan-b (ID 11) |

```powershell
.\05-vhba-templates.ps1

```

---

### `06-service-profile-template.ps1` — Service profile template

Creates `hg-esx-template` (updating-template) and binds all 6 vNICs (order 1-6),
2 vHBAs (order 7-8), all org policies, and the WWNN pool.

```powershell
.\06-service-profile-template.ps1

```text

---

### `07-deploy-service-profiles.ps1` — Deploy service profiles

Instantiates 8 named service profiles from `hg-esx-template` in unassociated state.

| Profile | Slot | VCF Role |
| --- | --- | --- |
| hg-esx-01 to hg-esx-04 | 1-4 | Management Domain |
| hg-esx-05 to hg-esx-08 | 5-8 | VI Workload Domain |

```powershell
.\07-deploy-service-profiles.ps1

```

---

### `07b-associate-service-profiles.ps1` — Associate blades

Binds the 8 service profiles to physical blades (chassis 1, slots 1-8).
**Run only after blades are seated and FC cables are connected.**

```powershell

# Associate all 8 blades

.\07b-associate-service-profiles.ps1

# Associate only the first N blades (useful for staged rollout)

.\07b-associate-service-profiles.ps1 -DeployCount 1

```text

---

### `09-fc-zoning.ps1` — FC zone profile

Builds 16 single-initiator FC zones (8 blades x 2 fabrics) in zone profile `hg-fc-zones`.
Running without `-Enable` is safe before cabling — the profile is created **disabled**.

```powershell

# Build zones, leave profile disabled (safe pre-cable)

.\09-fc-zoning.ps1

# Activate zones (run after blades are associated and ASA A30 is cabled)

.\09-fc-zoning.ps1 -Enable

```

**Target WWPNs (ASA A30 — from NetApp System Manager):**

| Name | WWPN | Fabric |
| --- | --- | --- |
| asa30-n1-a | 20:17:d0:39:ea:da:44:85 | A |
| asa30-n2-a | 20:19:d0:39:ea:da:44:85 | A |
| asa30-n1-b | 20:18:d0:39:ea:da:44:85 | B |
| asa30-n2-b | 20:1a:d0:39:ea:da:44:85 | B |

**Initiator WWPNs (assigned by UCSM from hg-wwpn-a/b pools):**

| Profile | vmhba0 Fabric A | vmhba1 Fabric B |
| --- | --- | --- |
| hg-esx-01 | 20:00:00:25:B5:11:1A:01 | 20:00:00:25:B5:11:1B:01 |
| hg-esx-02 | 20:00:00:25:B5:11:1A:02 | 20:00:00:25:B5:11:1B:02 |
| hg-esx-03 | 20:00:00:25:B5:11:1A:03 | 20:00:00:25:B5:11:1B:03 |
| hg-esx-04 | 20:00:00:25:B5:11:1A:04 | 20:00:00:25:B5:11:1B:04 |
| hg-esx-05 | 20:00:00:25:B5:11:1A:05 | 20:00:00:25:B5:11:1B:05 |
| hg-esx-06 | 20:00:00:25:B5:11:1A:06 | 20:00:00:25:B5:11:1B:06 |
| hg-esx-07 | 20:00:00:25:B5:11:1A:07 | 20:00:00:25:B5:11:1B:07 |
| hg-esx-08 | 20:00:00:25:B5:11:1A:08 | 20:00:00:25:B5:11:1B:08 |

---

### `10-verify.ps1` — Verification report

Read-only health check. Prints pool utilisation, VLAN/VSAN state, template list,
service profile association states, assigned WWPNs, FC zone profile, active faults,
and uplink port channel status. Safe to run at any time.

```powershell
.\10-verify.ps1

```

---

## Deployment Order (Summary)

```text

[Optional]  .\00-wipe.ps1                         # clean slate rebuild only

            .\01-pools.ps1
            .\02-vlans-vsans.ps1
            .\03-policies.ps1
            .\04-vnic-templates.ps1
            .\05-vhba-templates.ps1
            .\06-service-profile-template.ps1
            .\07-deploy-service-profiles.ps1

 --- Seat blades, connect FC cables to FI storage ports 1-2 ---

            .\07b-associate-service-profiles.ps1
            .\09-fc-zoning.ps1                    # build zones (disabled)
            .\09-fc-zoning.ps1 -Enable            # activate zones

            .\10-verify.ps1                       # confirm health

```

Or use the orchestrator: `.\run-all.ps1`

---

## Known Module Quirks (Cisco.UCSManager 3.0.6.18)

Workarounds for cmdlets that differ from the module docs or earlier versions:

| Issue | Workaround |
| --- | --- |
| `Add-UcsFcpoolInitiators` / `Add-UcsFcpoolBlock` do not exist | Use `Add-UcsManagedObject -ClassId FcpoolInitiators` / `FcpoolBlock` |
| `Add-UcsVlan` fails without a piped parent object | Pipe `Get-UcsManagedObject -ClassId FabricLanCloud` first |
| `Add-UcsVsan -FabricId` is not a valid parameter | Use `Invoke-UcsXml -XmlQuery` with explicit per-fabric DNs |
| `Invoke-UcsXml -Xml` fails with positional parameter error | Use `-XmlQuery` parameter |
| `Set-UcsEgressPolicy` does not exist | Use `Get-UcsChild -ClassId EpqosEgress \| Set-UcsManagedObject` |
| `Add-UcsVhbaTemplate -Target` is not a valid parameter | Remove it — UCSM defaults to `adaptor` |
| `Set-UcsServiceProfile -NodeWwnPoolName` is not valid | Use `Add-UcsManagedObject -ClassId VnicFcNode` child on the SP |
| Custom QoS policy causes `qos-policy-invalid` fault on SP association | Set `QosPolicyName = ''` on vNIC/vHBA templates to use the system default |
| BIOS token values are case-sensitive | Lowercase only: `'enabled'`, `'disabled'`, `'hpc'` |
| `-Descr` rejects em-dashes, en-dashes, `=` and many special chars | UCSM allows only: `a-z A-Z 0-9 space ! # $ % & ( ) * + , - . / : ; ? @ [ ] _ { \| } ~` |
