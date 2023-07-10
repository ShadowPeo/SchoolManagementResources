$computers = Get-ADComputer -SearchBase "<<COMPUTER_OU>>" -Filter * -Properties managedBy,Description

foreach ($computer in $computers)
{
    if (($computer.Description).SubString(0,6) -eq "<<DOMAIN_NETBIOS>>")
    {
        Write-Host ($computer.Description).Substring(0,14)
        Set-ADComputer -Identity $computer.SamAccountName -ManagedBy ($computer.Description).Substring(0,14)
    }
    else 
    {
        Set-ADComputer -Identity $computer.SamAccountName -ManagedBy $null
    }
}