# FixMyADMX

The main motivation for writing this script was the Citrix ADMX files. @AdamGrossTX has done a great job of finding and removing broken parts in the citrix.admx/adml files (see <https://github.com/AdamGrossTX/Toolbox/tree/master/Intune/ADMXIngestion> ). I took this as an opportunity to create a script that would do this manual process automatically, so that new releases would be fixed automatically. Here's what it does:

* Replace comboBox with textBox - comboBox is not supported by Intune
* Add explainText to all `<policy>` attributes, as this is also **required** albeit undocumented currently on the Intune learn page. Will fix 'Object reference not set to an instance of an object.'
* Remove the windows.admx reference if possible, otherwise return information on the usage of 'windows:' references in the log. This will be fixed by Microsoft in the future

**ATTENTION**: This will **not** remediate other things mentioned in the official documentation.
Official documentation about importing ADMX to Intune: <https://learn.microsoft.com/en-us/mem/intune/configuration/administrative-templates-import-custom>
