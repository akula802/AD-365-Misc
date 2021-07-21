# Script to return the date-time of a user's last logon

Import-Module ActiveDirectory

function Get-ADUserLastLogon([string]$userName)
{
  $dcs = Get-ADDomainController -Filter {Name -like "*"}
  $time = 0
  foreach($dc in $dcs)
  { 
    $hostname = "server1" #$dc.HostName
    $user = Get-ADUser $userName | Get-ADObject -Properties lastLogon 
    if($user.LastLogon -gt $time) 
    {
      $time = $user.LastLogon
    }
  }
  $dt = [DateTime]::FromFileTime($time)
  Write-Host $username "last logged on to $hostname at:" $dt }


# Now run the function
Get-ADUserLastLogon -UserName LeroyJenkins
