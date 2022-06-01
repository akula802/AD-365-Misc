# Script to gather user info from AD and export to a CSV file
# Used to collect user info for import into another system, could be useful elsewhere

# Import the required AD module
Import-Module ActiveDirectory


# Format for CSV:
# In Final CSV: FirstName, LastName, Email, Title, Department (add manually)
# Pull With Script: FirstName, Surname, Email, Description


# Get the user information
$requestorsFromAD =  Get-ADUser -Filter * -Properties GivenName,Surname,EmailAddress,Description,SamAccountName  `
            | Where-Object {$_.Enabled -eq $true} `
            | Where-Object {$_.EmailAddress.Length -gt 0}  ` # For this project, I only cared about active users with an Email property set
            | Sort-Object -Property SamAccountName


# Loop and format for CSV
$outputData = ForEach ($requestor in $requestorsFromAD)
    {
        Write-Host $requestor.GivenName $requestor.Surname $requestor.EmailAddress $requestor.Description

        New-Object -TypeName psobject -Property @{
            FirstName = $requestor.GivenName
            LastName = $requestor.Surname
            Email = $requestor.EmailAddress
            Title = $requestor.Description
        } | Select-Object FirstName,LastName,Email,Title

    } # End ForEach



#Write to CSV file
$outputData | Export-CSV -Path C:\temp\staff-all.csv
