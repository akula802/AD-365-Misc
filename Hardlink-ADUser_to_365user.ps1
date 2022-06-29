# Script to "hard-link" an on-premises AD user to a Microsoft 365 user, where Azure ADSync was misconfigured
# In this case, the synced AD account is different / separate from the cloud-only 365 account
# Steps revised and tested with the help of a Microsoft support representative


#########################################################################
#############  ENTER THE USER'S ORIGINAL INFORMATION HERE  ##############
#########################################################################

$localADuserOriginalSAM = "firstnameLastname"
$originalOU = "Sales"
$userNewUPN = "lastNameFirstInitial" # The UPN after the merge... should match the user's current email, which is lastNameFirstInitial

#########################################################################
#########################################################################
#########################################################################


# Get the individual, local AD user object from on-premises AD
$localADuser = Get-ADUser -Identity $localADuserOriginalSAM
$userGUID = $localADuser.ObjectGUID.Guid
$userOldUPN = $localADuser.UserPrincipalName
#$usersOldSAMname = $localADuser.SamAccountName



# Store some OU information for later
$originalOUDN = "OU=$originalOU,OU=Active Users,OU=Users,OU=FakeCo.local,DC=FakeCo,DC=local"



# 1. Move AD user account to the 'Lost & Found' OU, which does not sync to AzA/365 (verify in your env)
$userOldUPN | Move-ADObject -TargetPath "CN=LostAndFound, DC=FakeCo, DC=local"



# 2. Run a Delta or Initial sync, then PAUSE the syncing temporarily
    # Code WIP



# Store Office 365 Global Admin Creds and connect to MS online
Import-Module MsOnline
$credential = Get-Credential
Connect-MsolService -Credential $credential



# 3. The AD user should now be in the 365 users Recycle Bin - delete it from there
Remove-MsolUser -UserPrincipalName $userOldUPN -RemoveFromRecycleBin



# 5. Convert the AD user's GUID to an ImmutableID used by 365/AzAD
    # Test user's GUID: 1a3568b3-824b-479d-9f17-a2ca6dedaec8
    # Test user's GUID converted ImmutableID: s2g1GkuCnUefF6LKbe2uyA==
$userImmutableID = [Convert]::ToBase64String([guid]::New($userGUID).ToByteArray())



# 6. Apply the converted GUID to the 365 user as the ImmutableID
Set-MsolUser -UserPrincipalName $userNewUPN -ImmutableId $userImmutableID



# 7. Change the UPN of the AD user to match the email address of the cloud/365 user
    # Code WIP



# 8. Move the AD user back to the appropriate OU
$userNewUPN | Move-ADObject -TargetPath $originalOUDN



# 9. Re-enable the ADSync
    # Code WIP



# 10. Have the user sign in with the new UPN and make sure Outlook and other data are still present

