#Requires -Version 5.1
<#
.SYNOPSIS
Adds the Foundry delegated permission to an existing event SPA registration.
.DESCRIPTION
Adds https://ai.azure.com/user_impersonation using the shared registration script.
Preserves existing callbacks and API permissions; creates no app registration.
Requires Azure CLI sign-in, registration-edit permissions and the genuine Foundry
API service principal in the tenant. A missing API service principal is not provisioned.
Tenant-wide admin consent is granted only with -GrantAdminConsent and requires
an appropriate consent-capable Entra role.
.EXAMPLE
.\Set-HackathonSpaRegistrationPernussuibExistingApp.ps1 -TenantId <tenant-guid> -ClientId <client-guid>
.EXAMPLE
.\Set-HackathonSpaRegistrationPernussuibExistingApp.ps1 -TenantId <tenant-guid> -ClientId <client-guid> -GrantAdminConsent
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [guid] $TenantId,

    [Parameter(Mandatory)]
    [guid] $ClientId,

    [switch] $GrantAdminConsent
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Set-HackathonSpaRegistration.ps1') `
    -TenantId $TenantId -ClientId $ClientId -GrantAdminConsent:$GrantAdminConsent
