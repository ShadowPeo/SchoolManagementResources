$tennantURL = "<<JAMF TENNANT URL>>" #No Protocol
$jamfUser = "<<JAMF TENNANT USER>>" # User with API access and access to required data fields
$jamfPass = "<<JAMF TENNANT USER PASSWORD>>" #Password for Above User

$studentCSV = "<<CURRENT CASES DATA>>" #User data, assumes use of the eduhub export script
$upnDomain = "<<UPN DOMAIN>>" #lead with the @ symbol so that if using on a non UPN system the symbol can be blank or something else
$requiredRatio = 2 #The ratio required to maintain so for 1:2 the number is 2

#Snipe Variables
$snipeAPIKey = "my.snipe.APIKey"
$snipeURL = "https://my.snipe.url" #No Trailing /

#Powershell Universal Variables
$psuURI = "http://my.powershelluniversal.api.url" #URI of the Powershell Universal Server