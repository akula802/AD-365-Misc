# Script to check for user accounts with MFA not set to 'Enforced' or 'Enabled'
# Queries across multiple tenants in a managed services environment
# Creates a separate .csv file per tenant
# Run the script and log in as yourself, script will only access tenants you are a delegated admin for
# Lots of credit to: https://www.alitajran.com/export-office-365-users-mfa-status-with-powershell/



#Import O365 CMDLETS
Import-Module MSOnline
    if($?)
    {
        Write-Host -ForegroundColor Green -Object "MSOnline module imported successfully"
    }
    else
    {
        Write-Host -ForegroundColor Red -Object "ERROR: Failed to import the MSOnline module.  Check that it is installed"
        exit
    }



# Define the final report path (folder)
$reportPath = "C:\Path\to\Results"



# Connect to M365 with IIT Creds
Connect-MsolService



# Collect all tenants I have access to
$Tenants = Get-MsolPartnerContract | Select Name, TenantID



# Loop through the file and collect non-MFA users
#[int]$count = 1
foreach($Tenant in $Tenants) {

    # Create the final report object, that will dump into the output CSV file later
    $Report = [System.Collections.Generic.List[Object]]::new()
    $PartnerName = ($Tenant.Name).Replace("."," ").Replace(" ", "").Replace(",","").Replace("_","").Trim()

    try
        {
            # get all the users
            $Users = Get-MsolUser -TenantId $Tenant.TenantID -EnabledFilter EnabledOnly -All 

            # Loop the users
            ForEach ($User in $Users) {

                # Get some MFA info about the user
                $MFAMethods = $User.StrongAuthenticationMethods.MethodType
                $MFAEnforced = $User.StrongAuthenticationRequirements.State
                $MFAPhone = $User.StrongAuthenticationUserDetails.PhoneNumber
                $DefaultMFAMethod = ($User.StrongAuthenticationMethods | ? { $_.IsDefault -eq "True" }).MethodType

                # Add to report if MFA is not enabled or enforced
                If ((($User.StrongAuthenticationRequirements.State -ne "Enforced") -and ($User.StrongAuthenticationRequirements.State -ne "Enabled")) -and ($User.StrongAuthenticationRequirements.State)) {
                    Write-Host $User.UserPrincipalName has MFA: $MFAEnforced

                    $ReportLine = [PSCustomObject] @{
                        User        = $User.UserPrincipalName
                        Name        = $User.DisplayName
                        MFAUsed     = $MFAEnforced
                        MFAMethod   = $DefaultMFAMethod
                        PhoneNumber = $MFAPhone
                    }
                 
                    
        
                } # end if #1

                elseif (!($User.StrongAuthenticationRequirements.State))
                    {

                    Write-Host $User.UserPrincipalName is not using MFA.

                        $ReportLine = [PSCustomObject] @{
                            User        = $User.UserPrincipalName
                            Name        = $User.DisplayName
                            MFAUsed     = "None"
                            MFAMethod   = "Not in use"
                            PhoneNumber = $MFAPhone

                    }

                } # End elseif


                # Add the user result to the $Report object here, before moving to the next user
                $Report.Add($ReportLine)
                 

            } # End foreach $user loop


            # Write the report file here before moving to the next partner/tenant
            $Report | Sort Name | Export-CSV -Encoding UTF8 -Path "$reportPath\$PartnerName.csv" -NoTypeInformation

        } # End try block
   
    catch
        {
            Write-host Failed at tenant: $tenant.Name
            Write-Host $Error
            Write-Host `r`n
        }

} # End foreach $account loop



# print the results and write the file - Or use Out-Grid to view results (if doing one tenant at a time)
Write-Host `r`nFinished. Reports at C:\Users\BHartley\Desktop\test\Results2
#$Report | Select User, Name, MFAUsed, MFAMethod, PhoneNumber | Sort Name | Out-GridView

