# .NET core maintenance
This script is written for Datto RMM. It will fetch installers from microsoft.com to execute any install or uninstall tasks you select at runtime. You can also manually set your runtime preferences in the script to decide what it does when running it locally on a device. The procedures this script can perform are outlined below - it will also run an end-of-life date check for the installed products before it exits.

This has not been tested with .NET Core versions lower than 5. It's also not meant to work with preview editions as you're likely not running them in production anyway. When channel 10 is no longer in preview, you should be able to just add it to the channel selection field in the component configuration screen of Datto RMM to deploy it with this script.

# Available procedures
- Install
    - Installs the latest version available from the channel you choose. This does not currently install version other than the latest, but could potentially be modified to deploy a specific version if you request one at runtime (I'll probably end up adding this feature).
- Update
    - Installs any newer versions available for each installed product. This keeps everything within the same channel, it will not install e.g., v9 over v8.
- Upgrade to channel
    - Audits your installed products to replace them with the latest available version in the channel you selected. It will upgrade e.g., v6 products to v8 and leave v9 products alone.
- Audit EOL dates
    - Checks end-of-life dates for the products you have installed. It will report expired products and those expiring within 90 days. Since the script already does this regardless of which other procedure you select, this is essentially a read-only option (unless you also chose the InputRemoveEOLVersions option at runtime).
- Keep latest
    - Checks for multiple versions of the same installed products and removes all but the one with the highest version number.
- Uninstall channel
    - Removes all products from the channel you choose. E.g., SDK, Desktop, x86/x64 etc. in channel 7.0.
- Uninstall specific version
    - Surgical removal based on the product/version/architecture you specify.
- Uninstall all
    - Yup.
- RemoveEOLVersions
    - This is a checkbox in Datto RMM outside of the selections above, so you can choose if you want it to run after any of the other procedures. It will perform the EOL audit and remove anything that has expired. Maybe you already have a current channel installed alongside an EOL one and want to run the Update procedure while getting rid of the old one? It's possible to install an EOL product this way and then remove it in the same run, so not sure how much sense this makes 🤷‍♂️

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
- InputArchitecture (Selection)
    - win-x64
    - win-x86
    - x64 and x86
- InputSpecificVersion (Text box)
    - BLANK, but a valid input would be a full version number, e.g., 8.0.16
- InputRemoveEOLVersions (Boolean)
    - $true
    - $false

# Background
I've not found a good, reliable way to silently & remotely remove .NET core from endpoints in a variety of environments using pure PowerShell, some common removal tool, or any other built-in Windows functions. What I've found works best is to run the same version installer for the product installed on the target enpdoint with the `/uninstall` switch.
