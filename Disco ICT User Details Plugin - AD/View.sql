SELECT SAMAccountName AS 'UserID', employeeType AS 'User Type', department AS 'Department', physicalDeliveryOfficeName AS 'Class', title AS 'Title', userAUPStatus AS 'AUP Status', userCASESStatus AS 'CASES Status' FROM OpenQuery (
[ADSI],
'SELECT SAMAccountName, employeeType, department, physicalDeliveryOfficeName, title, userAUPStatus, userCASESStatus
FROM ''LDAP://OU=Staff Users,DC=myschool,DC=wan''
WHERE objectClass = ''user''
AND NOT objectClass = ''computer''
'
) AS tblADS