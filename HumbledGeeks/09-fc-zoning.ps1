#Requires -Version 5.1
<#
.SYNOPSIS
    Section 09 – FC Zone Profile and single-initiator zones for FlexPod ASA A30.

.DESCRIPTION
    Pre-builds all 16 FC zones (8 blades × 2 fabrics) in UCSM using single-initiator
    zoning — the FlexPod best practice. Each zone contains exactly one ESXi initiator
    WWPN and all ASA A30 target WWPNs for that fabric.

    ── ROOT CAUSE & FIX (discovered during 2026-04 re-deployment) ──────────────
    UCSM zones will show  configState=not-applied / operState=not-active  even
    when the zone profile, zones, and endpoints are all correctly defined.
    The missing piece is TWO things that are NOT created by Add-UcsFabricFcUserZone:

      1.  Storage VSANs under fabric/fc-estc
          UCSM needs matching fabricVsan objects (id=10, id=11) under the Storage
          Cloud (fabric/fc-estc).  These must share the same FCoE VLAN IDs as the
          server-side VSANs so the FI can bridge server vHBA traffic to storage ports.
            fabric/fc-estc/net-hg-vsan-a  id=10  fcoeVlan=1010  (Fabric A)
            fabric/fc-estc/net-hg-vsan-b  id=11  fcoeVlan=1011  (Fabric B)
          The fcoeVlan values must match the fcoeVlan on the server-side VSANs
          (fabric/san/A/net-hg-vsan-a / fabric/san/B/net-hg-vsan-b) — verify with:
            Get-UcsVlan -Ucs $h | Where-Object { $_.Id -in 1010,1011 }

      2.  storageVsanRef child inside every fabricFcUserZone
          Each zone needs a storageVsanRef object (RN = vsan-ref) referencing the
          storage VSAN by name.  This is the binding that tells UCSM which VSAN to
          push the zone into and causes the zone to transition to applied/active.
          Without it, zones stay permanently at configState=not-applied id=0.
          The UCSM GUI sets this automatically when you pick a VSAN from the dropdown
          — but the PowerShell cmdlet Add-UcsFabricFcUserZone does NOT.

          The -Enable switch below handles both of these steps.
    ────────────────────────────────────────────────────────────────────────────

    All WWPNs are hard-coded from values known before the ASA A30 is cabled:
      • Initiator WWPNs  — assigned by UCSM from hg-wwpn-a/b pools at SP creation
      • Target WWPNs     — pulled from NetApp System Manager FC port screen

    Zone profile is created with AdminState = DISABLED so this script is safe to
    run before the ASA A30 is physically connected.  Nothing activates until you
    run:   .\09-fc-zoning.ps1 -Enable

    ASSUMED CABLING (UCS 6332-16UP — FC storage ports 1–2 per FI):
      ASA A30 node-1 port n1_fc_a_1a  →  FI-A storage port 1   (Fabric A)
      ASA A30 node-1 port n1_fc_b_1d  →  FI-B storage port 1   (Fabric B)
      ASA A30 node-2 port n2_fc_a_1a  →  FI-A storage port 2   (Fabric A)
      ASA A30 node-2 port n2_fc_b_1d  →  FI-B storage port 2   (Fabric B)

.PARAMETER Enable
    Completes the three activation steps:
      1. Creates storage-cloud VSANs 10 and 11 under fabric/fc-estc
      2. Reassigns FC storage ports from VSAN 1 to the correct per-fabric VSANs
      3. Adds storageVsanRef to every zone (this is what makes zones go active)
      4. Sets zone profile AdminState to 'enabled'
    Run ONLY after the ASA A30 is physically cabled and blade profiles are associated.

.PARAMETER FcoeVlanA
    FCoE VLAN ID assigned to server-side VSAN A (default 1010).
    Must match the fcoeVlan on fabric/san/A/net-hg-vsan-a.

.PARAMETER FcoeVlanB
    FCoE VLAN ID assigned to server-side VSAN B (default 1011).
    Must match the fcoeVlan on fabric/san/B/net-hg-vsan-b.

