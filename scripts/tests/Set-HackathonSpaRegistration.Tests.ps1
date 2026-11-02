#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$registrationScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Set-HackathonSpaRegistration.ps1'
$callbackScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Add-HackathonSpaCallback.ps1'
$tenantId = '11111111-1111-1111-1111-111111111111'
$clientId = '22222222-2222-2222-2222-222222222222'

function Assert {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Reset-State {
    $script:state = @{
        TenantId = $tenantId
        ClientId = $clientId
        App = $null
        Principal = $null
        Grants = @()
        Calls = @()
        FailMethod = ''
        ResourceNames = @('https://ai.azure.com', 'https://ai.azure.com/')
        Resource = @{
            id = 'foundry-object'
            appId = '33333333-3333-3333-3333-333333333333'
            oauth2PermissionScopes = @(@{
                id = '44444444-4444-4444-4444-444444444444'
                value = 'user_impersonation'
                isEnabled = $true
            })
        }
    }
    $global:SpaRegistrationTestState = $script:state
}

# This stand-in prevents all network calls, including tenant sign-in and provisioning.
function az {
    $global:LASTEXITCODE = 0
    $state = $global:SpaRegistrationTestState
    $arguments = @($args)
    if ($arguments[0] -eq 'account') {
        return (@{ tenantId = $state.TenantId } | ConvertTo-Json)
    }
    Assert ($arguments[0] -eq 'rest') 'Unexpected Azure CLI command.'
    $method = $arguments[[Array]::IndexOf($arguments, '--method') + 1]
    $cliUrl = $arguments[[Array]::IndexOf($arguments, '--url') + 1]
    Assert ($cliUrl -notmatch '[()]') 'Graph URL contains unescaped Windows command-shell parentheses.'
    $url = [Uri]::UnescapeDataString($cliUrl)
    $bodyIndex = [Array]::IndexOf($arguments, '--body')
    $body = $null
    $bodyFile = $null
    if ($bodyIndex -ge 0) {
        $bodyFile = $arguments[$bodyIndex + 1].Substring(1)
        $body = Get-Content -LiteralPath $bodyFile -Raw | ConvertFrom-Json
    }
    $state.Calls += @{ Method = $method; Url = $url; Body = $body; BodyFile = $bodyFile }
    if ($method -eq $state.FailMethod) {
        $global:LASTEXITCODE = 1
        return
    }

    $result = $null
    switch -Regex ($url) {
        '/servicePrincipals\?\$filter=servicePrincipalNames' {
            Assert ($url -match "servicePrincipalNames/any\(n:n eq '([^']+)'\)$") 'Foundry discovery must use a single exact resource-name match.'
            $resourceName = $Matches[1]
            $result = @{ value = @() }
            if ($resourceName -in $state.ResourceNames) {
                $result.value = @($state.Resource)
            }
            break
        }
        '/applications\?\$filter=displayName' {
            $result = @{ value = @() }
            if ($state.App) { $result.value = @($state.App) }
            break
        }
        '/applications$' {
            Assert ($method -eq 'POST') 'Expected application creation.'
            $body | Add-Member -NotePropertyName id -NotePropertyValue 'app-object'
            $body | Add-Member -NotePropertyName appId -NotePropertyValue $state.ClientId
            $body | Add-Member -NotePropertyName passwordCredentials -NotePropertyValue @()
            $body | Add-Member -NotePropertyName keyCredentials -NotePropertyValue @()
            $state.App = $body
            $result = $body
            break
        }
        '/applications[/\(]' {
            Assert ($null -ne $state.App) 'No application to read/update.'
            if ($method -eq 'PATCH') {
                $state.App.spa = $body.spa
                $state.App.requiredResourceAccess = $body.requiredResourceAccess
            }
            else { $result = $state.App }
            break
        }
        '/servicePrincipals\?\$filter=appId' {
            $result = @{ value = @() }
            if ($state.Principal) { $result.value = @($state.Principal) }
            break
        }
        '/servicePrincipals$' {
            Assert ($method -eq 'POST') 'Expected service principal creation.'
            $state.Principal = @{ id = 'client-object'; appId = $body.appId }
            $result = $state.Principal
            break
        }
        '/servicePrincipals\(appId=' {
            $result = $state.Principal
            break
        }
        '/oauth2PermissionGrants\?' {
            $result = @{ value = $state.Grants }
            break
        }
        '/oauth2PermissionGrants$' {
            $body | Add-Member -NotePropertyName id -NotePropertyValue 'grant-object'
            $state.Grants += $body
            $result = $body
            break
        }
        '/oauth2PermissionGrants/grant-object$' {
            $state.Grants[0].scope = $body.scope
            break
        }
        default { throw "Unexpected Graph request: $method $url" }
    }
    if ($null -ne $result) { $result | ConvertTo-Json -Depth 30 }
}

function Assert-Fails {
    param([scriptblock] $Action, [string] $Expected)
    $message = ''
    try { & $Action | Out-Null }
    catch { $message = $_.Exception.Message }
    Assert ($message -like "*$Expected*") "Expected failure containing '$Expected'; got '$message'."
}

Reset-State
$result = & $registrationScript -TenantId $tenantId -DisplayName "Event's SPA" -GrantAdminConsent
Assert ($result.ClientId -eq $clientId -and $result.TenantId -eq $tenantId) 'Public IDs were not returned.'
Assert ($result.AdminConsentVerified) 'Admin consent was not verified.'
Assert ($script:state.App.signInAudience -eq 'AzureADMyOrg') 'Registration is not single tenant.'
Assert (@($script:state.App.spa.redirectUris).Count -eq 0) 'Creation invented a callback.'
Assert (-not $script:state.App.web.implicitGrantSettings.enableAccessTokenIssuance) 'Implicit access tokens enabled.'
Assert (-not $script:state.App.web.implicitGrantSettings.enableIdTokenIssuance) 'Implicit ID tokens enabled.'
Assert ($script:state.Grants[0].clientId -eq 'client-object') 'Consent used app ID instead of service principal object ID.'
Assert ($script:state.Grants[0].scope -eq 'user_impersonation') 'Consent granted an unrelated scope.'
Assert ($script:state.App.requiredResourceAccess[0].resourceAppId -eq $script:state.Resource.appId) 'API ID was not discovered.'
Assert (@($script:state.App.passwordCredentials).Count -eq 0) 'A secret was created.'

$script:state.App.requiredResourceAccess += [pscustomobject] @{
    resourceAppId = 'other-api'
    resourceAccess = @([pscustomobject] @{ id = 'other-scope'; type = 'Scope' })
}
$script:state.App.requiredResourceAccess[0].resourceAccess = @()
$script:state.Grants[0].scope = 'existing_scope'
$result = & $registrationScript -TenantId $tenantId -ClientId $clientId `
    -RedirectUri @('https://group-one.example/', 'https://group-two.example/') -GrantAdminConsent
Assert ($result.RedirectUris.Count -eq 2) 'Callbacks were not appended.'
Assert ($script:state.App.requiredResourceAccess.Count -eq 2) 'Update discarded other API permissions.'
Assert ($script:state.App.requiredResourceAccess[1].resourceAccess[0].id -eq 'other-scope') 'Update changed an unrelated scope.'
Assert ($script:state.App.requiredResourceAccess[0].resourceAccess.Count -eq 1) 'Missing Foundry scope was not restored.'
Assert ($script:state.Grants[0].scope -eq 'existing_scope user_impersonation') 'Consent update discarded existing scopes.'

$result = & $registrationScript -TenantId $tenantId -ClientId $clientId `
    -RedirectUri @('https://group-two.example/', 'https://group-three.example/') -GrantAdminConsent
Assert ($result.RedirectUris.Count -eq 3) 'Update duplicated or lost a callback.'
Assert ('https://group-one.example/' -cin $result.RedirectUris) 'Update removed another group callback.'
Assert (@($script:state.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Url -match '/applications$' }).Count -eq 1) 'Rerun created another registration.'
Assert (@($script:state.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Url -match '/servicePrincipals$' }).Count -eq 1) 'Rerun created another service principal.'
Assert ($script:state.Grants.Count -eq 1) 'Rerun duplicated admin consent.'
$result = & $callbackScript -TenantId $tenantId -ClientId $clientId `
    -FabricEndpoint 'https://group-four.example/dashboard'
Assert ('https://group-four.example/' -cin $result.RedirectUris) 'Callback script did not derive the hosting root.'
Assert ($result.RedirectUris.Count -eq 4) 'Callback script discarded existing callbacks.'
Assert (-not $result.AdminConsentVerified) 'Callback script attempted admin consent.'
$result = & $callbackScript -TenantId $tenantId -ClientId $clientId `
    -FabricEndpoint 'https://group-four.example/'
