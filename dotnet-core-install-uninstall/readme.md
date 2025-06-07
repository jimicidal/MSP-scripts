# Install/uninstall .NET core
This script is written for Datto RMM. It's intended to have six installer files attached to the "component" in Datto. You'll find the filenames at the top of the script. Essentially, you'll want the installers for x64 ASP.NET, the .NET Windows hosting package, and both the x64 & x86 desktop and standalone packages. That gives you the option of deploying or removing any implementation of .NET core when you schedule the job.

You can also just put the installers in the same directory as the script if you're running it locally; just manually set your variables to select the packages you want and whether to install or uninstall.

In my Datto RMM instance, I have several components using this same script, with each one configured for a different major version of .NET core. This way I can deploy or remove the latest minor version of any major version 5-10. The separation cuts down on the number of attached files to wrangle for a single component and makes it easy to see from a device's activity history what versions were updated/installed/removed.

## Background
I've not found a good, reliable way to silently & remotely remove .NET core from endpoints in a variety of environments using pure PowerShell, some common removal tool, or any other built-in Windows functions. What I've found works best is to run the same version installer that the target enpdoint has installed, but with the `/uninstall` switch. The drawback, obviously, is that the executable file and installed .NET versions need to match.

## Installation
Attach the install files for the latest minor version of whichever major version you want to deploy. For example, all the installers for v8.0.16. Run your Datto job in installation mode to deploy fresh or to update an existing instance of that major version, e.g., 8.0.5 to 8.0.16.

## Removal
Since this method only works with install files that are of the exact same version of .NET core that the endpoint has installed, if your endpoints have varying minor versions of the major version you want to remove (e.g., 8.0.5, 8.0.9, etc.), you would have to run the script twice: once to update them all to the script's version 8.0.16 (or whichever installers you've downloaded and attached), and once more to perform the uninstall.
