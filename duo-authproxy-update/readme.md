# Duo Authproxy Update
This script audits the health of your Duo Authentication Proxy installation. It will optionally fix certain issues based on the variables you pass to it. The script is written for Datto RMM, so input variables are declared at the component configuration screen and the values passed to the script are defined when you create the job.

The variables to configure in DattoRMM are all checkboxes:
- UpdateNeeded
- ExtraFiles
- BadFailmode
- EncryptionNeeded