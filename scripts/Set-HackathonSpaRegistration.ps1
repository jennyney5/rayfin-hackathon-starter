#Requires -Version 5.1
<#
.SYNOPSIS
Creates the event's single-tenant Entra SPA registration, or adds approved callbacks.
.DESCRIPTION
Requires Azure CLI and an organizer signed into the supplied tenant. Creates no
secrets, Azure App Service, resource roles, or Fabric/Foundry items. Admin consent
is optional and applies only to Foundry user_impersonation.
#>
[CmdletBinding(DefaultParameterSetName = 'Create')]
param(
    [Parameter(Mandatory)]
    [guid] $TenantId,

    [Parameter(Mandatory, ParameterSetName = 'Create')]
    [ValidateNotNullOrEmpty()]
    [string] $DisplayName,

    [Parameter(Mandatory, ParameterSetName = 'Update')]
    [guid] $ClientId,

    [string[]] $RedirectUri = @(),

    [switch] $GrantAdminConsent
)

$ErrorActionPreference = 'Stop'

function Invoke-AzureCli {
    param([string[]] $Arguments)

    $output = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed (exit $LASTEXITCODE). Check the error above, tenant sign-in and Entra permissions."
    }
    if ($output) {
        ($output -join "`n") | ConvertFrom-Json
    }
}

function Invoke-Graph {
    param(
        [string] $Method,
        [string] $Url,
        [hashtable] $Body
    )

    $arguments = @('rest', '--method', $Method, '--url', $Url)
    $bodyFile = $null
    try {
        if ($Body) {
            # A JSON file avoids Windows native-command argument quoting issues.
            $bodyFile = [IO.Path]::GetTempFileName()
            [IO.File]::WriteAllText($bodyFile, ($Body | ConvertTo-Json -Depth 20),
                [Text.UTF8Encoding]::new($false))
            $arguments += @('--headers', 'Content-Type=application/json', '--body', "@$bodyFile")
        }
        Invoke-AzureCli -Arguments $arguments
    }
    finally {
        if ($bodyFile) {
            Remove-Item -LiteralPath $bodyFile -Force
        }
    }
}

function Get-GraphItems {
    param([string] $Url)

    do {
        $page = Invoke-Graph -Method GET -Url $Url
        $page.value
        $Url = $page.'@odata.nextLink'
    } while ($Url)
}

Get-Command az -ErrorAction Stop | Out-Null
$account = Invoke-AzureCli -Arguments @('account', 'show')
if ($account.tenantId -ne $TenantId.ToString()) {
    throw "Sign into the requested tenant first: az login --tenant $TenantId --allow-no-subscriptions"
}

$callbacks = @(
    foreach ($callback in $RedirectUri) {
        $uri = $null
        if (-not [Uri]::TryCreate($callback, [UriKind]::Absolute, [ref] $uri) -or
            $uri.Scheme -ne 'https' -or $uri.AbsolutePath -ne '/' -or
            $uri.Query -or $uri.Fragment -or $uri.UserInfo -or $callback.Contains('*') -or
            $uri.Host -in @('app.fabric.microsoft.com', 'app.powerbi.com', 'api.fabric.microsoft.com')) {
            throw "Invalid callback '$callback'. Supply the actual deployed HTTPS hosting root, not a portal URL, wildcard or auth helper."
        }
        $uri.AbsoluteUri
    }
)

$graph = 'https://graph.microsoft.com/v1.0'
$filter = [Uri]::EscapeDataString(
    "servicePrincipalNames/any(n:n eq 'https://ai.azure.com' or n eq 'https://ai.azure.com/')")
$resources = @(Get-GraphItems -Url "$graph/servicePrincipals?`$filter=$filter")
if ($resources.Count -ne 1) {
    throw "Expected one Foundry API service principal for https://ai.azure.com; found $($resources.Count). Ask the tenant admin to make the Foundry API available before rerunning."
}
$resource = $resources[0]
$scopes = @($resource.oauth2PermissionScopes | Where-Object {
    $_.value -eq 'user_impersonation' -and $_.isEnabled
})
if ($scopes.Count -ne 1) {
    throw 'The Foundry API does not expose one enabled user_impersonation delegated scope.'
}
$scope = $scopes[0]

