# FixMyADMX

The main motivation for writing this script was the Citrix ADMX files. @AdamGrossTX has done a great job of finding and removing broken parts in the Citrix receiver.admx/adml files (see <https://github.com/AdamGrossTX/Toolbox/tree/master/Intune/ADMXIngestion> ). I took this as an opportunity to create a script that would do this manual process automatically, so that new releases would be fixed automatically. Here's what it does:

* Replace comboBox with textBox - comboBox is not supported by Intune
* Add explainText to all `<policy>` attributes, as this is also **required** albeit undocumented currently on the Intune learn page. Will fix 'Object reference not set to an instance of an object.'
* Remove the windows.admx reference if possible, otherwise skip only that step and continue with all other fixes while logging the reason
* Optional: Use `-UseCustomSupportedOn` to replace `windows:*` supportedOn references with a local `SUPPORTED_Windows` supportedOn definition, ensure `<supportedOn>` exists in `<policyDefinitions>`, and remove the windows.admx namespace import
* Optional: Use `-SupportedOnName` and `-SupportedOnString` together with `-UseCustomSupportedOn` to define your own supportedOn definition name and display text
* The script automatically increments the ADMX `policyDefinitions` `revision` minor version on every run; use `-IncrementMajorRevision` to increment major and reset minor to `0`

**ATTENTION**: This will **not** remediate other things mentioned in the official documentation.
Official documentation about importing ADMX to Intune: <https://learn.microsoft.com/en-us/mem/intune/configuration/administrative-templates-import-custom>

## Optional switch

Use this switch when you want to remove the `windows.admx` namespace even if `windows:*` references are in active use:

```powershell
.\FixMyADMX.ps1 -ADMXFileLocation 'C:\temp\FixMyADMX\UCC\UCClientPolicies.admx' -ADMLFileLocation 'C:\temp\FixMyADMX\UCC\UCClientPolicies.adml' -UseCustomSupportedOn
```

Note: `-UseCustomSupportedOn` defaults to definition name `SUPPORTED_Windows` and display string text `Windows`.

To use your own supportedOn definition name and custom string text:

```powershell
.\FixMyADMX.ps1 -ADMXFileLocation 'C:\temp\FixMyADMX\chrome.admx' -ADMLFileLocation 'C:\temp\FixMyADMX\chrome.adml' -UseCustomSupportedOn -SupportedOnName 'SUPPORTED_CustomWindows' -SupportedOnString 'Windows Custom'
```

To increment the ADMX major revision instead of minor:

```powershell
.\FixMyADMX.ps1 -ADMXFileLocation 'C:\temp\FixMyADMX\chrome.admx' -ADMLFileLocation 'C:\temp\FixMyADMX\chrome.adml' -IncrementMajorRevision
```
