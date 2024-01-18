# Script to find user accounts with 'password never expires' set to True, and sets it to False
# Intended to prevent accounts from having eternal passwords


###############################
##### PREFLIGHT - LOGGING #####
###############################

# Current timestamp, formatted
$begin_timestamp = Get-Date -Format "yyyy-MM-dd_HH:mm:ss"

# Check and/or create the log directory
cd "C:\Scripts\UserPwCheck"
$log_directory = "$PWD\UserPwCheckLog"
if (!(Test-Path -Path $log_directory)) {
    New-Item -Path $PWD -Name "UserPwCheckLog" -ItemType Directory | Out-Null
}

# Check and/or create the log file
$log_file = "$log_directory\runlog.txt"
if (!(Test-Path -Path $log_file)) {
    $create_logfile_msg = "####################`r`n$begin_timestamp`r`nCreated log file.`r`n####################"
    Write-Host $create_logfile_msg
    $create_logfile_msg | Out-File -FilePath "$PWD\UserPwCheckLog\runlog.txt" -Encoding UTF8
}

# Start the log for this run
$start_run_msg = "`r`n==================================`r`nScript started at $begin_timestamp"
Write-Host $start_run_msg
$start_run_msg | Out-File -FilePath "$PWD\UserPwCheckLog\runlog.txt" -Encoding UTF8 -Append



#########################################
##### PREFLIGHT - INITIAL VARIABLES #####
#########################################

# Build a list of all domain controllers
$dc_list = (Get-ADDomainController -Filter * | Select Hostname).Hostname



##########################################
##### PREFLIGHT - REUSABLE FUNCTIONS #####
##########################################

# This function is the only way to get an accurate LastLogon timestamp for an AD user
Function Get-UserLastLogin() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$UserSID,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [string[]]$DCList
    )

    # Build a list of all Domain Controllers if none provided
    if (!($DCList)) {
        $DCList = (Get-ADDomainController -Filter * | Select Hostname).Hostname
    }

    # Build a list of all LastLogon values stored by each DC
    $all_logins = @()
    ForEach ($DC in $DCList) {
        $user_last_login_value = [datetime]::FromFileTime((Get-ADUser -Identity $UserSID -Server $DC -Properties * | Select LastLogon).LastLogon)
        $all_logins += $user_last_login_value
    }

    # Return the most recent LastLogon value
    $user_last_login = ($all_logins | Sort-Object -Descending) | Select-Object -First 1
    return $user_last_login

} # End function Get-UserLastLogin



Function Update-ScriptLogFile() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$LogFilePath,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$LogMessage
    )

    # Sanity-Check to make sure the log exists
    if (!(Test-Path -Path $LogFilePath)) {
        $fn_fail_msg = "Log fine was not found at $LogFilePath"
        return $fn_fail_msg
    }

    # Write the message
    $LogMessage | Out-File -FilePath $LogFilePath -Encoding UTF8 -Append


} # End function Update-ScriptLogFile



######################################
##### PREFLIGHT - MODULE IMPORTS #####
######################################

# Import the required module(s), fail if unable
$required_modules = ('ActiveDirectory')

ForEach ($module in $required_modules) {
    Try {
        $Error.Clear()
        Import-Module $module -ErrorAction Stop
        $import_module_success_msg = "Imported $module successfully."
        Write-Host $import_module_success_msg
        Update-ScriptLogFile -LogFilePath $log_file -LogMessage $import_module_success_msg
    }
    
    Catch {
        $import_module_fail_msg = "Exception when importing the $module module. Is it installed?"
        Write-Error $import_module_fail_msg
        Update-ScriptLogFile -LogFilePath $log_file -LogMessage $import_module_fail_msg
        exit
    }

} # End ForEach $module



##########################
##### THE MAIN EVENT #####
##########################

# Collect current AD user list
Try {
        # Clear $Error
        $Error.Clear()

        # UPDATE THIS FOR YOUR USER SEARCH NEEDS
        $users = Get-ADUser -Filter {Name -notlike '*mailbox*'} `
            -Properties Enabled, DistinguishedName, SID, SamAccountName, Name, GivenName, Surname, EmailAddress, PasswordNeverExpires, LastLogonDate `
            | Select-Object PasswordNeverExpires, Enabled, DistinguishedName, SamAccountName, EmailAddress, SID `
            | Where-Object {$_.DistinguishedName -notlike "*OU=*Service Account*"} `
            | Where-Object {$_.DistinguishedName -notlike "*OU=Disabled*"} `
            | Where-Object {$_.Enabled -eq $true}  `
            | Where-Object {$_.PasswordNeverExpires -eq $true}
    }

catch {
        # Update the log with details and exit
        $get_ad_users_error_msg = "::: An error occurred trying to enumerate AD users. Exception details to follow:"
        Write-Host $get_ad_users_error_msg
        Update-ScriptLogFile -LogFilePath $log_file -LogMessage $get_ad_users_error_msg

        $fail_timestamp = Get-Date -Format "yyyy-MM-dd_HH:mm:ss"
        Write-Host $Error
        Update-ScriptLogFile -LogFilePath $log_file -LogMessage $Error

        $fail_end_msg = "`r`nScript failed at $fail_timestamp`r`n=================================="
        Write-Host $fail_end_msg
        Update-ScriptLogFile -LogFilePath $log_file -LogMessage $fail_end_msg
        exit
    }



