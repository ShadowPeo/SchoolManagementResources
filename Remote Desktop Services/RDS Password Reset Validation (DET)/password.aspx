<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="../Site.xsl"?>
<?xml-stylesheet type="text/css" href="../RenderFail.css"?>
<% @Page Language="C#" Debug="false" ResponseEncoding="utf-8" ContentType="text/xml" %>
<% @Import Namespace="System " %>
<% @Import Namespace="System.Security" %>
<% @Import Namespace="Microsoft.TerminalServices.Publishing.Portal.FormAuthentication" %>
<% @Import Namespace="Microsoft.TerminalServices.Publishing.Portal" %>
<% @Import Namespace="System.Web.Security.AntiXss" %>
<script language="C#" runat=server>

    //
    // Customizable Text
    //
    string L_CompanyName_Text = "Work Resources";

    //
    // Localizable Text
    //
    const string L_DomainUserNameLabel_Text = "CURRIC\\user name:";
    const string L_OldPasswordLabel_Text = "Current password:";
    const string L_NewPasswordLabel_Text = "New password:";
    const string L_ConfirmNewPasswordLabel_Text = "Confirm new password:";
    const string L_PasswordChangedLabel_Text = "Your password has been successfully changed.";
    const string L_OKButton_Text = "OK";
    const string L_ComplexityFailureLabel_Text = "Your new password does not meet the length, complexity, or history requirements of your domain. Try choosing a different new password.";
    const string L_NewPasswordsDontMatchLabel_Text = "The entered passwords do not match.";
    const string L_BlankPasswordFailureLabel_Text = "Please enter a new password.";
    const string L_PasswordChangeGenericFailure_Text = "Your password cannot be changed. Please contact your administrator for assistance.";
    const string L_LogonFailureLabel_Text = "The user name or password that you entered is not valid. Try typing it again.";
    const string L_SubmitLabel_Text = "Submit";
    const string L_CancelLabel_Text = "Cancel";
    const string L_RenderFailTitle_Text = "Error: Unable to display RD Web Access";
    const string L_RenderFailP1_Text = "An unexpected error has occurred that is preventing this page from being displayed correctly.";
    const string L_RenderFailP2_Text = "Viewing this page in Internet Explorer with the Enhanced Security Configuration enabled can cause such an error.";
    const string L_RenderFailP3_Text = "Please try loading this page without the Enhanced Security Configuration enabled. If this error continues to be displayed, please contact your administrator.";

    //
    // Page Variables
    //
    public string strErrorMessageRowStyle;
    public string strButtonsRowStyle;
    public bool bFailedLogon = false, bPasswordMismatchFailure = false, bPasswordBlankFailure = false, bComplexityFailure = false, bGenericFailure = false, bSuccess = false;
    public string sHelpSourceServer, sLocalHelp;
    public Uri baseUrl;

    void Page_PreInit(object sender, EventArgs e)
    {

        // Deny requests with "additional path information"
        if (Request.PathInfo.Length != 0)
        {
            Response.StatusCode = 404;
            Response.End();
        }

        // gives us https://<hostname>[:port]/rdweb/pages/<lang>/
        baseUrl = new Uri(new Uri(RequestHelper.GetOriginalRequestUri(Request), RequestHelper.GetRequestFilePath(Request)), ".");

        sLocalHelp = ConfigurationManager.AppSettings["LocalHelp"];
        if ((sLocalHelp != null) && (sLocalHelp == "true"))
        {
            sHelpSourceServer = "./rap-help.htm";
        }
        else
        {
            sHelpSourceServer = "http://go.microsoft.com/fwlink/?LinkId=141038";
        }
    }

    void Page_Load(object sender, EventArgs e)
    {
        string strPasswordChangeEnabled = ConfigurationManager.AppSettings["PasswordChangeEnabled"];

        if (strPasswordChangeEnabled == null || !(strPasswordChangeEnabled.Equals("true", StringComparison.CurrentCultureIgnoreCase)))
        {
            SafeRedirect(null);
        }
        
        if ( Request.QueryString != null )
        {
            NameValueCollection objQueryString = Request.QueryString;
            if ( objQueryString["Error"] != null )
            {
                if ( objQueryString["Error"].Equals("FailedLogon", StringComparison.CurrentCultureIgnoreCase) )
                {
                    bFailedLogon = true;
                }
                else if ( objQueryString["Error"].Equals("ComplexityFailed", StringComparison.CurrentCultureIgnoreCase) )
                {
                    bComplexityFailure = true;
                }
                else if (objQueryString["Error"].Equals("FailedBlankPassword", StringComparison.CurrentCultureIgnoreCase))
                {
                    bPasswordBlankFailure = true;
                }
                else if (objQueryString["Error"].Equals("FailedPasswordMatch", StringComparison.CurrentCultureIgnoreCase))
                {
                    bPasswordMismatchFailure = true;
                }
                else if (objQueryString["Error"].Equals("FailedGeneric", StringComparison.CurrentCultureIgnoreCase))
                {
                    bGenericFailure = true;
                }
                else if (objQueryString["Error"].Equals("PasswordSuccess", StringComparison.CurrentCultureIgnoreCase))
                {
                    bSuccess = true;
                }
            }
            if ( objQueryString["UserName"] != null )
            {
                DomainUserName.Value = SecurityElement.Escape(objQueryString["UserName"]); 
            }
            
            
        }
    }
    
    private void SafeRedirect(string strRedirectUrl)
    {
        string strRedirectSafeUrl = null;

        if (!String.IsNullOrEmpty(strRedirectUrl))
        {
            Uri baseUrl = RequestHelper.GetOriginalRequestUri(Request);
            Uri redirectUri = new Uri(new Uri(baseUrl, RequestHelper.GetRequestFilePath(Request)), strRedirectUrl);

            if (
                redirectUri.Authority.Equals(baseUrl.Authority) &&
                redirectUri.Scheme.Equals(baseUrl.Scheme)
               )
            {
                strRedirectSafeUrl = redirectUri.AbsoluteUri;   
            }

        }

        if (strRedirectSafeUrl == null)
        {
            strRedirectSafeUrl = "default.aspx";
        }

        Response.Redirect(strRedirectSafeUrl);       
    }