.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.
    Section 07 must have been run first so vHBA WWPNs are already assigned.

    ── WHAT TO CHANGE FOR A DIFFERENT DEPLOYMENT ──────────────────────────
    1. $fabricATargets / $fabricBTargets  — replace with your storage WWPNs
    2. $initiators table                  — replace with your SP initiator WWPNs
    3. $FcoeVlanA / $FcoeVlanB params     — must match server-side VSAN fcoeVlan
    4. $vsanIdA / $vsanIdB                — VSAN IDs (default 10 and 11)
    ────────────────────────────────────────────────────────────────────────

.EXAMPLE
    # Build all 16 zones (zone profile DISABLED — safe pre-cable)
    $env:UCSM_PASSWORD = 'YourPassword'
    .\09-fc-zoning.ps1

.EXAMPLE
    # Activate zones after ASA A30 is cabled and blades are associated
    $env:UCSM_PASSWORD = 'YourPassword'
    .\09-fc-zoning.ps1 -Enable
#>
param(
    [switch]$Enable,
    [int]$FcoeVlanA = 1010,   # must match server-side fabric/san/A VSAN fcoeVlan
    [int]$FcoeVlanB = 1011,   # must match server-side fabric/san/B VSAN fcoeVlan
    [int]$VsanIdA   = 10,
    [int]$VsanIdB   = 11
)

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h = $global:UcsHandle

