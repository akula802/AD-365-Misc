# Script to bulk update the Description field (job title) for AD users in a specific OU
# In this example we needed to change the Sales dept users from 'Sales Rep' to 'Prod Slinger'


# Preflight
Import-Module ActiveDirectory


# Note: Get the OU path from the 'distinguishedName' attribute of the OU
$OUPath = "OU=Sales Dept,OU=Active Users,OU=Users,OU=FakeCo.local,DC=FakeCo,DC=local"


# Define the old and new description fields
$oldDescription = "Sales Rep"
$newDescription = "Prod Slinger"


# Get all the users in the OUPath whose descriptions match
$users = Get-ADUser -Filter * -SearchBase $OUpath -Properties SamAccountName,Description | Where-Object {$_.Description -EQ $oldDescription}


# Loop through the users and update the descriptions
ForEach ($user in $users)
    {
        #Write-Host $user.SamAccountName - $user.Description
        Set-ADUser -Identity $user.SamAccountName -Description $newDescription
    }

