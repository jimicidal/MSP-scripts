# AuthLite install/update
AuthLite wants you to deploy their MSI via Group Policy. When a new version comes out, you have to update the GPO. You should probably just run this script instead - it will fetch whatever the latest version is (if an update is needed) each time you run it.

Per [AuthLite documentation](https://www.authlite.com/docs/2_5/id_1599938970), DCs needs to be updated first. You can install right over top of the existing instance. Then you can bring member servers and workstations up to the same version.

This script is intended to run as a Datto RMM component. Add a Boolean variable in the component's config called 'IgnoreInstalledVersionNumber'. The checkbox added by Datto will allow you to force an update if the script determines that no update is needed. Alternatively, you can manually set `$ForceUpdate` to `$true` or `$false` in the script.
