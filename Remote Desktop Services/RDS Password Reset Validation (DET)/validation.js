var userDomain = "CURRIC";
var pwdMinLength=8;
var pwdRequiredComplexity = 3;
var pwdSymbols = true;
var pwdUpperCase = true;
var pwdLowerCase = true;
var pwdDigits = true;

function checkPassword(field)
{   
    var statusField = "";
    var listField = "";
    if (field.getAttribute('name') == "NewUserPass")
    {
        statusField = "PasswordValid";
        listField = "PasswordValidList";
    }
    else if (field.getAttribute('name') == "UserPass")
    {
        statusField = "OldPasswordValid";
        listField = "OldPasswordValidList";
    }

    if ((pwdUpperCase + pwdLowerCase + pwdDigits + pwdSymbols) >= pwdRequiredComplexity)
    {
        var newPass = document.forms["FrmLogin"][field.getAttribute('name')].value;

        if (newPass.length >= pwdMinLength)
        {
            newPassUpper = /[A-Z]/.test(newPass);
            newPassLower = /[a-z]/.test(newPass);
            newPassNumber = /\d/.test(newPass);
            newPassSymbol = /\W/.test(newPass);

            if ((newPassUpper + newPassLower + newPassNumber + newPassSymbol) < pwdRequiredComplexity)
            {
                document.getElementById(statusField).innerHTML = "<b><font color=\"#FF0000\">Password Complexity not achieved, must be;<\/b><\/font>";
                document.getElementById(listField).innerHTML = "<b><font color=\"#FF0000\"><ul><li>8 characters minimum<\/li> <li>Upper Case<\/li><li>Lower Case<\/li><li>Numbers<\/li><li>Symbols<\/li><\/ul><\/b><\/font>";
                document.getElementById("btnSignIn").disabled = true;
            }
            else
            {
                if (field.getAttribute('name') == "NewUserPass")
                {
                    if (document.forms["FrmLogin"]['NewUserPass'].value == document.forms["FrmLogin"]['UserPass'].value)
                    {
                        document.getElementById("PasswordValid").innerHTML = "<b><font color=\"#FF0000\">Password Cannot Match Previous Password<\/b><\/font>";
                        document.getElementById("btnSignIn").disabled = true;
                    }
                    else{
                        document.getElementById("btnSignIn").disabled = false;
                        document.getElementById(statusField).innerHTML = "";
                        document.getElementById(listField).innerHTML = "";
                    }
                }
                else{
                    document.getElementById("btnSignIn").disabled = false;
                    document.getElementById(statusField).innerHTML = "";
                    document.getElementById(listField).innerHTML = "";
                }
            }

        }
        else
        {
            document.getElementById(statusField).innerHTML = "<b><font color=\"#FF0000\">Password Complexity not achieved, must be;<\/b><\/font>";
            document.getElementById(listField).innerHTML = "<b><font color=\"#FF0000\"><ul><li>8 characters minimum<\/li> <li>Upper Case<\/li><li>Lower Case<\/li><li>Numbers<\/li><li>Symbols<\/li><\/ul><\/b><\/font>";
            document.getElementById("btnSignIn").disabled = true;
        }
    }
    else
    {
        window.alert("Required Complexity Cannot Be Achieved, Please see Script Maintainer");
        document.getElementById("btnSignIn").disabled = true;
    }

}

function checkConfirmPassword()
{
    if(document.forms["FrmLogin"]["ConfirmNewUserPass"].value != document.forms["FrmLogin"]["NewUserPass"].value)
    {
        document.getElementById("ConfirmValid").innerHTML = "<b><font color=\"#FF0000\">Passwords do not match, please correct<\/b><\/font>";
        document.getElementById("btnSignIn").disabled = true;
    }
    else
    {
        document.getElementById("ConfirmValid").innerHTML = "";
        document.getElementById("btnSignIn").disabled = false;
    }
}

