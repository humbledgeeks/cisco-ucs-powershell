# Contributing to cisco-ucs-powershell

## Requirements

- PowerShell 5.1+ or PowerShell 7+
- Cisco UCS PowerTool: `Install-Module Cisco.UCSManager`
- PSScriptAnalyzer: `Install-Module PSScriptAnalyzer`

## Script Header

All scripts must include a header block:

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

## Credential Standards

- Use `$env:UCSM_PASSWORD` — never hardcode credentials
- Store sensitive values in environment variables or PowerShell SecretManagement

## Linting

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse
```

## Pull Request Checklist

- [ ] Script header present with all fields
- [ ] No hardcoded credentials
- [ ] PSScriptAnalyzer passes with no errors
- [ ] README updated if new scripts added
