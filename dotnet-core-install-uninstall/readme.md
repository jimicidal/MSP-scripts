# Install/uninstall .NET core
This script is written for Datto RMM. It's intended to have six installer files attached to the "component" in Datto. You'll find the filenames at the top of the script. Essentially, you'll want the installers for x64 ASP.NET, the .NET Windows hosting package, and both the x64 & x86 desktop and standalone packages. That gives you the option of deploying or removing any implementation of the software when you schedule the job.

You can also just put the installers in the same directory as the script if you're running it locally; just manually set your variables to choose the packages and whether to install or uninstall.

## Background
I've not found a good, reliable way to silently & remotely remove .NET core from endpoints in a variety of environments using pure PowerShell, some common removal tool, or any other built-in Windows functions. What I've found works best is to run the same version installer as is installed on the target enpdoint, but with the `/uninstall` switch. The drawback, obviously is that the file and installed versions need to match.

## Installation
Attach the install files for the latest minor version of whichever major version you want to deploy. For example, all the installers for v8.0.13. Run your Datto job in installation mode to deploy fresh or to update an existing instance of that major version, e.g., 8.0.5 to 8.0.13.

## Removal
Since this method only works with install files that are of the exact same version of .NET core that the endpoint has installed, if your endpoints have varying minor versions of the major version you want to remove (e.g., 8.0.5, 8.0.9, etc.), you would have to run the script twice: once to update them all to the script's version 8.0.13 (or whichever installers you've downloaded and attached), and once more to perform the uninstall.