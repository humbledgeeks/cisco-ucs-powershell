#Requires -Version 5.1
<#
.SYNOPSIS
    Section 00 - Prerequisites check and UCSM connection (shared helper)
.DESCRIPTION
    Dot-sourced by every other script in this series. Not run directly.

    Verifies the Cisco.UCSManager PowerShell module is installed (installs it
    from PSGallery if missing), connects to UCSM, and sets two global variables
    used by all downstream scripts:
        $global:UcsHandle  - the active UCSM session object
        $global:HgOrg      - the HumbledGeeks sub-org MO

    Credentials: set the UCSM_PASSWORD environment variable for non-interactive
    use; the script falls back to Get-Credential if the variable is absent.

.NOTES
    Repo    : infra-automation / Cisco / UCS / PowerShell / HumbledGeeks
    Tested  : Cisco.UCSManager 3.0.6.18 | PowerShell 7.x (macOS / Linux / Windows)

    ── CUSTOMISE FOR YOUR DEPLOYMENT ──────────────────────────────────────
    Change $UCSMHost and $OrgName below to match your environment.
    These two values are the only things that need to change for a different
    UCS domain or sub-org. All other scripts inherit them automatically.
    ────────────────────────────────────────────────────────────────────────

.EXAMPLE
    # This file is dot-sourced automatically — never run it directly.
    # To use it interactively in a shell session:
    $env:UCSM_PASSWORD = 'YourPassword'
    . .\00-prereqs-and-connect.ps1
    Get-UcsServiceProfile -Ucs $global:UcsHandle
#>

# ══════════════════════════════════════════════════════════════════════════
# DEPLOYMENT CONFIGURATION — change these for a new environment
# ══════════════════════════════════════════════════════════════════════════
$UCSMHost = '10.103.12.20'    # UCSM Virtual IP (cluster VIP, not individual FI IPs)
$OrgName  = 'HumbledGeeks'    # Sub-org name — created automatically if it doesn't exist
# ══════════════════════════════════════════════════════════════════════════

$OrgDN = "org-root/org-$OrgName"

# ── Module check ─────────────────────────────────────────────────────────
# PSGallery publishes the UCS PowerTool suite as three modules:
#   Cisco.UCS.Common   – shared types and utilities
#   Cisco.UCS.Core     – core Ucs session objects
#   Cisco.UCSManager   – UCS Manager cmdlets (Connect-Ucs, Add-UcsServiceProfile, etc.)
$requiredModules = @('Cisco.UCS.Common', 'Cisco.UCS.Core', 'Cisco.UCSManager')
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Host "[INFO] Installing $mod from PSGallery..." -ForegroundColor Cyan
        Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber -AcceptLicense -Repository PSGallery
    }
    Import-Module $mod -ErrorAction Stop
}
Write-Host "[OK]   Cisco UCS modules loaded  (UCSManager $(Get-Module Cisco.UCSManager | Select-Object -ExpandProperty Version))" -ForegroundColor Green

# ── Connect ────────────────────────────────────────────────────────────────
# Build credential once
if ($env:UCSM_PASSWORD) {
    $secPwd = ConvertTo-SecureString $env:UCSM_PASSWORD -AsPlainText -Force
    $cred   = New-Object System.Management.Automation.PSCredential('admin', $secPwd)
    Write-Host "[INFO] Using UCSM_PASSWORD env var for authentication" -ForegroundColor DarkGray
} else {
    $cred = Get-Credential -UserName 'admin' -Message "Enter UCSM credentials for $UCSMHost"
}

# Retry loop — handles "maximum session limit" (error 572) by waiting for idle sessions
# to expire (UCSM default idle timeout is 600 s).  Retries every 20 s, up to 10 times.
$maxRetries = 10
$retryDelay = 20
$global:UcsHandle = $null

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    try {
        # Use -NotDefault so we hold an explicit handle; always disconnect on exit via
        # the Disconnect-UcsSession helper defined below.
        $global:UcsHandle = Connect-Ucs -Name $UCSMHost -Credential $cred -NotDefault -ErrorAction Stop
        Write-Host "[OK]   Connected to UCSM $UCSMHost" -ForegroundColor Green
        break
    } catch {
        if ($_.Exception.Message -match '572|maximum session') {
            Write-Warning "[WARN] UCSM session limit hit (attempt $attempt/$maxRetries). Waiting ${retryDelay}s for idle sessions to expire..."
            Start-Sleep -Seconds $retryDelay
        } else {
            throw  # Re-throw unexpected errors immediately
        }
    }
}

if (-not $global:UcsHandle) {
    throw "Failed to connect to UCSM $UCSMHost after $maxRetries attempts. Check session limit in UCSM Admin → Sessions."
}

# ── Cleanup helper — call at the end of every script ──────────────────────
function global:Disconnect-UcsSession {
    if ($global:UcsHandle) {
        try { Disconnect-Ucs -Ucs $global:UcsHandle -ErrorAction SilentlyContinue } catch {}
        $global:UcsHandle = $null
        Write-Host "[OK]   UCSM session closed." -ForegroundColor DarkGray
    }
}

# ── Verify org exists ─────────────────────────────────────────────────────
$org = Get-UcsOrg -Ucs $global:UcsHandle | Where-Object { $_.Name -eq $OrgName }
if (-not $org) {
    Write-Warning "Org '$OrgName' not found — creating it..."
    $org = Add-UcsOrg -Ucs $global:UcsHandle -Name $OrgName `
               -Descr "HumbledGeeks sub-organisation" -ModifyPresent
    Write-Host "[OK]   Org $OrgName created" -ForegroundColor Green
} else {
    Write-Host "[OK]   Org $OrgName verified  (DN: $($org.Dn))" -ForegroundColor Green
}

$global:HgOrg = $org
Write-Host "`n[READY] Use `$global:UcsHandle and `$global:HgOrg in subsequent scripts.`n"
