# Script to check for changes in AD admin security groups
# Intended for use alongside an RMM, to alert on changes (admins added or removed)
# Writes to and reads from a file - this could be encrypted for added security later



# First, make sure the OS is at least Server 2008 R2 or higher
# This will also only work in the PowerShell version is 2.0 or higher
$psVersion = $PSVersionTable.PSVersion.Major
$osName = Get-WmiObject win32_operatingsystem | Select-Object -ExpandProperty Caption
$osversion =  (Get-WmiObject win32_operatingsystem | select -ExpandProperty version).Replace(".","")
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


# Now that we've checked the versions
Import-Module ActiveDirectory


# Declare some initial variables
$groups = "Domain Admins", "Enterprise Admins"
$userListFile = "C:\ProgramData\Scripts\DomainAdmins-members.txt"
$timestamp = Get-Date -Format yyyy-MM-dd_HH:mm:ss
$tempMessageFile = "C:\ProgramData\Scripts\tempMsg.txt"



########### DEFINE THE FUNCTIONS #########################################################################


Function GetADGroupMembers() {

    try
        {
            # Clear the $error variabkle
            $error.Clear()

            # Create a global string variable
            $global:currentMembers = ""

             # Loop through the goups named in the $groups list
            ForEach($group in $groups)
                {
                    # To get all the group members
                    $members = (Get-ADGroupMember -Identity $group | Select-Object -ExpandProperty Name | Out-String).Trim()

                        # Now loop through all the group members
                        Foreach ($member in $members)
                            {
                                # And add the names to $membersAll if not already there
                                if ($global:currentMembers -notcontains $member)
                                    {
                                        $global:currentMembers += "`r`n$member"
                                    }
                            }
                } # End Foreach $group loop


                # After the loop, trim the leading white space from the global string variable
                $global:currentMembers = $global:currentMembers.Trim()



            # Yes, this is stupid, but necessary to ensure utf8 encoding of all variables
            $tempCurrentMembersFile = "C:\ProgramData\Scripts\tempCurrentMembers.txt"
            [system.io.file]::WriteAllText($tempCurrentMembersFile, $global:currentMembers,[text.encoding]::utf8)
            $global:currentMembersUTF8 = Get-Content $tempCurrentMembersFile -Encoding utf8
            Remove-Item $tempCurrentMembersFile
        }
    catch
        {
            Write-Host Something terrible happened checking group membership.
            Write-Host $error
            exit
        }

} # End function GetADGroupMembers



Function CompareGroupMembers(){

    if (Test-Path $userListFile)
        {
            $originalMembers = Get-Content $userListFile -Encoding utf8
            #$originalMembers = [system.io.file]::ReadAllText($userListFile, [System.Text.Encoding]::UTF8)
            #Write-Host `r`nOriginals:`r`n$originalMembers`r`n`r`n
            $changedMembers = (Compare-Object -ReferenceObject $originalMembers -DifferenceObject $global:currentMembersUTF8)
            if ($changedMembers -Eq $null)
                {
                    Write-Host No changes to admin group membership were detected.
                }
            else
                {
                    # Begin writing the change message to a temporary file
                    $timestampLog = "$timestamp`r`n"
                    $timestampLog | Out-File $tempMessageFile -Encoding utf8
                    $headerLog = "The following membership changes were recorded in the admin security groups:`r`n "
                    $headerLog | Out-File $tempMessageFile -Append utf8

                    # Loop through the change results (members added or removed)
                    ForEach ($member in $changedMembers)
                        {
                            if (($member | Select-Object -ExpandProperty SideIndicator) -eq "=>")
                                {
                                    $addedUser = ($member | Select-Object -ExpandProperty InputObject) + " was ADDED"
                                    $addedUser | Out-File $tempMessageFile -Append utf8
                                }
                            elseif (($member | Select-Object -ExpandProperty SideIndicator) -eq "<=")
                                {
                                    $removedUser = ($member | Select-Object -ExpandProperty InputObject) + " was REMOVED"
                                    $removedUser | Out-File $tempMessageFile -Append utf8
                                }
                        } # End ForEach loop


                        # Update the reference list
                        Clear-Content $userListFile
                        [system.io.file]::WriteAllText($userListFile, $global:currentMembers,[text.encoding]::utf8)
                        $footerMsg = "`r`nUpdated the list for the next membership check."
                        $footerMsg  | Out-File $tempMessageFile -Append utf8


                        # Prepare the message to return to Labtech, and remove the temp file
                        $changeResultMessage = (Get-Content $tempMessageFile -Encoding utf8) -join "`n"
                        Write-Host $changeResultMessage
                        Remove-Item $tempMessageFile -Force

                } # End else / changes detected

        } # End if file exists block

    else
        {
            # User list / reference file was deleted or otherwise not found
            # First, create a new list file
            [system.io.file]::WriteAllText($userListFile, $global:currentMembers,[text.encoding]::utf8)

            # Begin writing the change message to the console and to a message file
            $timestampLog = "$timestamp`r`n"
            $timestampLog | Out-File $tempMessageFile -Encoding utf8
            $headerLog = "The reference file was deleted. Current members of the @groupName@ security group:`r`n "
            $headerLog | Out-File $tempMessageFile -Append utf8


            # Loop through the security group members
            ForEach ($member in $currentMembers)
                {
                    $currentUser = $member
                    $currentUser | Out-File $tempMessageFile -Append utf8
                            
                } # End ForEach loop


                # Footer message
                $footerMsg = "`r`nCreated a new list for the next membership check."
                $footerMsg  | Out-File $tempMessageFile -Append utf8


                # Prepare the message to return to Labtech, and remove the temp file
                $changeResultMessage = (Get-Content $tempMessageFile) -join "`n"
                Write-Host $changeResultMessage
                Remove-Item $tempMessageFile -Force
        }

} # End function CompareGroupMembers



########### SET THE STAGE FOR THE BIG SHOW ###############################################################


# Before starting, check to see if the existing $userListFile was last written to prior to October 2017
# There were some earlier tests of this script that should not have been mass-deployed :-P
# If you're not me, comment out the following 11 lines
if (Test-Path $userListFile)
    {
        $lastTouch = Get-ItemProperty -Path $userListFile | Select-Object -ExpandProperty LastWriteTime
        $targetDate = [datetime]"10/5/2017"

        if($lastTouch -lt $targetDate)
            {
                Remove-Item $userListFile
                Write-Host Detected an old userListFile and removed it.
            }
    }


# Also, remove any remnant tmpMsg file if it exists (sanity check)
if (Test-Path -Path $tempMessageFile)
    {
        Remove-Item $tempMessageFile -Force
    }



########### EXECUTE THE FUNCTIONS #########################################################################


# Call the above functions
GetADGroupMembers
CompareGroupMembers

