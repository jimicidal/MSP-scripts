# Duo Accounts API Reporting
This PowerShell script generates a UI to view child accounts in your MSP tenant. Selecting a child organization allows you to view information you would otherwise have to log into the web UI to find.

It's pretty bare-bones, but it works. I'm working on converting it to a proper C# app.

I've not included it here for obvious reasons, but you will need to provide your Duo Accounts API details for this to work. Specifically, set these three variables to their appropriate values:
- $Duo_host
- $Duo_skey
- $Duo_ikey