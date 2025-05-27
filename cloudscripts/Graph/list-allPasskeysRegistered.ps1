Connect-MgGraph -Scopes UserAuthenticationMethod.Read.All, AuditLog.Read.All

$Report = @()

$PasskeyUsers = Invoke-MgGraphRequest -Method GET `
-Uri "beta/reports/authenticationMethods/userRegistrationDetails?`$filter=methodsRegistered/any(i:i eq 'passKeyDeviceBound') OR methodsRegistered/any(i:i eq 'passKeyDeviceBoundAuthenticator')" `
-OutputType PSObject | Select -expand Value

Foreach ($user in $PasskeyUsers) {
    $passkey = Invoke-MgGraphRequest -Method GET -Uri "beta/users/$($user.id)/authentication/fido2Methods" -OutputType PSObject | Select -Expand Value
    $obj = [PSCustomObject][ordered]@{
        "User" = $user.UserPrincipalName
        "Passkey" = $passkey.displayName
        "Model" = $passkey.model
        "aaGuid" = $passkey.aaGuid
        "Date created" = $passkey.createdDateTime
    }
    $Report += $obj
}

$Report | Out-GridView