Assert ($result.RedirectUris.Count -eq 4) 'Callback script duplicated the same origin.'
Assert-Fails { & $registrationScript -TenantId $tenantId -DisplayName "Event's SPA" } 'already exists'
$script:state.App.signInAudience = 'AzureADMultipleOrgs'
Assert-Fails { & $registrationScript -TenantId $tenantId -ClientId $clientId } 'single-tenant'
Assert (@($script:state.Calls | Where-Object { $_.BodyFile -and (Test-Path -LiteralPath $_.BodyFile) }).Count -eq 0) 'Temporary request files were left behind.'

Reset-State
foreach ($invalid in @(
    'http://group.example/', 'https://*.example/', 'https://group.example/auth/relay.html',
    'https://group.example/?code=test', 'https://group.example/#fragment',
    'https://user:password@group.example/', 'https://app.fabric.microsoft.com/',
    'https://app.powerbi.com/', 'https://api.fabric.microsoft.com/'
)) {
    Assert-Fails { & $registrationScript -TenantId $tenantId -DisplayName 'Test' -RedirectUri $invalid } 'Invalid callback'
}
Assert ($script:state.Calls.Count -eq 0) 'Invalid callbacks reached Graph.'
foreach ($invalid in @(
    'http://group.example/', 'https://*.example/', 'https://app.fabric.microsoft.com/groups/workspace',
    'https://app.powerbi.com/', 'https://api.fabric.microsoft.com/v1/workspaces',
    'https://group.example/?code=test', 'https://group.example/#fragment',
    'https://user:password@group.example/'
)) {
    Assert-Fails { & $callbackScript -TenantId $tenantId -ClientId $clientId -FabricEndpoint $invalid } 'hosting endpoint'
}
Assert ($script:state.Calls.Count -eq 0) 'Invalid hosting endpoints reached Graph.'
$script:state.TenantId = '55555555-5555-5555-5555-555555555555'
Assert-Fails { & $registrationScript -TenantId $tenantId -DisplayName 'Test' } 'Sign into the requested tenant'
Assert ($script:state.Calls.Count -eq 0) 'Wrong-tenant invocation reached Graph.'

