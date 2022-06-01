# I inherited an environment with a terrible implementation of Azure AD Sync
# So many duplicate accounts across AD and 365
# I needed to report on users whose Email != UPN


# Import any necessary modules
Import-Module ActiveDirectory


# Empty string var to collect results, could be written to a file
$problemAccounts = ""


# Collect current list of users whose EmailAddress dots NOT match their UPN
Try
    {
        $Error.Clear()
        $ADUsersDiffUPN =  Get-ADUser -Filter * -Properties EmailAddress,samaccountname, UserPrincipalName `
            | Where-Object {$_.Enabled -eq $true} `
            | Where-Object {$_.EmailAddress.Length -gt 0}  `
            | Where-Object {$_.EmailAddress -ne $_.UserPrincipalName} `
            | Sort-Object -Property SamAccountName
            #| Select-Object EmailAddress, SamAccountName, UserPrincipalName `
            

        #Write-Host `r`nENABLED USERS WITH EMAIL DIFFERENT FROM UPN:`r`n
        $problemAccounts += "ENABLED USERS WITH EMAIL ADDRESS DIFFERENT FROM UPN/SAM:`r`n`r`n"

        ForEach ($diffUPNuser in $ADUsersDiffUPN)
            {
                #Write-Host $diffUPNuser.SamAccountName `, $diffUPNuser.UserPrincipalName `, $diffUPNuser.EmailAddress
                $problem1user = $diffUPNuser.SamAccountName + ", " + $diffUPNuser.UserPrincipalName + ", " + $diffUPNuser.EmailAddress + "`r`n"
                $problemAccounts += $problem1user
            } # End ForEach
        
    } # End Try #1

catch
    {
        Write-Host An error occurred trying to enumerate AD users with UPN-Email differences.
        Write-Host $Error
        exit
    }



# Collect current list of users whose user object in AD is missing the EmailAddress property
Try
    {
        $Error.Clear()
        $ADUsersNoEmail =  Get-ADUser -Filter * -Properties EmailAddress,samaccountname, UserPrincipalName `
            | Where-Object {$_.Enabled -eq $true} `
            | Where-Object {$_.EmailAddress.Length -eq 0}  `
            | Where-Object {$_.EmailAddress -ne $_.UserPrincipalName} `
            | Select-Object EmailAddress, SamAccountName, UserPrincipalName `
            | Sort-Object -Property SamAccountName

        #Write-Host `r`n`r`n`r`nENABLED USERS MISSING EMAIL:`r`n
        $problemAccounts += "`r`n`r`n`r`nENABLED USERS MISSING EMAIL PROPERTY:`r`n`r`n"

        ForEach ($noEmailUser in $ADUsersNoEmail)
            {
                $problem2user = $noEmailUser.SamAccountName +", " + $noEmailUser.UserPrincipalName + "`r`n"
                $problemAccounts += $problem2user
            } # End ForEach
        
    } # End Try #2

catch
    {
        Write-Host An error occurred trying to enumerate AD users with UPN-Email differences.
        Write-Host $Error
        exit
    }


# Print results to console. This var could also be piped to Out-File if desired
Write-Host $problemAccounts
