# Database Integration Configuration Data File - SAMPLE
# Copy this file to Config.psd1 and update the values for your environment
# This file contains shared configuration variables used across multiple database integration scripts

@{
    # Database server hostname or IP address for SQL Server connection
    server = "YOUR_SQL_SERVER"
    
    # Database name containing student information system data
    database = "YOUR_DATABASE_NAME"
    
    # Active Directory organizational unit path specifically for student accounts
    studentSearchBase = "OU=Students,OU=Users,OU=YourSchool,DC=YourDomain,DC=com"
}
