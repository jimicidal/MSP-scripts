# Amazon Corretto Update/Install/Uninstall
This script is intended to run as a Datto RMM component. That means you can set up "variables" in the Datto component config to modify how the script runs when you schedule the job. Alternatively, you can adjust the "runtime preference" variables section of the script to modify its behavior manually or some other way.

Depending on what action you want the script to take, it will:
- Update all installed instances of Amazon Corretto
  - E.g., v8 x86 jre, v8 x64 jre, v17 x86 jdk, & v17 x64 jdk
  - Other runtime preferences are ignored
- Install whatever version you specify using the other runtime options
  - If you try to install JRE for a version that doesn't have it, you will get JDK instead
- Uninstall all installed instances of Amazon Corretto
  - Other runtime preferences are ignored
- Uninstall all installed versions of Java before performing any of the above

The variables to configure in DattoRMM are below. I've included the default selections I set for what I think are the most common use cases:
- Action (Selection)
  - Update (Default)
  - Install
  - Uninstall
- Version (Selection)
  - 8 (Default)
  - 11
  - 17
  - 21
  - 22
- Architecture (Selection)
  - x64 (Default)
  - x86
  - x64 and x86
- Edition (Selection)
  - jdk
  - jre (Default)
- RemoveJava (Boolean)
  - True
  - False (Default)