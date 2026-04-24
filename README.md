# cisco-ucs-powershell

PowerShell automation for Cisco UCS infrastructure — FlexPod deployment, Service Profiles, fabric configuration, and identity management.

## Contents

| Path | Purpose |
|------|---------|
| `get-ucs-inventory.ps1` | Gather UCS inventory |
| `HumbledGeeks/` | Complete FlexPod automation suite (00-10) |
| `HumbledGeeks/blog-post-draft.md` | Companion blog post |
| `HumbledGeeks/screenshots/` | Blog post images |

## Prerequisites

- PowerShell 5.1+ or PowerShell 7+
- Cisco UCS PowerTool: `Install-Module Cisco.UCSManager`

## Quick Start

```powershell
cd HumbledGeeks
.\00-prereqs-and-connect.ps1
.\01-pools.ps1
# ... continue through the numbered suite
```

## Blog Post

[Automating a Cisco UCS FlexPod with NetApp ASA A30 on Broadcom VCF](https://humbledgeeks.com/automating-a-cisco-ucs-flexpod-with-netapp-asa-a30-on-broadcom-vcf/)

## CI/CD

All PRs validated by PSScriptAnalyzer, secret scan, and header compliance.

## Owner

humbledgeeks-allen | [HumbledGeeks.com](https://humbledgeeks.com)
