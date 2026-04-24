#Requires -Version 5.1
<#
.SYNOPSIS
    Section 02 – VLANs and VSANs
.DESCRIPTION
    Adds the HumbledGeeks VLANs to the fabric LAN cloud (they share the
    existing dc3-* VLANs) and creates dedicated VSANs in the FC Storage
    Cloud for hg-vsan-a (Fabric A) and hg-vsan-b (Fabric B).
.NOTES
    Dot-sources 00-prereqs-and-connect.ps1 automatically.

    What you may want to adjust for a different deployment:
      - $requiredVlans table   — add/remove VLAN IDs and names to match
                                 your network design
      - VSAN IDs and FCoE VLANs — change id="10"/"11" and fcoeVlan values
                                   if those IDs conflict with existing VSANs
      - VSAN names              — update hg-vsan-a/b if using a different
                                   org name prefix

.EXAMPLE
    # Run standalone
    $env:UCSM_PASSWORD = 'YourPassword'
    .\02-vlans-vsans.ps1

.EXAMPLE
    # Part of a full deployment — called automatically by run-all.ps1
    .\run-all.ps1
#>

. "$PSScriptRoot\00-prereqs-and-connect.ps1"
$h = $global:UcsHandle

Write-Host "`n========== 02 – VLANs & VSANs ==========" -ForegroundColor Cyan

# ── VLANs (global LAN cloud – shared across the domain) ──────────────────
Write-Host "`n[VLAN] Verifying required VLANs exist in LAN cloud..."
$requiredVlans = @(
    @{ Id = 1;   Name = 'default'         },
    @{ Id = 13;  Name = 'dc3-iscsi-a'     },
    @{ Id = 14;  Name = 'dc3-iscsi-b'     },
    @{ Id = 15;  Name = 'dc3-nfs'         },
    @{ Id = 16;  Name = 'dc3-mgmt'        },
    @{ Id = 17;  Name = 'dc3-vmotion'     },
    @{ Id = 18;  Name = 'dc3-apps'        },
    @{ Id = 20;  Name = 'dc3-core'        },
    @{ Id = 22;  Name = 'dc3-docker'      },   # vmnic2/3 workload trunk
    @{ Id = 32;  Name = 'dc3-gns3-mgmt'  },   # vmnic2/3 workload trunk
    @{ Id = 34;  Name = 'dc3-gns3-data'  },   # vmnic2/3 workload trunk
    @{ Id = 253; Name = 'dc3-jumbbox'    }    # vmnic2/3 workload trunk
)

# Add-UcsVlan requires a LAN cloud parent object piped in
$lanCloud = Get-UcsManagedObject -ClassId 'FabricLanCloud' -Ucs $h

foreach ($v in $requiredVlans) {
    $exists = Get-UcsVlan -Ucs $h | Where-Object { $_.Id -eq $v.Id -and $_.Name -eq $v.Name }
    if ($exists) {
        Write-Host "  [OK]   VLAN $($v.Id)  ($($v.Name))" -ForegroundColor Green
    } else {
        Write-Warning "  [MISSING] VLAN $($v.Id) ($($v.Name)) — creating..."
        $lanCloud | Add-UcsVlan -Ucs $h `
            -Name       $v.Name `
            -Id         $v.Id `
            -ModifyPresent | Out-Null
        Write-Host "  [OK]   VLAN $($v.Id) ($($v.Name)) created" -ForegroundColor Green
    }
}

# ── VSANs – FC Storage Cloud ──────────────────────────────────────────────
# Add-UcsVsan -FabricId is not a valid parameter in module 3.0.6.18.
# VSANs must be created at explicit per-fabric DNs via Invoke-UcsXml.
# Each VSAN appears in two trees: fabric/san/<FI> and fabric/fc-estc/<FI>.
Write-Host "`n[VSAN] Creating VSANs in FC Storage Cloud..."

$vsanXml = @"
<configConfMos cookie="$($h.Cookie)" inHierarchical="false">
  <inConfigs>
    <pair key="fabric/san/A/net-hg-vsan-a">
      <fabricVsan dn="fabric/san/A/net-hg-vsan-a"
        name="hg-vsan-a" id="10" fcoeVlan="1010"
        zoningState="disabled" status="created,modified"/>
    </pair>
    <pair key="fabric/san/B/net-hg-vsan-b">
      <fabricVsan dn="fabric/san/B/net-hg-vsan-b"
        name="hg-vsan-b" id="11" fcoeVlan="1011"
        zoningState="disabled" status="created,modified"/>
    </pair>
  </inConfigs>
</configConfMos>
"@
try {
    Invoke-UcsXml -Ucs $h -XmlQuery $vsanXml | Out-Null
    Write-Host "  [OK]   hg-vsan-a  ID=10  FCoE=1010  Fabric=A" -ForegroundColor Green
    Write-Host "  [OK]   hg-vsan-b  ID=11  FCoE=1011  Fabric=B" -ForegroundColor Green
} catch {
    Write-Warning "  VSANs: $($_.Exception.Message)"
}

# Verify
$vsans = Get-UcsVsan -Ucs $h | Where-Object { $_.Name -like 'hg-vsan-*' }
$vsans | Select-Object Name, Id, FcoeVlan, ZoningState, Dn | Format-Table -AutoSize

# ── FC Storage Port VSAN member assignments ────────────────────────────────
# Assign FC storage ports 29-32 on each FI to their respective VSANs.
# NOTE: In UCSM PS module this is done via Set-UcsFabricFcStorageCloud
# or direct MO manipulation. Shown here for reference.
Write-Host "`n[VSAN] FC Storage Port assignments (ports 1–2 on UCS 6332-16UP)..."
Write-Host "  NOTE: Verify in UCSM GUI that FC Storage ports 1–2 on FI-A" -ForegroundColor Yellow
Write-Host "        are members of hg-vsan-a and ports 1–2 on FI-B are" -ForegroundColor Yellow
Write-Host "        members of hg-vsan-b. Configure via CLI if needed:" -ForegroundColor Yellow
Write-Host "        scope fc-storage > scope fabric a > scope vsan hg-vsan-a" -ForegroundColor DarkGray
Write-Host "        create member-port fc a 1 <1|2>" -ForegroundColor DarkGray

Write-Host "`n[DONE] Section 02 – VLANs & VSANs complete.`n" -ForegroundColor Green
