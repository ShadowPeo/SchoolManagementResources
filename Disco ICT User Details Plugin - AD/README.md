#Disco ICT User Details Plugin - User AD Details through Intermediary MSSQL server

This is to pull certain fields from Active Directory (AD) through and intermediate SQL server by connecting AD to the SQL server as a linked server using the Active Directory Services Interface (ADSI), using that data to create a view (I put mine into the Disco database itself) and then pulling those details into Disco through the Custom SQL Provider setting in the User Details plugin.

[Disco ICT](https://discoict.com.au) Software from [Gary Sharp](https://github.com/garysharp) that is used to simply the management of school ICT resources

ADSI is a bit of a weird beast, its provided to allow for devolopers to interact with AD, and in this case we are going to use it to list all the users as defined by an OU string. The issue here is that by default page size is 1000, which works out to be 901 usable rows of data when pulled through the ADSI connection, if you have less than this in the number of potential users your going to pull at once, all is fine otherwise you will need to modify the maximum pagesize. It is possible to use things like joins to get around this pagentation issue however for most networks that is superflous changing the maximum allowed rows to something like 5000 is easy enough to do

**Using NTDSUtil to Allow for more that 901 rows**

On a machine that has Active Directory tools installed run as a user that has Domain Admin right the ntdsutil(.exe).

Upon opening the utility we will need to connect to a domain controller, set the new max page size, and commit the changes, the instructions below will set it to 5000, please be aware that you need to replace <\<ServerName\>> with the actual DNS name of the server, an IP address will simply be rejected.

NTDSUTIL.exe
LDAP policies
connections
connect to server <\<SERVERNAME\>>
q
Set MaxPageSize to 5000
commit
q

