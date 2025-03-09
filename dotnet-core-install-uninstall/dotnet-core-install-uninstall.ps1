# Version number of the attached files
$InstallerVersion = '8.0.13'

# Runtime preferences - these must be configured in the Datto component config
$RequestedProductType   =   $env:ProductType    # Selection - Desktop/Standalone/Hosting bundle
$Requestedx64           =   $env:x64            # Boolean   - $true/$false
$Requestedx86           =   $env:x86            # Boolean   - $true/$false
$RequestedAction        =   $env:Action         # Selection - Uninstall/Install
$RequestedIncludeASP    =   $env:IncludeASP     # Boolean   - $true/$false

# Attached files - this script relies on .exe installers attached to the Datto component
$ASPInstaller           = "aspnetcore-runtime-$InstallerVersion-win-x64.exe"
$Runtimex64Installer    = "dotnet-runtime-$InstallerVersion-win-x64.exe"
$Runtimex86Installer    = "dotnet-runtime-$InstallerVersion-win-x86.exe"
$Desktopx64Installer    = "windowsdesktop-runtime-$InstallerVersion-win-x64.exe"
$Desktopx86Installer    = "windowsdesktop-runtime-$InstallerVersion-win-x86.exe"
$HostingBundleInstaller = "dotnet-hosting-$InstallerVersion-win.exe"

# Validate our inputs - whether x64/x86/both architectures were selected
if (($Requestedx64 -eq $false) -and ($Requestedx86 -eq $false) -and ($RequestedProductType -ne 'Hosting bundle')) {
    write-host 'No architecture selected. Please choose either the x64 and/or x86 versions.'
    exit 1
  }

# Validate our inputs - whether the desktop or standalone deployments were selected
if ($RequestedProductType -eq 'Desktop') {
  $x64Installer = $Desktopx64Installer
  $x86Installer = $Desktopx86Installer
} elseif ($RequestedProductType -eq 'Standalone') {
  $x64Installer = $Runtimex64Installer
  $x86Installer = $Runtimex86Installer
} elseif ($RequestedProductType -eq 'Hosting bundle') {
  $x64Installer = $HostingBundleInstaller
} else {
  write-host 'No product type selected. Please choose between the desktop version, standalone runtime, or Windows hosting bundle.'
  exit 1
}

# Set arguments for the installer depending on whether we want to install or remove the product
if ($RequestedAction -eq 'Install') {
  write-host "Job configured to install the $RequestedProductType product."
  $ChosenArgs = "/install /quiet /norestart"
} else {
  write-host "Job configured to uninstall the $RequestedProductType product."
  $ChosenArgs = "/uninstall /quiet /norestart"
}

# Run the .NET core x64 installer with our arguments if requested
if (($Requestedx64 -eq $true) -and ($RequestedProductType -ne 'Hosting bundle')) {
  try {
    write-host 'Processing x64 version...'
    Start-Process -FilePath ".\$x64Installer" -ArgumentList $ChosenArgs -wait
    write-host 'OK'
  } catch {
    write-host 'Failed.'
    write-host $_
    $ProcedureFailed = $true
  }
}

# Run the .NET core x86 installer with our arguments if requested
if (($Requestedx86 -eq $true) -and ($RequestedProductType -ne 'Hosting bundle')) {
  try {
    write-host 'Processing x86 version...'
    Start-Process -FilePath ".\$x86Installer" -ArgumentList $ChosenArgs -wait
    write-host 'OK'
  } catch {
    write-host 'Failed.'
    write-host $_
    $ProcedureFailed = $true
  }
}

# Run the Hosting bundle installer if requested with the same install/uninstall arguments
if ($RequestedProductType -eq 'Hosting bundle') {
   try {
    write-host 'Processing Hosting bundle...'
    start-process ./$x64Installer -argumentlist $ChosenArgs -wait
    write-host 'OK'
  } catch {
    write-host 'Failed.'
    write-host $_
    $ProcedureFailed = $true
  }
}

# Run the ASP installer if requested with the same install/uninstall arguments
if ($RequestedIncludeASP -eq $true) {
   try {
    write-host 'Processing ASP.NET...'
    start-process ./$ASPInstaller -argumentlist $ChosenArgs -wait
    write-host 'OK'
  } catch {
    write-host 'Failed.'
    write-host $_
    $ProcedureFailed = $true
  }
}

if ($ProcedureFailed) {
  exit 1
}