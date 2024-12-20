# Duo Accounts API Reporting
These PowerShell script generate useful reports about the child organizations in your Duo MSP tenant. It requires an Admin API and an Accounts API to be configured at the parent MSP account level. It works well, but there is still progress to be made - important things like avoiding hard-coded credentials are not observed here.

The `duo-accounts-api-reporting.ps1` script creates a folder structure in your output path of clientName > "Duo Security" > logYear > logMonth (e.g., d:\reports\Widgets-R-Us\Duo Security\2023\December). It massages the data received from Duo, generates some stylized HTML, then uses MSEdge.exe to print to PDF. Use your company's logo to make the reports more production-ready.

The `one-giant-csv.ps1` script just loops through all child accounts and dumps all users and last login date into one CSV. This can help you quickly identify any stale users that may need to be deleted, re-enrolled, etc.

I've not included mine here for obvious reasons, but you will need to provide your Duo Accounts API and Admin API details for this to work. More to come as I'm also working on making this into a proper c# app.

## Sample output
![Report Sample](https://github.com/jimicidal/MSP-scripts/blob/main/duo-accounts-api-reporting/Report%20sample.png?raw=true)