Write-Host "`n========== 09 – FC Zoning ==========" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════════════════════════════
# HELPER — direct XML API call (needed for storageVsanRef which has no cmdlet)
# ══════════════════════════════════════════════════════════════════════════════
function Invoke-UcsmXml {
    param([string]$Xml)
    $uri = "https://$($h.Ucs)/nuova"
    try {
        # PowerShell 6+ supports -SkipCertificateCheck
        $r = Invoke-RestMethod -Uri $uri -Method POST -Body $Xml `
             -ContentType 'application/xml' -SkipCertificateCheck -ErrorAction Stop
    } catch {
        # PS 5.1 fallback — trust all certs for self-signed UCSM cert
        if (-not ([System.Management.Automation.PSTypeName]'TrustAll').Type) {
            Add-Type @'
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAll : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert,
        WebRequest req, int problem) { return true; } }
'@
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll
        }
        $r = Invoke-RestMethod -Uri $uri -Method POST -Body $Xml -ContentType 'application/xml'
    }
    return $r
}

function Get-UcsmCookie { return $h.SessionId }

# ══════════════════════════════════════════════════════════════════════════════
# WWPN TABLES
# ══════════════════════════════════════════════════════════════════════════════
# ── ASA A30 Target WWPNs ─────────────────────────────────────────────────────
$fabricATargets = @(
    @{ Name = 'asa30-n1-a'; Wwpn = '20:17:d0:39:ea:da:44:85' },   # node-1 n1_fc_a_1a → FI-A port 1
    @{ Name = 'asa30-n2-a'; Wwpn = '20:19:d0:39:ea:da:44:85' }    # node-2 n2_fc_a_1a → FI-A port 2
)
$fabricBTargets = @(
    @{ Name = 'asa30-n1-b'; Wwpn = '20:18:d0:39:ea:da:44:85' },   # node-1 n1_fc_b_1d → FI-B port 1
    @{ Name = 'asa30-n2-b'; Wwpn = '20:1a:d0:39:ea:da:44:85' }    # node-2 n2_fc_b_1d → FI-B port 2
)

# ── ESXi Initiator WWPNs ─────────────────────────────────────────────────────
$initiators = @(
    @{ Sp='hg-esx-01'; FabA='20:00:00:25:B5:11:1A:01'; FabB='20:00:00:25:B5:11:1B:01' },
    @{ Sp='hg-esx-02'; FabA='20:00:00:25:B5:11:1A:02'; FabB='20:00:00:25:B5:11:1B:02' },
    @{ Sp='hg-esx-03'; FabA='20:00:00:25:B5:11:1A:03'; FabB='20:00:00:25:B5:11:1B:03' },
    @{ Sp='hg-esx-04'; FabA='20:00:00:25:B5:11:1A:04'; FabB='20:00:00:25:B5:11:1B:04' },
    @{ Sp='hg-esx-05'; FabA='20:00:00:25:B5:11:1A:05'; FabB='20:00:00:25:B5:11:1B:05' },
    @{ Sp='hg-esx-06'; FabA='20:00:00:25:B5:11:1A:06'; FabB='20:00:00:25:B5:11:1B:06' },
    @{ Sp='hg-esx-07'; FabA='20:00:00:25:B5:11:1A:07'; FabB='20:00:00:25:B5:11:1B:07' },
    @{ Sp='hg-esx-08'; FabA='20:00:00:25:B5:11:1A:08'; FabB='20:00:00:25:B5:11:1B:08' }
)

# ══════════════════════════════════════════════════════════════════════════════
# ENABLE MODE  (-Enable switch)
# Creates storage-cloud VSANs, reassigns FC ports, binds zones to VSANs,
# then sets the zone profile to AdminState=enabled.
# ══════════════════════════════════════════════════════════════════════════════
if ($Enable) {
    Write-Host "`n[ENABLE] Activating FC zones — 3-step process" -ForegroundColor Yellow
    Write-Host "         Pre-flight: ASA A30 cabled? Blade profiles associated? [y/N] " `
               -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -notmatch '^[Yy]') { Write-Host "Aborted."; exit 0 }

    $cookie = Get-UcsmCookie

    # ── Step 1: Create storage-cloud VSANs 10 and 11 ─────────────────────────
    # These fabricVsan objects under fabric/fc-estc must share the same fcoeVlan
    # as the server-side VSANs so the FI can bridge server↔storage FC traffic.
    # ifRole and switchId are admin-implicit — UCSM sets them automatically.
    Write-Host "`n  [1/3] Creating storage-cloud VSANs" -ForegroundColor Cyan

    foreach ($cfg in @(
        @{ Dn='fabric/fc-estc/net-hg-vsan-a'; Name='hg-vsan-a'; Id=$VsanIdA; FcoeVlan=$FcoeVlanA },
        @{ Dn='fabric/fc-estc/net-hg-vsan-b'; Name='hg-vsan-b'; Id=$VsanIdB; FcoeVlan=$FcoeVlanB }
    )) {
        $xml = @"
<configConfMo cookie="$cookie" dn="$($cfg.Dn)" inHierarchical="false">
  <inConfig>
    <fabricVsan name="$($cfg.Name)" id="$($cfg.Id)" fcoeVlan="$($cfg.FcoeVlan)" zoningState="enabled"/>
  </inConfig>
</configConfMo>
"@
        $r = Invoke-UcsmXml -Xml $xml
        if ($r.configConfMo.errorCode) {
            Write-Warning "  Storage VSAN $($cfg.Name): $($r.configConfMo.errorDescr)"
        } else {
            Write-Host "    [OK] $($cfg.Dn)  id=$($cfg.Id)  fcoeVlan=$($cfg.FcoeVlan)" `
                       -ForegroundColor Green
        }
    }

    # ── Step 2: Reassign FC storage ports to per-fabric VSANs ────────────────
    # Move ports 1–2 on each FI from VSAN 1 (net-default) to the matching VSAN.
    # Fabric A ports → VSAN 10 (net-hg-vsan-a)
    # Fabric B ports → VSAN 11 (net-hg-vsan-b)
    Write-Host "`n  [2/3] Reassigning FC storage ports to VSAN $VsanIdA/$VsanIdB" -ForegroundColor Cyan

    $portAssignments = @(
        @{ OldVsan='net-default'; NewVsan='net-hg-vsan-a'; Switch='A'; Ports=@(1,2) },
        @{ OldVsan='net-default'; NewVsan='net-hg-vsan-b'; Switch='B'; Ports=@(1,2) }
    )
    foreach ($pa in $portAssignments) {
        foreach ($port in $pa.Ports) {
            # Remove from old VSAN
            $delDn  = "fabric/fc-estc/$($pa.OldVsan)/phys-switch-$($pa.Switch)-slot-1-port-$port"
            $delXml = "<configConfMo cookie=""$cookie"" dn=""$delDn"" inHierarchical=""false""><inConfig><fabricFcVsanPortEp status=""deleted""/></inConfig></configConfMo>"
            Invoke-UcsmXml -Xml $delXml | Out-Null

            # Add to new VSAN
            $addDn  = "fabric/fc-estc/$($pa.NewVsan)/phys-switch-$($pa.Switch)-slot-1-port-$port"
            $addXml = "<configConfMo cookie=""$cookie"" dn=""$addDn"" inHierarchical=""false""><inConfig><fabricFcVsanPortEp switchId=""$($pa.Switch)"" portId=""$port"" slotId=""1""/></inConfig></configConfMo>"
            $r = Invoke-UcsmXml -Xml $addXml
            if ($r.configConfMo.errorCode) {
                Write-Warning "    Port $($pa.Switch)/1/$port → $($pa.NewVsan): $($r.configConfMo.errorDescr)"
            } else {
                Write-Host "    [OK] FI-$($pa.Switch) port $port → $($pa.NewVsan)" -ForegroundColor Green
            }
        }
    }

    # ── Step 3: Add storageVsanRef to every zone ──────────────────────────────
    # This is the critical binding.  Without it, zones stay at id=0 /
    # configState=not-applied regardless of all other configuration.
    # RN is always "vsan-ref"; name must match the fabricVsan.name created above.
    Write-Host "`n  [3/3] Binding zones to storage VSANs via storageVsanRef" -ForegroundColor Cyan

    $vsanBindings = @(
        @{ Filter='fab-a'; VsanName='hg-vsan-a' },
        @{ Filter='fab-b'; VsanName='hg-vsan-b' }
    )
    $bound = 0
    foreach ($binding in $vsanBindings) {
        $zones = Get-UcsFabricFcUserZone -Ucs $h |
                 Where-Object { $_.Dn -like "*hg-fc-zones*$($binding.Filter)*" }
        foreach ($zone in $zones) {
            $xml = @"
<configConfMo cookie="$cookie" dn="$($zone.Dn)/vsan-ref" inHierarchical="false">
  <inConfig><storageVsanRef name="$($binding.VsanName)"/></inConfig>
</configConfMo>
"@
            $r = Invoke-UcsmXml -Xml $xml
            if ($r.configConfMo.errorCode) {
                Write-Warning "    $($zone.Name): $($r.configConfMo.errorDescr)"
            } else {
                Write-Host "    [OK] $($zone.Name)  → storageVsanRef=$($binding.VsanName)" `
                           -ForegroundColor Green
                $bound++
            }
        }
    }
    Write-Host "    $bound zones bound." -ForegroundColor Green

    # ── Enable the zone profile ───────────────────────────────────────────────
    $profile = Get-UcsFabricFcZoneProfile -Ucs $h | Where-Object { $_.Name -eq 'hg-fc-zones' }
    if (-not $profile) {
        Write-Error "Zone profile 'hg-fc-zones' not found. Run without -Enable first."
        exit 1
    }
    Set-UcsFabricFcZoneProfile -FabricFcZoneProfile $profile -AdminState 'enabled' -Force |
        Out-Null
    Write-Host "`n  [OK] hg-fc-zones AdminState → ENABLED" -ForegroundColor Green

    # ── Verify ────────────────────────────────────────────────────────────────
    Write-Host "`n--- Zone Verification ---" -ForegroundColor Yellow
    $zones = Get-UcsFabricFcUserZone -Ucs $h | Where-Object { $_.Dn -like '*hg-fc-zones*' }
    $active    = ($zones | Where-Object { $_.OperState -eq 'active' }).Count
    $applied   = ($zones | Where-Object { $_.ConfigState -eq 'applied' }).Count
    $total     = $zones.Count
    $zones | Select-Object Name, Path, ConfigState, OperState |
             Sort-Object Path, Name | Format-Table -AutoSize
    Write-Host "  Applied : $applied/$total   Active : $active/$total" -ForegroundColor $(
        if ($active -eq $total) { 'Green' } else { 'Yellow' }
    )
    if ($active -ne $total) {
        Write-Warning "Some zones not yet active — wait 30s and re-check, or verify storage port link state."
    } else {
        Write-Host "`n  All zones active.  Verify from ESXi:" -ForegroundColor Green
        Write-Host "  esxcli storage nmp device list" -ForegroundColor DarkGray
        Write-Host "  esxcli storage nmp path list`n" -ForegroundColor DarkGray
    }
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
# CREATE ZONE PROFILE  (AdminState=disabled — safe pre-cable state)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[PROFILE] hg-fc-zones  (AdminState=disabled — safe to run pre-cable)"
$profile = Add-UcsFabricFcZoneProfile -Ucs $h `
    -Name       'hg-fc-zones' `
    -AdminState 'disabled' `
    -Descr      'FlexPod ASA A30 SI zones 8x2' `
    -ModifyPresent
Write-Host "  [OK]   $($profile.Dn)  AdminState=$($profile.AdminState)" -ForegroundColor Green

# ══════════════════════════════════════════════════════════════════════════════
# CREATE 16 ZONES  (8 blades × 2 fabrics, single-initiator zoning)
# NOTE: storageVsanRef is NOT added here — zones stay in pre-cable safe state.
#       storageVsanRef is added by the -Enable switch which also creates the
#       required storage-cloud VSANs and reassigns FC storage ports.
# ══════════════════════════════════════════════════════════════════════════════
$zoneCount = 0
foreach ($init in $initiators) {
    $short = $init.Sp -replace '^hg-', ''   # esx-01 … esx-08
    foreach ($fab in @('A','B')) {
        $zoneName = "hg-$short-fab-$($fab.ToLower())"   # hg-esx-01-fab-a  (15 chars)
        $initWwpn = if ($fab -eq 'A') { $init.FabA } else { $init.FabB }
        $initName = "$($init.Sp)-vmhba$( if ($fab -eq 'A') { '0' } else { '1' } )"
        $targets  = if ($fab -eq 'A') { $fabricATargets } else { $fabricBTargets }

        Write-Host "`n[ZONE-$fab] $zoneName  initiator=$initWwpn"

        $zone = Add-UcsFabricFcUserZone -Ucs $h `
            -FabricFcZoneProfile $profile `
            -Name   $zoneName `
            -Path   $fab `
            -ModifyPresent

        Add-UcsFabricFcEndpoint -Ucs $h -FabricFcUserZone $zone `
            -Name $initName -Wwpn $initWwpn -ModifyPresent | Out-Null
        Write-Host "  [init]  $initWwpn  ($initName)" -ForegroundColor DarkGray

        foreach ($tgt in $targets) {
            Add-UcsFabricFcEndpoint -Ucs $h -FabricFcUserZone $zone `
                -Name $tgt.Name -Wwpn $tgt.Wwpn -ModifyPresent | Out-Null
            Write-Host "  [tgt]   $($tgt.Wwpn)  ($($tgt.Name))" -ForegroundColor DarkGray
        }

        Write-Host "  [OK]   $zoneName" -ForegroundColor Green
        $zoneCount++
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n--- Zone Summary ---" -ForegroundColor Yellow
Get-UcsFabricFcUserZone -Ucs $h |
    Where-Object { $_.Dn -like '*hg-fc-zones*' } |
    Select-Object Name, Path | Sort-Object Path, Name | Format-Table -AutoSize

Write-Host "[DONE] $zoneCount zones created.  Profile = DISABLED (pre-cable safe state).`n" `
           -ForegroundColor Green
Write-Host "  ┌─ When ASA A30 is cabled and blades are associated, run:" -ForegroundColor DarkGray
Write-Host "  │    .\09-fc-zoning.ps1 -Enable" -ForegroundColor Cyan
Write-Host "  │" -ForegroundColor DarkGray
Write-Host "  │  -Enable will:" -ForegroundColor DarkGray
Write-Host "  │    1. Create storage-cloud VSANs 10/11 under fabric/fc-estc" -ForegroundColor DarkGray
Write-Host "  │    2. Reassign FC storage ports from VSAN 1 to VSANs 10/11" -ForegroundColor DarkGray
Write-Host "  │    3. Add storageVsanRef to each zone (what makes zones go active)" -ForegroundColor DarkGray
Write-Host "  │    4. Set zone profile AdminState = enabled" -ForegroundColor DarkGray
Write-Host "  └─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
