#Requires -Version 5.1
<#
.SYNOPSIS
Adds a deployed Fabric app's hosting origin to the event SPA's callback allowlist.
.DESCRIPTION
Supply the actual app hosting endpoint, not its Fabric portal or REST API URL.
Any hosting path is reduced to the HTTPS origin; existing callbacks are preserved.
Requires Azure CLI sign-in and registration-edit permissions in the supplied tenant.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [guid] $TenantId,

    [Parameter(Mandatory)]
    [guid] $ClientId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $FabricEndpoint
)

$ErrorActionPreference = 'Stop'
$endpoint = $null
if (-not [Uri]::TryCreate($FabricEndpoint, [UriKind]::Absolute, [ref] $endpoint) -or
    $endpoint.Scheme -ne 'https' -or $endpoint.UserInfo -or
    $endpoint.Query -or $endpoint.Fragment -or $FabricEndpoint.Contains('*') -or
    $endpoint.Host -in @('app.fabric.microsoft.com', 'app.powerbi.com', 'api.fabric.microsoft.com')) {
    throw 'Supply the actual deployed Fabric app HTTPS hosting endpoint, without credentials, query or fragment; portal and REST API URLs are not app callbacks.'
}

$callback = $endpoint.GetLeftPart([UriPartial]::Authority) + '/'
Write-Host "Adding SPA callback: $callback"
& (Join-Path $PSScriptRoot 'Set-HackathonSpaRegistration.ps1') `
    -TenantId $TenantId -ClientId $ClientId -RedirectUri $callback
