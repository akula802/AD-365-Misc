# Updated 2/9/2022
# Script to check for changes in AD admin security groups
# Intended to run often as a scheduled task or from an RMM
# Writes to and reads from a text file - this file could be encrypted for added security later
# It also creates and deletes some temporary files - necessary to ensure UTF8 encoding on all string variables when using the script in a crappy RMM
# https://github.com/akula802/AD-365-Misc/edit/main/Monitor-ADAdminsChanges.ps1



# First, make sure the OS is at least Server 2008 R2 or higher
# This will also only work in the PowerShell version is 2.0 or higher
$psVersion = $PSVersionTable.PSVersion.Major
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



# Now that we've checked the versions, import the AD module (required)
Import-Module ActiveDirectory



# Declare some initial variables
$groups = "Domain Admins", "Enterprise Admins"
$userListFile = "C:\ProgramData\Scripts\admins.txt"
$tempMessageFile = "C:\ProgramData\Scripts\tempMsg.txt"
$timestamp = Get-Date -Format yyyy-MM-dd_HH:mm:ss



# Before starting, remove any remnant tmpMsg file if it exists (sanity check)
if (Test-Path -Path $tempMessageFile)
    {
        Remove-Item $tempMessageFile -Force
    }



########### DEFINE THE FUNCTIONS #########################################################################

# Define the Send-Alert function
Function Send-Alert() {
    [CmdletBinding()]
    Param(
        #[stirng]$To,
        #[string]$From,
        [String]$Subject,
        [string]$Body
    ) # End param

    # Do the things
    Try
        {
            $Error.Clear()

            # Define the credential object
            $username = "<username>"
            $password = ConvertTo-SecureString '<sendgrid API key>' -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($username, $password)

            # Define the message
            $alertRecipients = @('admin1@company.com', 'ticketing@company.com')
            $alertFrom = 'sec-alerts@company.com'
            $subjectLine = $subject
            $MsgBody = $body

            # Send the message
            Send-MailMessage -To $alertRecipients -From $alertFrom -Subject $subjectLine -Body $MsgBody -SmtpServer "smtp.sendgrid.net" -Port 587 -Credential $credential -UseSSL

            # State the obvious
            Write-Host Alert was posted to Slack.
            return
        }

    Catch
        {
            Write-Host Something bad happened trying to post the alert.
            Write-Host $Error
            return
        }


} # End function Send-Alert




Function GetADGroupMembers() {

    try
        {
            # Clear the $error variable
            $error.Clear()

            # Create a string variable
            $currentMembers = ""

             # Loop through the goups named in the $groups list
            ForEach ($group in $groups)
                {
                    # To get all the group members
                    $members = Get-ADGroupMember -Identity $group | Select-Object -ExpandProperty Name

                        # Now loop through all the group members
                        ForEach ($member in $members)
                            {
                                # State the member name and the name of the group
                                $memberPlusGroup = "$member" + " ($group)"

                                # And add the names to $currentMembers if not already there
                                if ($script:currentMembers -notmatch $memberPlusGroup)
                                    {
                                        $currentMembers += "`r`n$memberPlusGroup"
                                    }
                            } # End foreach member loop

                } # End Foreach $group loop


                # After the loop, trim the leading white space from the string variable
                #$currentMembers = $currentMembers.Trim()
                #Write-Host $currentMembers



            # Yes, this temp file stuff is stupid, but Labtech
            # Create the temp file
            $tempCurrentMembersFile = "C:\ProgramData\Scripts\tempCurrentMembers.txt"
            if (!(Test-Path $tempCurrentMembersFile)) {New-Item -Path $tempCurrentMembersFile}
            
            # Write the currentMembers data to it
            [system.io.file]::WriteAllText($tempCurrentMembersFile, $currentMembers,[text.encoding]::utf8)
            
            # Create a SCRIPT scoped variable with the UTF8 data - will be used by the next function so scoping is necessary
            $script:currentMembersUTF8 = Get-Content $tempCurrentMembersFile -Encoding utf8
            
            # get rid of the temp file
            Remove-Item $tempCurrentMembersFile
        }
    catch
        {
            # An exception occurred, unlikely but you never know
            Write-Host Something terrible happened checking group membership.
            Write-Host $error
            exit
        }

} # End function GetADGroupMembers




Function CompareGroupMembers(){

    if (Test-Path $userListFile)
        {
            # Get the admin group members from the file, these were the members at last run time
            $originalMembers = Get-Content $userListFile -Encoding utf8
            
            # Get the current members, from the query executed seconds ago in the previous function
            $changedMembers = (Compare-Object -ReferenceObject $originalMembers -DifferenceObject $script:currentMembersUTF8)
            
            # Compare them
            if ($null -Eq $changedMembers)
                {
                    # File matches current query, so no changes
                    Write-Host No changes to admin group membership were detected.
                }
            else
                {
                    # The values were different, so there WERE changes made since last run
                    # Begin writing the change message to a temporary file
                    if (!(Test-Path $tempMessageFile)) {New-Item -Path $tempMessageFile}
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


                        # Update the reference list file
                        Clear-Content $userListFile
                        [system.io.file]::WriteAllText($userListFile, $script:currentMembers,[text.encoding]::utf8)
                        $footerMsg = "`r`nUpdated the list for the next membership check."
                        $footerMsg  | Out-File $tempMessageFile -Append utf8

                        # Prepare the message to return, and remove the temp message file
                        $changeResultMessage = (Get-Content $tempMessageFile -Encoding utf8) -join "`n"
                        Write-Host $changeResultMessage

                        # Lastly, send the alert
                        Send-Alert -Subject "ALERT: Change Detected in AD Admin Group" -Body $changeResultMessage

                        # Clean up remaining temp files
                        Remove-Item $tempMessageFile -Force

                } # End else / changes detected

        } # End if file exists block

    else
        {
            # User list / reference file was deleted or otherwise not found
            # Therefore, no comparison is possible, let's just create a new member list for the next run
            # First, create a new list file
            [system.io.file]::WriteAllText($userListFile, $script:currentMembers,[text.encoding]::utf8)

            # Begin writing the change message to the console and to a temporary message file
            $timestampLog = "$timestamp`r`n"
            if (!(Test-Path $tempMessageFile)) {New-Item -Path $tempMessageFile}
            $timestampLog | Out-File $tempMessageFile -Encoding utf8
            $headerLog = "The reference file was deleted. Current members of the priveleged security groups:`r`n "
            $headerLog | Out-File $tempMessageFile -Append utf8


            # Loop through the security group members
            ForEach ($member in $script:currentMembers)
                {
                    $currentUser = $member
                    $currentUser | Out-File $tempMessageFile -Append utf8
                            
                } # End ForEach loop


                # Footer message
                $footerMsg = "`r`nCreated a new list for the next membership check."
                $footerMsg  | Out-File $tempMessageFile -Append utf8


                # Prepare the message to return, and remove the temp message file
                $changeResultMessage = (Get-Content $tempMessageFile) -join "`n"
                Write-Host $changeResultMessage
                Remove-Item $tempMessageFile -Force
        }

} # End function CompareGroupMembers




########### CALL THE FUNCTIONS ###########################################################################

# Let the show begin :-)
GetADGroupMembers
CompareGroupMembers
