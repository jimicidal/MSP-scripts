# Install/update Cisco Secure Client
This script is written for Datto RMM. It's intended to have four files attached to the "component" in Datto: the Cisco_Umbrella_Root_CA.cer root certificate, and the three .MSI files in the deployment package for the Secure Client core, Umbrella extension, and DART tool. You can also just put all those files in the same directory as the script.

The function to retrieve the Umbrella configuration details is blank. It contained proprietary information about an internal API, so you will need to use that space to retrieve your own secret from your own server. The data your looking for is just the contents of your orgInfo.json file.

Since this script requires you to manually download the deployment files, I will eventually be updating it to always fetch the current version from the web.