if ($PSCmdlet.ParameterSetName -eq 'Create') {
    $nameFilter = [Uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    $matches = @(Get-GraphItems -Url "$graph/applications?`$filter=$nameFilter")
    if ($matches.Count -gt 0) {
        throw 'An application with this display name already exists. Rerun with its explicit -ClientId, or choose a distinct name.'
    }
    $app = Invoke-Graph -Method POST -Url "$graph/applications" -Body @{
        displayName = $DisplayName
        signInAudience = 'AzureADMyOrg'
        isFallbackPublicClient = $false
        spa = @{ redirectUris = $callbacks }
        web = @{ implicitGrantSettings = @{
            enableAccessTokenIssuance = $false
            enableIdTokenIssuance = $false
        } }
        requiredResourceAccess = @(@{
            resourceAppId = $resource.appId
            resourceAccess = @(@{ id = $scope.id; type = 'Scope' })
        })
    }
    $ClientId = [guid] $app.appId
    Write-Host "Created registration. Save ClientId $ClientId for all later runs (including recovery after a failure)."
}
else {
    $app = Invoke-Graph -Method GET -Url "$graph/applications(appId='$ClientId')"
    if ($app.signInAudience -ne 'AzureADMyOrg' -or
        @($app.passwordCredentials).Count -gt 0 -or @($app.keyCredentials).Count -gt 0 -or
        $app.isFallbackPublicClient -or
        $app.web.implicitGrantSettings.enableAccessTokenIssuance -or
        $app.web.implicitGrantSettings.enableIdTokenIssuance) {
        throw 'The supplied registration must be single-tenant, secret/certificate-free and use authorization code with PKCE (no implicit grant or fallback public client).'
    }
    $callbacks = @(@($app.spa.redirectUris) + $callbacks | Sort-Object -Unique)
    $permissions = @($app.requiredResourceAccess)
    $foundryPermission = @($permissions | Where-Object { $_.resourceAppId -eq $resource.appId })
    if ($foundryPermission.Count -eq 0) {
        $permissions += @{ resourceAppId = $resource.appId; resourceAccess = @(@{ id = $scope.id; type = 'Scope' }) }
    }
    elseif (-not @($foundryPermission[0].resourceAccess | Where-Object {
        $_.id -eq $scope.id -and $_.type -eq 'Scope'
    }).Count) {
        $foundryPermission[0].resourceAccess = @($foundryPermission[0].resourceAccess) +
            @(@{ id = $scope.id; type = 'Scope' })
    }
    Invoke-Graph -Method PATCH -Url "$graph/applications/$($app.id)" -Body @{
        spa = @{ redirectUris = $callbacks }
        requiredResourceAccess = $permissions
    } | Out-Null
}

$spUrl = "$graph/servicePrincipals(appId='$ClientId')"
$spFilter = [Uri]::EscapeDataString("appId eq '$ClientId'")
$principals = @(Get-GraphItems -Url "$graph/servicePrincipals?`$filter=$spFilter")
if ($principals.Count -eq 0) {
    # Newly created registrations can take a short time to become visible.
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            $principal = Invoke-Graph -Method POST -Url "$graph/servicePrincipals" -Body @{ appId = $ClientId.ToString() }
            break
        }
        catch {
            # A timed-out POST might have succeeded; read before retrying creation.
            $existing = @(Get-GraphItems -Url "$graph/servicePrincipals?`$filter=$spFilter")
            if ($existing.Count -eq 1) {
                $principal = $existing[0]
                break
            }
            if ($attempt -eq 6) { throw }
            Start-Sleep -Seconds 5
        }
    }
}
else {
    $principal = $principals[0]
}

$grantUrl = "$graph/oauth2PermissionGrants?`$filter=" + [Uri]::EscapeDataString(
    "clientId eq '$($principal.id)' and resourceId eq '$($resource.id)' and consentType eq 'AllPrincipals'")
if ($GrantAdminConsent) {
    $grants = @(Get-GraphItems -Url $grantUrl)
    if ($grants.Count -eq 0) {
        Invoke-Graph -Method POST -Url "$graph/oauth2PermissionGrants" -Body @{
            clientId = $principal.id
            resourceId = $resource.id
            consentType = 'AllPrincipals'
            principalId = $null
            scope = 'user_impersonation'
        } | Out-Null
    }
    elseif ('user_impersonation' -notin ($grants[0].scope -split ' ')) {
        Invoke-Graph -Method PATCH -Url "$graph/oauth2PermissionGrants/$($grants[0].id)" -Body @{
            scope = ($grants[0].scope + ' user_impersonation').Trim()
        } | Out-Null
    }
}

$verified = Invoke-Graph -Method GET -Url "$graph/applications/$($app.id)"
$verifiedPrincipal = Invoke-Graph -Method GET -Url $spUrl
$verifiedScopes = @($verified.requiredResourceAccess | Where-Object {
    $_.resourceAppId -eq $resource.appId
} | ForEach-Object { $_.resourceAccess } | Where-Object {
    $_.id -eq $scope.id -and $_.type -eq 'Scope'
})
if ($verified.signInAudience -ne 'AzureADMyOrg' -or $verifiedScopes.Count -ne 1 -or
    $verifiedPrincipal.appId -ne $ClientId.ToString() -or
    @($callbacks | Where-Object { $_ -cnotin @($verified.spa.redirectUris) }).Count -gt 0) {
    throw "Registration read-back validation failed. Rerun with -ClientId $ClientId after checking Entra."
}
if ($GrantAdminConsent) {
    $verifiedGrants = @(Get-GraphItems -Url $grantUrl)
    if ($verifiedGrants.Count -ne 1 -or 'user_impersonation' -notin ($verifiedGrants[0].scope -split ' ')) {
        throw 'Foundry tenant-wide admin consent read-back validation failed.'
    }
}

[pscustomobject] @{
    TenantId = $TenantId.ToString()
    ClientId = $ClientId.ToString()
    ServicePrincipalId = $verifiedPrincipal.id
    RedirectUris = @($verified.spa.redirectUris)
    FoundryScope = 'https://ai.azure.com/user_impersonation'
    AdminConsentVerified = [bool] $GrantAdminConsent
}