</script>
<RDWAPage 
    helpurl="<%=sHelpSourceServer%>" 
    workspacename="<%=AntiXssEncoder.XmlAttributeEncode(L_CompanyName_Text)%>" 
    baseurl="<%=SecurityElement.Escape(baseUrl.AbsoluteUri)%>"
    >
  <RenderFailureMessage>
    <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
            <meta http-equiv="Content-Type" content="text/html; charset=unicode"/>
            <title><%=L_RenderFailTitle_Text%></title>
        </head>
        <body>
            <h1><%=L_RenderFailTitle_Text%></h1>
            <p><%=L_RenderFailP1_Text%></p>
            <p><%=L_RenderFailP2_Text%></p>
            <p><%=L_RenderFailP3_Text%></p>
        </body>
    </html> 
  </RenderFailureMessage>

  <HTMLMainContent>
	<script language="javascript">
		document.getElementById("btnSignIn").disabled = true;
	</script>

    <script type="text/javascript" src="validation.js"></script>

      <form id="FrmLogin" name="FrmLogin" action="password.aspx" method="post">

        <table width="350" border="0" align="center" cellpadding="0" cellspacing="0">

            <tr>
            <td height="20">&#160;</td>
            </tr>
              <tr>
                    <td width="180" align = "right"> example: CURRIC\01234567</td>
                </tr>
            <tr>
            <td>
                <table width="350" border="0" cellpadding="0" cellspacing="0">
                <tr>
                    <td width="180" align="right"><%=L_DomainUserNameLabel_Text%></td>
                    <td width="7"></td>
                    <td align="right">
                    <input id="DomainUserName" name="DomainUserName" type="text" class="textInputField" runat="server" size="25" autocomplete="off" onfocusout="checkUsername();"/>
                    </td>
                </tr>
                <tr>
                    <td width="350" colspan="3" align="right"><span id="UsernameValid" color="#FF0000"></span></td>
                </tr>
                </table>
            </td>
            </tr>

            <tr>
            <td height="7"></td>
            </tr>

            <tr>
            <td>
                <table width="350" border="0" cellpadding="0" cellspacing="0">
                <tr>
                    <td width="180" align="right"><%=L_OldPasswordLabel_Text%></td>
                    <td width="7"></td>
                    <td align="right">
                    <input id="UserPass" name="UserPass" type="password" class="textInputField" runat="server" size="25" autocomplete="off" onfocusout="checkPassword(this);"/>
                    </td>
                </tr>
                <tr>
                    <td width="350" colspan="3" align="right"><span id="OldPasswordValid" color="#FF0000"></span></td>
                </tr>
                <tr>    
                        <td width="187" colspan="2"></td>
                        <td width="163" align="left"><span id="OldPasswordValidList" color="#FF0000"></span></td>
                </tr>
                </table>
            </td>
            </tr>

            <tr>
            <td height="7"></td>
            </tr>

            <tr>
            <td>
                <table width="350" border="0" cellpadding="0" cellspacing="0">
                <tr>
                    <td width="180" align="right"><%=L_NewPasswordLabel_Text%></td>
                    <td width="7"></td>
                    <td align="right">
                    <input id="NewUserPass" name="NewUserPass" type="password" class="textInputField" runat="server" size="25" autocomplete="off" onkeyup="checkPassword(this);"/>
                    </td>
                </tr>
                <tr>
                    <td width="350" colspan="3" align="right"><span id="PasswordValid" color="#FF0000"></span></td>
                </tr>
                <tr>    
                        <td width="187" colspan="2"></td>
                        <td width="163" align="left"><span id="PasswordValidList" color="#FF0000"></span></td>
                </tr>
                </table>
            </td>
            </tr>
            
            <tr>
            <td height="7"></td>
            </tr>

            <tr>
            <td>
                <table width="350" border="0" cellpadding="0" cellspacing="0">
                <tr>
                    <td width="180" align="right"><%=L_ConfirmNewPasswordLabel_Text%></td>
                    <td width="7"></td>
                    <td align="right">
                    <input id="ConfirmNewUserPass" name="ConfirmNewUserPass" type="password" class="textInputField" runat="server" size="25" autocomplete="off" onkeyup="checkConfirmPassword();" />
                    </td>
                </tr>
                <tr>
                    <td width="350" colspan="3" align="right"><span id="ConfirmValid" color="#FF0000"></span></td>
                </tr>
                </table>
            </td>
            </tr>
            
    <%
    strErrorMessageRowStyle = "style=\"display:none\"";
    if ( bGenericFailure == true )
    {
    strErrorMessageRowStyle = "style=\"display:\"";
    }
    %>
            <tr id="tr4" <%=strErrorMessageRowStyle%> >
            <td>
                <table>
                <tr>
                    <td height="20">&#160;</td>
                </tr>
                <tr>
                    <td><span class="wrng"><%=L_PasswordChangeGenericFailure_Text%></span></td>
                </tr>
                </table>
            </td>
            </tr>

    <%
    strErrorMessageRowStyle = "style=\"display:none\"";
    if (bPasswordBlankFailure == true)
    {
    strErrorMessageRowStyle = "style=\"display:\"";
    }
    %>
            <tr id="tr2" <%=strErrorMessageRowStyle%> >
            <td>
                <table>
                <tr>
                    <td height="20">&#160;</td>
                </tr>
                <tr>
                    <td><span class="wrng"><%=L_BlankPasswordFailureLabel_Text%></span></td>
                </tr>
                </table>
            </td>
            </tr>

    <%
    strErrorMessageRowStyle = "style=\"display:none\"";
    if ( bComplexityFailure == true )
    {
    strErrorMessageRowStyle = "style=\"display:\"";
    }
    %>
            <tr id="tr5" <%=strErrorMessageRowStyle%> >
            <td>
                <table>
                <tr>
                    <td height="20">&#160;</td>
                </tr>
                <tr>
                    <td><span class="wrng"><%=L_ComplexityFailureLabel_Text%></span></td>
                </tr>
                </table>
            </td>
            </tr>
    
    <%
    strErrorMessageRowStyle = "style=\"display:none\"";
    if (bPasswordMismatchFailure == true)
    {
    strErrorMessageRowStyle = "style=\"display:\"";
    }
    %>
            <tr id="tr3" <%=strErrorMessageRowStyle%> >
            <td>
                <table>
                <tr>
                    <td height="20">&#160;</td>
                </tr>
                <tr>
                    <td><span class="wrng"><%=L_NewPasswordsDontMatchLabel_Text%></span></td>
                </tr>
                </table>
            </td>
            </tr>

    <%
    strErrorMessageRowStyle = "style=\"display:none\"";
    if ( bSuccess == true )
    {
    strErrorMessageRowStyle = "style=\"display:\"";
    }
    %>
            <tr id="tr1" <%=strErrorMessageRowStyle%> >
            <td>
                <table align = "center">
                <tr>
                    <td height="20">&#160;</td>
                </tr>
                <tr>
                    <td><span class="wrng"><%=L_PasswordChangedLabel_Text%></span></td>
                </tr>
                <tr>
                    <td height="10">&#160;</td>
                </tr>
                <tr>
                    <td align = "center"><input type="button" class="formButton" id="OK" value="<%=L_OKButton_Text%>" onClick="window.location='login.aspx'"/></td>
                </tr>  
 
                </table>
            </td>
            </tr>

    <%
    strErrorMessageRowStyle = "style=\"display:none\"";
    if ( bFailedLogon == true )
    {
    strErrorMessageRowStyle = "style=\"display:\"";
    }
    %>
            <tr id="trErrorIncorrectCredentials" <%=strErrorMessageRowStyle%> >
            <td>
                <table>
                <tr>
                    <td height="20">&#160;</td>
                </tr>
                <tr>
                    <td><span class="wrng"><%=L_LogonFailureLabel_Text%></span></td>
                </tr>
                </table>
            </td>
            </tr>

    <%
    strButtonsRowStyle = "style=\"display:none\"";
    if ( bSuccess == false )
    {
        strButtonsRowStyle = "style=\"display:\"";
    }
    %>
            <tr>
            <td height="20">&#160;</td>
            </tr>
            <tr id="trButtons" <%=strButtonsRowStyle%> >
            <td align="right"><label><input type="submit" class="formButton" id="btnSignIn" value="<%=L_SubmitLabel_Text%>" /></label><label><input type="button" class="formButton" id="Cancel" value="<%=L_CancelLabel_Text%>" onClick="window.location='login.aspx'"/></label>
            </td>
            </tr>


            <tr>
            <td height="30">&#160;</td>
            </tr>

        </table>

      </form>

  
  </HTMLMainContent>
</RDWAPage>
