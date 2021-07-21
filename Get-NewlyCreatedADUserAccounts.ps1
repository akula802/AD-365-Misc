# Script to find newly-created user accounts (now defined in the $nHoursAgo variable on/near line 36)


# First, make sure the OS is at least Server 2008 R2 or higher
# This will also only work in the PowerShell version is 2.0 or higher
$psVersion = $PSVersionTable.PSVersion.Major
$osName = Get-WmiObject win32_operatingsystem | Select-Object -ExpandProperty Caption
$osversion =  (Get-WmiObject win32_operatingsystem | Select-Object -ExpandProperty version).Replace(".","")
if (([int32]$osVersion.SubString(0,2) -lt 61) -and (([int32]$osVersion.SubString(0,2)) -ne 10))
    {
        Write-Host This OS does not meet the minimum requirements to run this script.
        exit
    }
<#elseif ($osName -notmatch "Server")
    {
        Write-Host This is not a server OS. Exiting...
        exit
    }#>
elseif ($psVersion -lt 2)
    {
        Write-Host This Powershell version is not sufficient. Needs to be PSv2 or higher.
        exit
    }



# Import any necessary modules
Import-Module ActiveDirectory



# Define initial vairbales
#$timestamp = Get-Date -Format yyyy-MM-dd_HH:mm:ss
$nHoursAgo = (Get-Date).AddHours(-24)
$MessageBody = ""
$Count = $ADUsers.Count
$NewUserCount = 0



# Collect current list and save to file
Try
    {
        $Error.Clear()
        $ADUsers = Get-ADUser -Filter * -Properties WhenCreated, SamAccountName -ErrorAction SilentlyContinue | `
        Select-Object SamAccountName, WhenCreated | Sort-Object WhenCreated -Descending
    }
catch
    {
        Write-Host An error occurred trying to enumerate AD users.
        Write-Host $Error
        exit
    }



# Loop through the AD users and find the newly-created ones
Try
    {
        ForEach ($ADUser in $ADUsers)
            {
                $Name = $ADUser.SamAccountName
                $CreatedOn = $ADUser.WhenCreated
                #Write-Host "User: $Name | Created: $CreatedOn"
                if ($CreatedOn -gt $nHoursAgo)
                    {
                        # User was created in the last 24 hours, do the things
                        $msg = "$Name was created on $CreatedOn"
                        $NewUserCount ++
                        $MessageBody = $MessageBody + "$msg `r`n"
                    }
                else
                    {
                        # user was created prior to 24 hours ago, do nothing
                    }
            } # End Foreach loop
    } # End Try
Catch
    {
        Write-Host An error occurred looping through the enumerated users.
        Write-Host $Error
        exit
    }



# Report the results
if (($NewUserCount -ge 0) -or ($MessageBody -ne ""))
    {
        Write-Host $NewUserCount users were created in the last 24 hours. `r`n
        Write-Host $MessageBody
    }
else
    {
        Write-Host No newly-created users were found.
    }
