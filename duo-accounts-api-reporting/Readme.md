# Duo Accounts API Reporting
This PowerShell script generates useful reports about the child organizations in your Duo MSP tenant. It requires an Admin API and an Accounts API to be configured at the parent MSP account level. It works well, but is still a work in progress - so important things like avoiding hard-coded credentials are not observed here.

The script creates a folder structure in your output path of clientName > "Duo Security" > logYear > logMonth (e.g., d:\reports\Widgets-R-Us\Duo Security\2023\December). It massages the data received from Duo, generates some stylized HTML, then uses MSEdge.exe to print to PDF. Use your company's logo to make the reports production-ready.

I've not included it here for obvious reasons, but you will need to provide your Duo Accounts API and Admin API details for this to work. More to come as I'm also working on making this into a proper c# app.