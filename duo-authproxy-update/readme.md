# Duo Authproxy Update
The `duo-authproxy-update.ps1` script audits the health of your Duo Authentication Proxy installation. It will optionally fix certain issues based on the variables you pass to it. The script is written for Datto RMM, so input variables are declared at the component configuration screen and the values passed to the script are defined when you create the job.

The variables to configure in DattoRMM are all checkboxes:
- UpdateNeeded
- ExtraFiles
- BadFailmode
- EncryptionNeeded

## Update on boot
The `update-on-boot.ps1` script is an update-only version; it skips the config file checks above. Since it doesn't need variables configured as a Datto component, it can just be run as-is on any PC. This version of the script creates a scheduled task which will run on boot and expire after 7 days. When the task is triggered, it will run another script created by this script to perform the update.
