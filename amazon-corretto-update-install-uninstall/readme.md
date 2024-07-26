# Amazon Corretto Update/Install/Uninstall
This script is intended to run as a Datto RMM component. You can also adjust the "runtime preference" variables section to modify the script's behavior manually or some other way.

Depending on what action you want the script to take, it will:
- Update all installed instances of Amazon Corretto
  - E.g., v8 x86 jre, v8 x64 jre, v17 x86 jdk, & v17 x64 jdk
  - Other runtime preferences are ignored
- Install whatever version you specify using the other runtime options
  - If you try to install JRE for a version that doesn't have it, you will get JDK instead
- Uninstall all installed instances of Amazon Corretto
  - Other runtime preferences are ignored

The variables to configure in DattoRMM are all combo boxes:
- Action
  - Update
  - Install
  - Uninstall
- Version
  - 8
  - 11
  - 17
  - 21
  - 22
- Architecture
  - x64
  - x86
- Edition
  - jdk
  - jre
