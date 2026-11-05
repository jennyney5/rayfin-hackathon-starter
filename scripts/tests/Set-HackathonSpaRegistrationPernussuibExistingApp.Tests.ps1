#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$scripts = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$tenantId = '11111111-1111-1111-1111-111111111111'
$clientId = '22222222-2222-2222-2222-222222222222'
$name = 'Set-HackathonSpaRegistrationPernussuibExistingApp.ps1'

function Assert {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath (Join-Path $scripts $name) -Destination $fixture
    # The shared update is stubbed so no test can call Azure or change a registration.
    [IO.File]::WriteAllText((Join-Path $fixture 'Set-HackathonSpaRegistration.ps1'), @'
[CmdletBinding(DefaultParameterSetName = 'Create')]
param(
    [Parameter(Mandatory)] [guid] $TenantId,
    [Parameter(Mandatory, ParameterSetName = 'Create')] [string] $DisplayName,
    [Parameter(Mandatory, ParameterSetName = 'Update')] [guid] $ClientId,
    [string[]] $RedirectUri = @(),
    [switch] $GrantAdminConsent
)
if ($ClientId -eq [guid]::Empty) { throw 'Simulated shared update failure.' }
[pscustomobject] @{
    TenantId = $TenantId; ClientId = $ClientId
    Mode = $PSCmdlet.ParameterSetName
    RedirectUri = $RedirectUri; Consent = [bool] $GrantAdminConsent
}
'@)
    $wrapper = Join-Path $fixture $name
    $result = & $wrapper -TenantId $tenantId -ClientId $clientId
    Assert ($result.Mode -eq 'Update') 'Must select the existing-registration update path.'
    Assert ($result.TenantId.ToString() -eq $tenantId) 'Must preserve tenant ID.'
    Assert ($result.ClientId.ToString() -eq $clientId) 'Must preserve client ID.'
    Assert ($result.RedirectUri.Count -eq 0) 'Must not supply new callbacks.'
    Assert (-not $result.Consent) 'Must not grant admin consent by default.'

    $result = & $wrapper -TenantId $tenantId -ClientId $clientId -GrantAdminConsent
    Assert ($result.Consent) 'Must forward explicit admin consent.'
    $result = & $wrapper -TenantId $tenantId -ClientId $clientId -GrantAdminConsent:$false
    Assert (-not $result.Consent) 'Must honor explicitly disabled admin consent.'

    $message = ''
    try { & $wrapper -TenantId $tenantId -ClientId ([guid]::Empty) | Out-Null }
    catch { $message = $_.Exception.Message }
    Assert ($message -eq 'Simulated shared update failure.') 'Must propagate shared update failures.'

    $message = ''
    try { & $wrapper -TenantId $tenantId -ClientId 'invalid-guid' | Out-Null }
    catch { $message = $_.Exception.Message }
    Assert ($message -like '*Guid*') 'Invalid client IDs must fail parameter binding.'
    Write-Host 'PASS: Existing-app delegation, identifiers, callback preservation, explicit consent and failure propagation.'
}
finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