function checkUsername() 
{ 
    var username = document.forms["FrmLogin"]["DomainUserName"].value;
    if(username == "" || username==null ) {
        document.getElementById("UsernameValid").innerHTML = "<b><font color=\"#FF0000\">Username is not valid, please check the example<\/b><\/font>";
        document.getElementById("btnSignIn").disabled = true;
        //document.getElementById("DomainUserName").focus();
    }
    else 
    {
        if(username.length == 15)
        {
            var userDomainFilterCorrect = new RegExp(userDomain+"\\\\\\d{8}","gi");
            var userDomainFilterForwardSlash = new RegExp(userDomain+"\/\\d{8}","gi");;
            if (userDomainFilterCorrect.test(username))
            {
                    //Do Nothing, Username is Valid Staff
                    document.getElementById("UsernameValid").innerHTML = "";
                    document.getElementById("btnSignIn").disabled = false;
            }
            else if (userDomainFilterForwardSlash.test(username))
            {
                    //Valid Staff with forward slash not backward slash
                    document.forms["FrmLogin"]["DomainUserName"].value = document.forms["FrmLogin"]["DomainUserName"].value.replace(/\/+/g, '\\');
                    //Reset var for further processing
                    username = document.forms["FrmLogin"]["DomainUserName"].value;
                    document.getElementById("UsernameValid").innerHTML = "";
                    document.getElementById("btnSignIn").disabled = false;
            }
            else
            {
                //Otherwise alert its not a valid id
                document.getElementById("UsernameValid").innerHTML = "<b><font color=\"#FF0000\">Username is not valid, please check the example<\/b><\/font>";
                //document.getElementById("DomainUserName").focus();
                document.getElementById("btnSignIn").disabled = true;
            }
        }
        else if(username.length == 14)
        {
            var userDomainFilterCorrect = new RegExp(userDomain+"\\\\([A-Z]{2}[A-Z-]{1}\\d{4})","gi");
            var userDomainFilterForwardSlash = new RegExp(userDomain+"\/([A-Z]{2}[A-Z-]{1}\\d{4})","gi");
            if (userDomainFilterCorrect.test(username))
            {
                //Do Nothing Username is Valid Student
                document.getElementById("UsernameValid").innerHTML = "";
                document.getElementById("btnSignIn").disabled = false;
            }
            else if (userDomainFilterForwardSlash.test(username))
            {
                //Valid Student with forward slash not backward slash
                document.forms["FrmLogin"]["DomainUserName"].value = document.forms["FrmLogin"]["DomainUserName"].value.replace(/\/+/g, '\\');
                //Reset var for further processing
                username = document.forms["FrmLogin"]["DomainUserName"].value;
                document.getElementById("UsernameValid").innerHTML = "";
                document.getElementById("btnSignIn").disabled = false;
            }
            else
            {
                //Otherwise alert its not a valid id
                document.getElementById("UsernameValid").innerHTML = "<b><font color=\"#FF0000\">Username is not valid, please check the example<\/b><\/font>";
                //document.getElementById("DomainUserName").focus();
                document.getElementById("btnSignIn").disabled = true;
            }
        }
        else if (username.length == 8)
        {   
            //Is it a staff ID
            if (username.match(/\d{8}/gi))
            {
                //If it is add domain
                document.forms["FrmLogin"]["DomainUserName"].value = "CURRIC\\"+document.forms["FrmLogin"]["DomainUserName"].value;
                //Reset var for further processing
                username = document.forms["FrmLogin"]["DomainUserName"].value;
                document.getElementById("UsernameValid").innerHTML = "";
                document.getElementById("btnSignIn").disabled = false;
            }
            else
            {
                //Otherwise alert its not a valid id
                document.getElementById("UsernameValid").innerHTML = "<b><font color=\"#FF0000\">Username is not valid, please check the example<\/b><\/font>"; 
                //document.getElementById("DomainUserName").focus();
                document.getElementById("btnSignIn").disabled = true;
            }
        }
        else if (username.length == 7)
        {
            //Is it a student ID?
            if (username.match(/[A-Z]{2}[A-Z-]{1}\d{4}/gi))
            {
                //If it is add a domain
                document.forms["FrmLogin"]["DomainUserName"].value = "CURRIC\\"+document.forms["FrmLogin"]["DomainUserName"].value;
                //Reset var for further processing
                username = document.forms["FrmLogin"]["DomainUserName"].value;
                document.getElementById("UsernameValid").innerHTML = "";
                document.getElementById("btnSignIn").disabled = false;
            }
            else
            {
                //Otherwise alert its not a valid id
                document.getElementById("UsernameValid").innerHTML = "<b><font color=\"#FF0000\">Username is not valid, please check the example<\/b><\/font>";
                //document.getElementById("DomainUserName").focus();
                document.getElementById("btnSignIn").disabled = true;
            }
        }
        else
        {
            document.getElementById("UsernameValid").innerHTML = "<b><font color=\"#FF0000\">Username is not valid, please check the example<\/b><\/font>";
            //document.getElementById("DomainUserName").focus();
            document.getElementById("btnSignIn").disabled = true;
        }
    }
}