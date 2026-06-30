# Changes

## June 2026

- Change: Detection of active `windows:` references no longer blocks other fixes. The script now skips only the windows namespace removal step and continues.
- Add: New optional `-UseCustomSupportedOn` switch to replace `windows:*` supportedOn references with a local `SUPPORTED_Windows` definition and remove the windows namespace import.
- Change: Removed the `-UseWindowsSupportedOnName` parameter because `-UseCustomSupportedOn` now defaults to `Windows`.
- Add: New optional `-SupportedOnName` + `-SupportedOnString` parameters (used with `-UseCustomSupportedOn`) to define a custom supportedOn definition and corresponding ADML string entry.
- Add: The ADMX `policyDefinitions` `revision` now increments minor version on each run; `-IncrementMajorRevision` increments major and resets minor to `0`.
- Change: `-UseCustomSupportedOn` now defaults to supportedOn definition name `SUPPORTED_Windows` and string text `Windows` when no custom values are provided.
- Fix: When custom supportedOn mode is used, the output now always ensures a `<supportedOn>` section in `<policyDefinitions>` with a matching ADML string entry.
- Fix: Corrected explainText fallback parameter usage and improved explainText attribute/log handling.

## August 2025

- Fix: MN-EckeD provided a method to fix [#3](https://github.com/MHimken/FixMyADMX/issues/3)
- Update: Updated receiver.admx/.adml to 2503.

## June 2025

- Fix: Paths missing a trailing slash a now properly handled
- Add: Will now cleanup working files if no changes were done
- Update: Updated example files with their respective latest versions

## May 2025

- Fix: Removing the windows.admx failed if PowerShell 7 was used because 'select-string' returned a non-null value

## August 2024

- Update: Citrix receiver example
- Note: The citrix receiver example was modified additionally _by hand_ to not require the citrix base ADMX

## April 2024

- Add: Examples
- Fix: Minor textual fixes

## August 2023

- Initial Version
