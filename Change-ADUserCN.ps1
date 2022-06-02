# Change the canonical name (cn) in AD

# First find the user
$user = get-aduser -filter {SurName -like "lastName"}

# Then do the rename
Rename-ADObject -Identity $user -NewName "firstName lastName"
