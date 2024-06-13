On Error Resume Next

'#	This script will set your Outlook email signatures to a standard signature you define here.
'#  It works by building a Word object out of elements grabbed from Active Directory.
'#  You can use it how you like, but I used to call it from users' logon script batch file.
'#
'#	It's configured so you can pass one argument when you call the script to modify the signature output:
'#		sales	- Adds a line for the customer to call the 1800 number in an emergency
'#		am	- Adds a line about 1800 number and also to declare their regular office hours
'#
'#	JMS 2015-2022

''''Grab the argument(s) that were passed to the script, store them in the variable 'dept'
Set args = WScript.Arguments
blnArgs = False
If Not (WScript.Arguments.Count = 0) Then
	blnArgs = True
  dept = WScript.Arguments(0) 'The arguments are meant to represent the users' department
End If

''''Create user object from ADUC - just grab the entire thing
Set objSysInfo = CreateObject("ADSystemInfo")
strUser = objSysInfo.UserName
Set objUser = GetObject("LDAP://" & strUser)

''''Save just the parts of the user object you want to their own separate variables
''''In this case, we only care about the name, title, phone number, and office location
With objUser
	strName = .FullName
	strTitle = .Title
	strPhone = .TelephoneNumber
	strOffice = .OfficeLocations
End With

''''Prepare to build the signature body by creating a Word document
Set objWord = GetObject(, "Word.Application")
If objWord Is Nothing Then
	Set objWord = CreateObject("Word.Application")
  blnWord = True
End If

Set objDoc = objWord.Documents.Add()
Set objSelection = objWord.Selection
Set objEmailOptions = objWord.EmailOptions
Set objSignatureObjects = objWord.EmailOptions.EmailSignature
Set objSignatureEntries = objSignatureObjects.EmailSignatureEntries
objSelection.Style = "No Spacing"

''''Variables for the network location of the company logo image file, and department-specific optional text
''''Add any other signature elements here that you would like to reuse in the rest of the script
strLogo = "\\UNC\NETLOGON\Company Logo Email Signature.jpg"
strEmergencyNumber = "For 24/7 emergency service, please call 1 (800) 555-5555"

''''You can remove this whole if block, it just illustrates how to target a specific user with unique needs
If (strName = "Bobby Smith") Then
	With objSelection ''Set the font, write Bobby-specific text, add a link
		.Font.Name = "Arial"
		.Font.Size = 10
		.Font.Color = RGB(108, 115, 122)
		.Font.Bold = False
    .TypeText "Please send invoices to "
		.Hyperlinks.Add objSelection.Range, "mailto:accounting@company.com", , , "Accounting@Company.com"
	End With
	Set objSelection = objDoc.Range(objSelection.End - 23, objSelection.End) ''Select 23 spaces back from the end of the line
	With objSelection.Font ''Set the font of the curent text selection (Accounting@Company.com above)
		.Size = 10
		.Name = "Arial"
		.Color = RGB(108, 115, 122)
		.Underline = False
		.Bold = True
	End With
	Set objSelection = objWord.Selection
	objSelection.TypeText Chr(11) & Chr(11) ''Add two new lines/enter key/carriage return
End If


''''First line of standard signature - name, title, & phone number. Start by setting the text properties.
With objSelection ''Set the font to a gray color, 10pt bold Arial
	.Font.Name = "Arial"
	.Font.Size = 10
	.Font.Color = RGB(108, 115, 122)
	.Font.Bold = True
.TypeText strName ''Print the user's name
End With
If strTitle <> "" Then
	objSelection.TypeText "   " & strTitle ''If the user has a title in AD, type three spaces and then the title
End If
If strPhone <> "" Then
	objSelection.TypeText "   " & strPhone ''If the user has a phone number in AD, type three spaces and then the number
End If
objSelection.TypeText Chr(11) ''Go to the next line/enter key


''''Second line of standard signature. All users get this, no variables are checked.
With objSelection
	.Font.Bold = False
	.TypeText "Corporate Headquarters 1999 Best Birdy Road W, Minneapolis MN 55969" & Chr(11)
End With


''''Third line of standard signature. All users get this. This includes a link to the company's website
With objSelection
	.Font.Name = "Arial"
	.Font.Size = 10
	.Font.Color = RGB(108, 115, 122)
	.Font.Bold = False
	.TypeText "Eight years on the Inc. 500|5000 - "
	.Hyperlinks.Add objSelection.Range, "http://www.companyx.com", , , "www.companyx.com"
End With
''''Text is selected 20 spaces from the end of the line (the URL), and it's visual properties customized
Set objSelection = objDoc.Range(objSelection.End - 20, objSelection.End)
With objSelection.Font
	.Size = 10
	.Name = "Arial"
	.Color = RGB(108, 115, 122)
	.Underline = False
	.Bold = True
End With
Set objSelection = objWord.Selection
objSelection.TypeText Chr(11)


''''Account manager-specific additional line. Finally we check our passed argument, if it's there, to see if it's 'am'
	If (blnArgs = True) And (dept = "am") Then ''Set the font to a green color, 10pt bold Arial
		With objSelection.Font
			.Name = "Arial"
			.Size = 10
			.Color = RGB(30, 181, 58)
			.Bold = True
		End With
		If strOffice <> "" Then ''If the user has text in the Office field in ADUC, spit out the entire thing
			objSelection.TypeText "My office hours are " & strOffice & ". "
		End If
		objSelection.TypeText strEmergencyNumber & Chr(11)
	End If

''''Sales-specific additional line. If our passed argument is 'sales', we keep the green color, but write something else
	If (blnArgs = True) And (dept = "sales") Then
		With objSelection.Font
			.Name = "Arial"
			.Size = 10
			.Color = RGB(30, 181, 58)
			.Bold = True
		End With
		objSelection.TypeText strEmergencyNumber & Chr(11) ''This text was defined above where the path to the logo was set
	End If


''''Add the logo from a location all users can access. The path is defined further up so you can define these things all in one place
Set imgLogo = objSelection.InlineShapes.AddPicture(strLogo)
With imgLogo
	.ScaleHeight = 100
	.ScaleWidth = 100
End With


''''Now select the entire Word document you just built
Set objSelection = objDoc.Range()


''''Finally, adopt the signature for all messages
objSignatureEntries.Add "Main Signature", objSelection ''Add a signature called Main Signature consisting of the entire selection
With objSignatureObjects
	.NewMessageSignature = "Main Signature" ''Set the signature for new emails to the new Main Signature just created
	.ReplyMessageSignature = "Main Signature"
End With

objDoc.Close 0 ''Don't forget to clean up
If blnWord Then
	objWord.Quit
End If
