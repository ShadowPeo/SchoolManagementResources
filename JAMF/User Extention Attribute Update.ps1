$url = "https://$tennantURL/JSSResource/usergroups/name/Students%20-%20Year%2004"
    
    $headers = @{
        Authorization = "Bearer $token"
        Accept = "application/json"
    }
    
    $apiQuery = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ContentType "application/json;charset=UTF-8"

$users = $apiQuery.user_group.users

$headers = @{
    Authorization = "Bearer $token"
    Accept = "application/json"
}

foreach ($user in $users)
{
#    $headers.Accept = "application/xml"
#    $jamfUser = $null
#    $userURL = "https://$tennantURL/JSSResource/users/email/$($user.email_address)"
#    $jamfUser = (Invoke-WebRequest -Method Get -Uri $url -Headers $headers -ContentType "application/xml;charset=UTF-8").Content
#    Write-Host $jamfUser
#    Pause
    $body="	
    <user>
        <extension_attributes>
            <extension_attribute>
            <name>Graduation Year</name>
            <value>2025</value>
            </extension_attribute>
        </extension_attributes>
    </user>
    "
    $url = "https://$tennantURL/JSSResource/users/email/$($user.email_address)"
    Invoke-WebRequest -Method Put -Uri $url -Headers $headers -ContentType "application/xml;charset=UTF-8" -Body $body
}


<#

$headers = @{
        Authorization = "Bearer $token"
        Accept = "application/xml"
    }



$body="	
<user>
    <extension_attributes>
        <extension_attribute>
        <name>Graduation Year</name>
        <value>2028</value>
        </extension_attribute>
    </extension_attributes>
</user>
"



#$userID = $null
#$userID = ($users | WHERE-OBJECT name -eq "TEST@DOMAIN" | Select-Object id).id
$url = "https://$tennantURL/JSSResource/users/email/TEST@DOMAIN"


$response = Invoke-WebRequest -Method Put -Uri $url -Headers $headers -ContentType "application/xml;charset=UTF-8" -Body $body


#$response = Invoke-WebRequest -Method Get -Uri $url -Headers $headers -ContentType "application/xml;charset=UTF-8"
#<id>3</id>
#<value>2028</value>
#>