# .NET core maintenance
This script is written for Datto RMM - use the "component setup" section below to configure the component's "variables". The code will fetch installers from microsoft.com to install or uninstall products based on the procedure you requested. To run it outside the Datto RMM platform, just set your runtime preferences in the testing section around line 450. The procedures this script can perform are outlined below.

Untested with preview editions and .NET Core versions lower than 5!

# Available procedures
- Install
    - Installs the latest version available from the channel you choose.
- Update
    - Installs any available updates for each installed product. This keeps everything within the same channel; it will not move you to channel 10, for example, if you have 8 installed.
- Upgrade to channel
    - Replaces installed products with the latest version in the target channel. It will upgrade e.g. channel 6 products to channel 8, but leave channel 10 products alone.
- Audit EOL dates
    - Checks end-of-life dates for the products you have installed. It will report expired products and any that are expiring within 90 days. Since the script already does this regardless of which procedure you select, this is essentially a read-only run of the script (unless you also chose the InputRemoveEOLVersions option at runtime).
- Keep latest
    - Checks for multiple versions/instances of the same installed products and removes all but the one with the highest version number.
- Uninstall channel
    - Removes all products from the channel you choose. E.g., removes SDK, Desktop, x86/x64 etc. in channel 7.0.
- Uninstall specific version
    - Surgical removal of an installed product based on the product/version/architecture you specify.
- Uninstall all
    - Web hosting bundles, SDKs, ASP.NET, all of it.
- RemoveEOLVersions
    - This is a checkbox in Datto RMM, outside of the combo box selections above. It will perform the EOL audit and remove anything that has already expired. Good for when you have a current channel installed alongside EOL channels and want to run the Update procedure while getting rid of the old stuff.

# Datto RMM component setup
- InputProcedure (Selection)
    - Install
    - Update
    - Upgrade to channel
    - Audit EOL dates
    - Keep latest
    - Uninstall channel
    - Uninstall specific version
    - Uninstall all
- InputProduct (Selection)
    - Hosting bundle
    - ASP.NET runtime
    - Desktop runtime
    - Standalone runtime
    - SDK
- InputChannel (Selection)
    - 5.0
    - 6.0
    - 7.0
    - 8.0
    - 9.0
    - 10.0
- InputArchitecture (Selection)
    - win-x64
    - win-x86
    - x64 and x86
- InputSpecificVersion (Text box)
    - BLANK, but a valid input would be a full version number, e.g., 10.0.11
- InputRemoveEOLVersions (Boolean)
    - $true
    - $false

# Background
I found myself needing to constantly update or remove specific versions of .NET core in response to vulnerability findings. Installing a new version over top sometimes cleans up the old version, but not always. I've not found a reliable, scalable way to clean up the old stuff using pure PowerShell, some common removal tool, or any other built-in Windows functions. What I've found works best is to run the same version installer with the `/uninstall` switch. Using this script in Datto RMM has been a good solution for 10k+ endpoints across hundreds of different clients.
