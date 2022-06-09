#Disco ICT User Details Plugin - User AD Details through Intermediary MSSQL server

This is to pull certain fields from Active Directory (AD) through and intermediate SQL server by connecting AD to the SQL server as a linked server using the Active Directory Services Interface (ADSI), using that data to create a view (I put mine into the Disco database itself) and then pulling those details into Disco through the Custom SQL Provider setting in the User Details plugin.

[Disco ICT](https://discoict.com.au) Software from [Gary Sharp](https://github.com/garysharp) that is used to simply the management of school ICT resources

ADSI is a bit of a weird beast, its provided to allow for devolopers to interact with AD, and in this case we are going to use it to list all the users as defined by an OU string. The issue here is that by default page size is 1000, which works out to be 901 usable rows of data when pulled through the ADSI connection, if you have less than this in the number of potential users your going to pull at once, all is fine otherwise you will need to modify the maximum pagesize. It is possible to use things like joins to get around this pagentation issue however for most networks that is superflous changing the maximum allowed rows to something like 5000 is easy enough to do

**Using NTDSUtil to allow for more that 901 rows**

On a machine that has Active Directory tools installed run as a user that has Domain Admin right the ntdsutil(.exe).

Upon opening the utility we will need to connect to a domain controller, set the new max page size, and commit the changes, the instructions below will set it to 5000, please be aware that you need to replace <\<ServerName\>> with the actual DNS name of the server, an IP address will simply be rejected.

NTDSUTIL.exe

LDAP policies\
connections\
connect to server <\<SERVERNAME\>>\
q\
Set MaxPageSize to 5000\
commit\
q\


**Linking AD to MSSQL Server**

Once we can rely on AD to return enough rows we now need to link the AD server to Active Directory, to this end we need to run a script on the SQL server itself. Download and run the script Create-ADSI.sql on your SQL server (I use SQL Management Studio but feel free to use whatever your comfortable with). Replace <\<Username\>> with the username of a user that has the appropriate permissions and <\<Password\>> with the password for that user.\


**Creating the View**

Inside a database of your choice (ensure that the appropriate user has db_datareader permissions to the database, the user is DiscoServiceAccount if your using intergrated authetication as recomended) I put the view in the Disco SQL database so that I do not have to worry about these things.

The code to create the view that I used is included in View.sql please replace the list selection and the OU path with a path appropriate for your school.

**Adding To Disco**

Ok we now have all the piece aligned so go the User Details plugin in Disco and select User Details, with a provier of Custom SQL Database. Fill in the details as required, then use a TSQL statement to get the data, I used spaces in my View column names so I need to put square brackets around them, I will correct this ultimatly but not short term. The gotcha here is that the first column MUST be UserID and the second column MUST be TimeStamp. After it does not matter except for the fact the order you call them in, is the order they are diplsayed in. As I have no timestamp for last modified in this view I simply used the GetDate() \[TimeStamp\] function to get the current date/time as TimeStamp so the caching does not kick in. My code for this segment was

SELECT \[UserID\], GETDATE() \[Timestamp\], \[User Type\], \[Department\], \[Class\], \[Title\], \[AUP Status\], \[CASES Status\] from userADDetails WHERE UserId=@UserId;