Reset-State
$script:state.ResourceNames = @('https://ai.azure.com/')
$result = & $registrationScript -TenantId $tenantId -DisplayName 'Trailing-slash resource'
Assert ($result.ClientId -eq $clientId) 'Trailing-slash Foundry resource was not discovered.'

Reset-State
$script:state.ResourceNames = @()
Assert-Fails { & $registrationScript -TenantId $tenantId -DisplayName 'Missing resource' } 'found 0'
Assert ($null -eq $script:state.App) 'Missing Foundry resource did not stop creation.'

Reset-State
$script:state.Resource.oauth2PermissionScopes[0].isEnabled = $false
Assert-Fails { & $registrationScript -TenantId $tenantId -DisplayName 'Test' } 'enabled user_impersonation'
Assert ($null -eq $script:state.App) 'Unavailable scope did not stop creation.'

Reset-State
$result = & $registrationScript -TenantId $tenantId -DisplayName 'No tenant-wide consent'
Assert (-not $result.AdminConsentVerified -and $script:state.Grants.Count -eq 0) 'Consent was granted without explicit opt-in.'
$script:state.FailMethod = 'PATCH'
Assert-Fails { & $registrationScript -TenantId $tenantId -ClientId $clientId -RedirectUri 'https://group.example/' } 'Azure CLI failed'
Assert (@($script:state.Calls | Where-Object { $_.BodyFile -and (Test-Path -LiteralPath $_.BodyFile) }).Count -eq 0) 'Failed request left a temporary body file.'

Write-Host 'PASS: SPA creation, safe/idempotent updates, targeted optional consent, input validation and CLI failure cleanup.'
