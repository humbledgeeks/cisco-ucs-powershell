#Requires -Version 5.1
<#
.SYNOPSIS
    run-all.ps1 - Full HumbledGeeks UCS deployment orchestrator
.DESCRIPTION
    Runs all numbered sections in order (01 through 10) to build the complete
    HumbledGeeks FlexPod UCS environment from scratch.

    Deployment order:
      01  Address pools (MAC, UUID, WWNN, WWPN, IP)
      02  VLANs and VSANs
      03  Org policies (QoS, local disk, power, maintenance, boot, BIOS)
      04  vNIC templates (vmnic0-5, Fabric A + B)
      05  vHBA templates (vmhba0-1, Fabric A + B)
      06  Service profile template (hg-esx-template)
      07  Deploy 8 service profiles (unassociated)
      --  PAUSE: confirm blades are seated and FC cables connected
      07b Associate service profiles to blades 1-8
      09  Build and enable FC zone profile (hg-fc-zones, 16 zones)
      10  Verification report

    Each section is idempotent (-ModifyPresent) so the full run can be
    re-executed safely without duplicating objects.

.PARAMETER SkipAssociation
    Skip the blade association step (07b) and FC zone enable (09 -Enable).
    Use this when you want to build all config objects but defer physical
    blade binding to a later time.

.PARAMETER StartAt
    Begin the run at a specific section number (1-10).
    Useful for resuming a partial run after a failure.
    Example: -StartAt 4  (re-runs from vNIC templates onward)

.NOTES
    ── PREREQUISITES ───────────────────────────────────────────────────────
    1. PowerShell 7.x (cross-platform) or 5.1+ on Windows
       Install: https://github.com/PowerShell/PowerShell/releases

    2. Cisco.UCSManager module v3.0.6.18+
       Install-Module Cisco.UCSManager -Scope CurrentUser

    3. UCSM Virtual IP reachable (configured in 00-prereqs-and-connect.ps1)
       Default: 10.103.12.20  — change the $UCSMHost variable there

    4. Sub-org name configured (default: HumbledGeeks)
       Change the $OrgName variable in 00-prereqs-and-connect.ps1

    ── WHAT TO CHANGE FOR A DIFFERENT DEPLOYMENT ───────────────────────────
    All environment-specific settings live in 00-prereqs-and-connect.ps1:
      $UCSMHost — UCSM Virtual IP
      $OrgName  — sub-org to create/use

    Pool ranges, VLAN IDs, WWPN tables, and blade maps are in their
    respective numbered scripts (01 through 09). Each script has a
    "What to Change" section in its .NOTES block.

    ── STARTING FRESH ───────────────────────────────────────────────────────
    To wipe the HumbledGeeks org and start over:
        $env:UCSM_PASSWORD = 'YourPassword'
        .\00-wipe.ps1

.EXAMPLE
    # Full deployment — config objects only, blade association deferred
    $env:UCSM_PASSWORD = 'YourPassword'
    .\run-all.ps1 -SkipAssociation

.EXAMPLE
    # Full deployment including blade association and FC zone activation
    # (blades must be seated and ASA A30 must be cabled before running)
    $env:UCSM_PASSWORD = 'YourPassword'
    .\run-all.ps1

.EXAMPLE
    # Resume from vNIC templates if sections 1-3 already completed
    $env:UCSM_PASSWORD = 'YourPassword'
    .\run-all.ps1 -StartAt 4

.EXAMPLE
    # Verify current state at any point (does not re-run config)
    $env:UCSM_PASSWORD = 'YourPassword'
    .\10-verify.ps1
#>

param(
    [switch]$SkipAssociation,
    [int]$StartAt = 1
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Invoke-Section {
    param([int]$Number, [string]$File, [string]$Label)
    if ($Number -lt $StartAt) {
        Write-Host "`n  [SKIP] Section $Number ($Label) — StartAt=$StartAt" -ForegroundColor DarkGray
        return
    }
    Write-Host ("`n" + ("=" * 60)) -ForegroundColor DarkCyan
    Write-Host "  SECTION $Number — $Label" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    & "$scriptDir\$File"
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Section $Number ($File) exited with code $LASTEXITCODE"
    }
}

function Confirm-Continue {
    param([string]$Message)
    Write-Host "`n$Message" -ForegroundColor Yellow
    Write-Host "  Press ENTER to continue, or Ctrl+C to abort..." -ForegroundColor DarkGray
    $null = Read-Host
}

# ── Verify env var is set early ───────────────────────────────────────────
if (-not $env:UCSM_PASSWORD) {
    Write-Host "[INFO] UCSM_PASSWORD not set — you will be prompted for credentials each section." -ForegroundColor Yellow
    Write-Host "       To avoid repeated prompts, set it first:" -ForegroundColor DarkGray
    Write-Host "       `$env:UCSM_PASSWORD = 'YourPassword'" -ForegroundColor DarkGray
    Write-Host ""
}

$startTime = Get-Date
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  HumbledGeeks UCS Full Deployment" -ForegroundColor Cyan
Write-Host "  Started: $startTime" -ForegroundColor Cyan
if ($StartAt -gt 1) {
    Write-Host "  Resuming from section $StartAt" -ForegroundColor Yellow
}
if ($SkipAssociation) {
    Write-Host "  -SkipAssociation: blade binding will be skipped" -ForegroundColor Yellow
}
Write-Host "========================================`n" -ForegroundColor Cyan

# ── Sections 01-07: config objects ────────────────────────────────────────
Invoke-Section 1  '01-pools.ps1'                    'Address Pools'
Invoke-Section 2  '02-vlans-vsans.ps1'              'VLANs and VSANs'
Invoke-Section 3  '03-policies.ps1'                 'Org Policies'
Invoke-Section 4  '04-vnic-templates.ps1'           'vNIC Templates'
Invoke-Section 5  '05-vhba-templates.ps1'           'vHBA Templates'
Invoke-Section 6  '06-service-profile-template.ps1' 'Service Profile Template'
Invoke-Section 7  '07-deploy-service-profiles.ps1'  'Deploy Service Profiles'

# ── Pause before physical operations ──────────────────────────────────────
if (-not $SkipAssociation -and $StartAt -le 8) {
    Confirm-Continue @"
READY TO ASSOCIATE BLADES (Section 07b)

Pre-flight checklist:
  [ ] All 8 B200 blades seated in chassis 1, slots 1-8
  [ ] ASA A30 FC cables connected:
        node-1 n1_fc_a_1a --> FI-A storage port 1
        node-1 n1_fc_b_1d --> FI-B storage port 1
        node-2 n2_fc_a_1a --> FI-A storage port 2
        node-2 n2_fc_b_1d --> FI-B storage port 2
  [ ] All blades discovered in UCSM (assocState = unassociated)
"@

    Invoke-Section 8  '07b-associate-service-profiles.ps1' 'Associate Blades'
    Invoke-Section 9  '09-fc-zoning.ps1'                   'FC Zone Profile (build)'

    Confirm-Continue @"
READY TO ENABLE FC ZONING (09-fc-zoning.ps1 -Enable)

This activates the hg-fc-zones profile on both fabrics.
Run only after verifying blade association succeeded above.
"@
    Write-Host "`n[FC] Enabling FC zone profile..." -ForegroundColor Cyan
    & "$scriptDir\09-fc-zoning.ps1" -Enable
}

# ── Final verification ─────────────────────────────────────────────────────
Invoke-Section 10 '10-verify.ps1' 'Verification Report'

$elapsed = (Get-Date) - $startTime
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Deployment COMPLETE" -ForegroundColor Green
Write-Host "  Elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) minutes" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