# Get the most recent logon timestamp for the user
ForEach ($user in $users) {

    Try {
        # Clear $Error
        $Error.Clear()

        # Use the provided function and the $dc_list collected earlier
        $last_login = Get-UserLastLogin -UserSID $user.SID -DCList $dc_list

        # Add the ActualLastLogon value to the $user in $users
        Add-Member -InputObject $user -MemberType NoteProperty -Name ActualLastLogon -Value $last_login

        ### BEGIN CRITICAL ACTION ###
        # Flip the 'PasswordNeverExpires' property to FALSE
        Try {
            Set-ADUser -Identity $user.SID -PasswordNeverExpires $false
            $user_updated_msg = $user.SamAccountName + " ::: PasswordNeverExpires was changed to FALSE ::: Last Login: $last_login"
            Write-Host $user_updated_msg
            Update-ScriptLogFile -LogFilePath $log_file -LogMessage $user_updated_msg
        }

        Catch {
            # If the script fails to change the property, log the details and exit
            $user_update_fail_msg = "FAILED to update PasswordNeverExpires property for " + $user.SamAccountName + ". Error message to follow:"
            Write-Host $user_update_fail_msg
            Update-ScriptLogFile -LogFilePath $log_file -LogMessage $user_update_fail_msg

            Write-Host $Error
            Update-ScriptLogFile -LogFilePath $log_file -LogMessage $Error

            $fail_timestamp = Get-Date -Format "yyyy-MM-dd_HH:mm:ss"
            $user_update_fail_end_msg = "`r`nScript failed at $fail_timestamp`r`n=================================="
            Write-Host $user_update_fail_end_msg
            Update-ScriptLogFile -LogFilePath $log_file -LogMessage $user_update_fail_end_msg
            exit

        }
        ### END CRITICAL ACTION ###

    } # End main Try

    Catch {
        # Update the log with details and exit
        $user_SAM = $user.SamAccountName
        $get_last_login_error_msg = "An error occurred trying to get the last login for $user_sam. Exception details to follow:"
        Write-Host $get_last_login_error_msg
        Update-ScriptLogFile -LogFilePath $log_file -LogMessage $get_last_login_error_msg

        $fail_timestamp = Get-Date -Format "yyyy-MM-dd_HH:mm:ss"
        Write-Host $Error
        Update-ScriptLogFile -LogFilePath $log_file -LogMessage $Error

        $get_last_login_fail_end_msg = "`r`nScript failed at $fail_timestamp`r`n=================================="
        Write-Host $get_last_login_fail_end_msg
        Update-ScriptLogFile -LogFilePath $log_file -LogMessage $get_last_login_fail_end_msg
        exit
    } # End main Catch

} # End ForEach $user in $users



######################
##### WRAP IT UP #####
######################

#Write-Host $users_final
$finish_success_timestamp_for_filename = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$finish_success_timestamp_for_log = Get-Date -Format "yyyy-MM-dd_HH:mm:ss"

# Export the results, if there are any
$total_users_affected = $users.Count
if ($total_users_affected -gt 0) {
    $users | Export-Csv -Path "$log_directory\users-pw-never-expires__$finish_success_timestamp_for_filename.csv" -Force
}
else {
    # No users found, set counter to 0
    $total_users_affected = 0
}

# Update the log
$finish_success_msg = "There were $total_users_affected users found with never-expiring passwords.`r`nScript finished successfully at $finish_success_timestamp_for_log`r`n=================================="
Write-Host $finish_success_msg
Update-ScriptLogFile -LogFilePath $log_file -LogMessage $finish_success_msg



##########################
##### CLEANUP / EXIT #####
##########################

# Keep only 10 of the most recent CSV files. Delete the oldest.
$csv_files = Get-ChildItem -Path $log_directory -Filter "*.csv" -ErrorAction SilentlyContinue

if ($csv_files.Length -gt 10) {

    # Get the LastWriteTime of the 10th oldest file. This is the threshhold.
    $csv_threshhold = (($csv_files | Sort-Object -Property LastWriteTime -Descending)[9]).LastWriteTime

    ForEach ($csv in $csv_files) {
        if ($csv.LastWriteTime -lt $csv_threshhold) {
            Remove-Item $csv -Force -ErrorAction SilentlyContinue
        }
    }
} # End $csv_files.Length -gt 10

Write-Host `r`nCleaned up oldest CSV files.



# Archive the log files when > 1 MB. Only keep 1 archive
if (($log_file.Length / 1MB) -gt 1) {

    $archive_log = "$log_directory\runlog.archive"

    if (Test-Path -Path $archive_log) {
        Remove-Item -Path $archive_log -Force
    }

    Rename-Item -Path $log_file -NewName "runlog.archive" -Force
    Write-Host Archived the log file due to the 1MB size limit.
}
