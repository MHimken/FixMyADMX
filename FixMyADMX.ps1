#requires -version 7
<#
.SYNOPSIS
This script will *attempt* to fix common issues in ADMX files so they can be uploaded to Intune
.DESCRIPTION
The main motivation for writing this script was the Citrix ADMX files. AdamGrossTX has done a great job of finding and removing broken parts in the 
citrix.admx/adml files (see https://github.com/AdamGrossTX/Toolbox/tree/master/Intune/ADMXIngestion ). I took this as an opportunity to create a script 
that would do this manual process automatically, so that new releases would be fixed automatically. Here's what it does:
* Replace comboBox with textBox - comboBox is not supported by Intune
* Add explainText to all <policy> attributes, as this is also **required** albeit undocumented currently on the Intune learn page. 
* Remove the windows.admx reference if possible, otherwise return information on the usage of 'windows:' references in the log. This will be fixed by Microsoft in the future

ATTENTION: This will not remediate other things mentioned in the official documentation.
Official documentation about importing ADMX to Intune: https://learn.microsoft.com/en-us/mem/intune/configuration/administrative-templates-import-custom

ATTENTION: I highly recommend to change the version number once you have fixed your ADMX. It will make changes more visible in Intune.
More information:
* https://github.com/MHimken/FixMyADMX
* https://manima.de/2023/08/fixmyadmx-will-prepare-your-admx-for-intune
.PARAMETER ADMXFileLocation
Provide one .admx file at a time - make sure it matches the ADML file
.PARAMETER ADMLFileLocation
Provide one .adml file at a time - make sure it matches the ADMX file (currently by Microsoft only en-us is supported)
.PARAMETER WorkingDirectory
Provide a path to a working directory - this will later contain your fixed files.
Default: C:\FixMyADMX\
.PARAMETER LogDirectory
Provide a log directory
Default: $WorkingDirectory\Logs\
.PARAMETER ToConsole
Will output to console _instead_ of a logfile. This might be helpful if you need output piped to something else than a file.
.PARAMETER UseCustomSupportedOn
If set, and if Windows namespace references are actively used, the script will replace Windows:* supportedOn references
with a local dummy supportedOn definition and then remove the windows.admx namespace import.
.PARAMETER SupportedOnName
Optional custom supportedOn definition name. Only valid together with -UseCustomSupportedOn and requires -SupportedOnString.
.PARAMETER SupportedOnString
Optional custom display string text for the supportedOn definition. Only valid together with -UseCustomSupportedOn and requires -SupportedOnName.
.PARAMETER IncrementMajorRevision
If set, increments the major ADMX revision and resets the minor revision to 0. By default, the script increments the minor revision.
.EXAMPLE
PS> .\FixMyADMX.ps1 -ADMXFileLocation 'C:\users\MHimken\Downloads\CitrixADMX\receiver.admx' -ADMLFileLocation 'C:\users\MHimken\Downloads\CitrixADMX\receiver.adml'
Will attempt to apply all fixes within this script. This is is the minimum amount of parameters required 

.NOTES
    Version: 1.3
    Versionname: Fixing what we can
    Intial creation date: 06.08.2023
    Last change date: 30.06.2026
    Latest changes: https://github.com/MHimken/FixMyADMX/blob/master/changelog.md
#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Default')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'CustomSupportedOn')]
    [System.IO.FileInfo]$ADMXFileLocation,
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Default')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'CustomSupportedOn')]
    [System.IO.FileInfo]$ADMLFileLocation,
    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'CustomSupportedOn')]
    [Switch]$UseCustomSupportedOn,
    [Parameter(Mandatory = $true, ParameterSetName = 'CustomSupportedOn')]
    [string]$SupportedOnName,
    [Parameter(Mandatory = $true, ParameterSetName = 'CustomSupportedOn')]
    [string]$SupportedOnString,
    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'CustomSupportedOn')]
    [Switch]$IncrementMajorRevision,
    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'CustomSupportedOn')]
    [System.IO.DirectoryInfo]$WorkingDirectory = 'C:\FixMyADMX\',
    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'CustomSupportedOn')]
    [System.IO.DirectoryInfo]$LogDirectory = "$WorkingDirectory\Logs\",
    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'CustomSupportedOn')]
    [Switch]$ToConsole
)
#Prepare folders and files
$Script:TimeStampStart = Get-Date
$Script:DateTime = Get-Date -Format ddMMyyyy_hhmmss
if (-not(Test-Path $LogDirectory)) { New-Item $LogDirectory -ItemType Directory -Force | Out-Null }
$LogPrefix = 'FMA_'
$LogFile = Join-Path -Path $LogDirectory -ChildPath ('{0}_{1}.log' -f $LogPrefix, $DateTime)

if (-not(Test-Path $WorkingDirectory)) { New-Item -Path $WorkingDirectory -ItemType Directory -Force | Out-Null } 
$CurrentLocation = Get-Location
Set-Location $WorkingDirectory
# Custom parameter set is explicitly selected when SupportedOnName/SupportedOnString are used.
if ($PSCmdlet.ParameterSetName -eq 'CustomSupportedOn') {
    $UseCustomSupportedOn = $true
}
$script:FatalRepairError = $false
$script:RepairSummary = [ordered]@{
    Revision = 'NotRun'
    WindowsNamespace = 'NotRun'
    CustomSupportedOn = 'NotRun'
    ComboBox = 'NotRun'
    ExplainText = 'NotRun'
}
function Write-Log {
    <#
    .DESCRIPTION
        This is a modified version of the script by Ryan Ephgrave.
        .LINK
        https://www.ephingadmin.com/powershell-cmtrace-log-function/
    #>
    Param (
        [Parameter(Mandatory = $false)]
        $Message,
        $Component,
        # Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
        [ValidateSet('1', '2', '3')][int]$Type
    )
    if (-not($NoLog)) {
        $Time = Get-Date -Format 'HH:mm:ss.ffffff'
        $Date = Get-Date -Format 'MM-dd-yyyy'
        if (-not($Component)) { $Component = 'Runner' }
        if (-not($ToConsole)) {
            $LogMessage = "<![LOG[$Message" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
            $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
        } elseif ($ToConsole) {
            switch ($type) {
                1 { Write-Host "T:$Type C:$Component M:$Message" }
                2 { Write-Host "T:$Type C:$Component M:$Message" -BackgroundColor Yellow -ForegroundColor Black }
                3 { Write-Host "T:$Type C:$Component M:$Message" -BackgroundColor Red -ForegroundColor White }
                default { Write-Host "T:$Type C:$Component M:$Message" }
            }
        }
    }
}
function Backup-PolicyFiles {
    Write-Log -Message "Creating a backup of $script:ADMXFileLocation and $script:ADMLFileLocation" -Component 'FMABackup'
    $FilenameADML = $(Split-Path -Path $script:ADMLFileLocation -Leaf)
    $FileNameADMX = $(Split-Path -Path $script:ADMXFileLocation -Leaf)
    $BackupADMLPath = Join-Path -Path $WorkingDirectory -ChildPath "Original_$FilenameADML"
    $BackupADMXPath = Join-Path -Path $WorkingDirectory -ChildPath "Original_$FilenameADMX"
    $script:SaveADMLToWorkingDirectoryPath = Join-Path -Path $WorkingDirectory -ChildPath $FilenameADML
    $script:SaveADMXToWorkingDirectoryPath = Join-Path -Path $WorkingDirectory -ChildPath $FilenameADMX
    Copy-Item -Path $script:ADMXFileLocation -Destination $script:SaveADMXToWorkingDirectoryPath -Force | Out-Null
    Copy-Item -Path $script:ADMXFileLocation -Destination $BackupADMXPath -Force | Out-Null
    Copy-Item -Path $script:ADMLFileLocation -Destination $script:SaveADMLToWorkingDirectoryPath -Force | Out-Null
    Copy-Item -Path $script:ADMLFileLocation -Destination $BackupADMLPath -Force | Out-Null
    Write-Log -Message "Backup of $script:ADMXFileLocation and $script:ADMLFileLocation finished" -Component 'FMABackup'
}
function Add-explainText {
    param(
        [string]$explainTextIdentifier
    )
    Write-Log -Message "Adding $explainTextIdentifier" -Component 'FMAAddexplainText'
    [xml]$ADMLtoEdit = Get-Content -Path $script:SaveADMLToWorkingDirectoryPath
    if ($explainTextIdentifier -in $ADMLtoEdit.DocumentElement.resources.stringTable.string.id) {
        return $false
    }
    $explainTextStringElement = $ADMLtoEdit.CreateElement('string')
    $explainTextStringElement.SetAttribute('id', $explainTextIdentifier)
    $explainTextStringElement.InnerText = "This should explain '$($explainTextIdentifier.Substring(0,$explainTextIdentifier.Length - 8))', but it was missing from the ADMX and ADML. Find this element by using '$explainTextIdentifier' in the ADML and replace it as needed"
    $parentNodestringTable = $ADMLtoEdit.DocumentElement.resources.stringTable
    try {
        $parentNodestringTable.AppendChild($explainTextStringElement)
    } catch {
        Write-Log -Message "$($Error[0].Exception.ErrorRecord)" -Component 'FMAAddexplainText' -Type 3
        Write-Log -Message "Failed to append the childitem $explainTextIdentifier in $script:SaveADMLToWorkingDirectoryPath" -Component 'FMAAddexplainText' -Type 3
        return $false
    }
    $ADMLtoEdit.Save($script:SaveADMLToWorkingDirectoryPath)
    return $true
}
function Add-StringToADML {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StringIdentifier,
        [Parameter(Mandatory = $true)]
        [string]$StringText
    )
    [xml]$ADMLtoEdit = Get-Content -Path $script:SaveADMLToWorkingDirectoryPath
    if ($StringIdentifier -in $ADMLtoEdit.DocumentElement.resources.stringTable.string.id) {
        return $true
    }
    $stringElement = $ADMLtoEdit.CreateElement('string')
    $stringElement.SetAttribute('id', $StringIdentifier)
    $stringElement.InnerText = $StringText
    try {
        $ADMLtoEdit.DocumentElement.resources.stringTable.AppendChild($stringElement) | Out-Null
        $ADMLtoEdit.Save($script:SaveADMLToWorkingDirectoryPath)
    } catch {
        Write-Log -Message "$($Error[0].Exception.ErrorRecord)" -Component 'FMAAddStringToADML' -Type 3
        Write-Log -Message "Failed to add string '$StringIdentifier' to $script:SaveADMLToWorkingDirectoryPath" -Component 'FMAAddStringToADML' -Type 3
        return $false
    }
    return $true
}
function Get-CustomSupportedOnSettings {
    $settings = [ordered]@{
        DefinitionName = 'SUPPORTED_Windows'
        StringId = 'FixMyADMX_SupportedOn_Windows'
        StringText = 'Windows'
    }
    if ($SupportedOnName) {
        $settings.DefinitionName = 'SUPPORTED_' + $SupportedOnName
        $safeStringId = ($SupportedOnName -replace '[^a-zA-Z0-9_]', '_')
        $settings.StringId = 'FixMyADMX_SupportedOn_' + $safeStringId
        $settings.StringText = $SupportedOnString
    }
    return [pscustomobject]$settings
}
function Ensure-CustomSupportedOnDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionName,
        [Parameter(Mandatory = $true)]
        [string]$DisplayStringId,
        [Parameter(Mandatory = $true)]
        [string]$DisplayStringText
    )
    if (-not(Add-StringToADML -StringIdentifier $DisplayStringId -StringText $DisplayStringText)) {
        Write-Log -Message 'Failed to add the custom supportedOn string to ADML.' -Component 'FMAEnsureCustomSupportedOn' -Type 3
        return $false
    }
    [xml]$ADMXToChange = Get-Content -Path $script:SaveADMXToWorkingDirectoryPath
    $policyDefinitionsNode = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']")
    if ($null -eq $policyDefinitionsNode) {
        Write-Log -Message 'Could not locate policyDefinitions node in ADMX.' -Component 'FMAEnsureCustomSupportedOn' -Type 3
        return $false
    }
    $namespaceUri = $policyDefinitionsNode.NamespaceURI
    $supportedOnNode = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']/*[local-name()='supportedOn']")
    if ($null -eq $supportedOnNode) {
        if ([string]::IsNullOrEmpty($namespaceUri)) {
            $supportedOnNode = $ADMXToChange.CreateElement('supportedOn')
        } else {
            $supportedOnNode = $ADMXToChange.CreateElement('supportedOn', $namespaceUri)
        }
        # supportedOn must be at policyDefinitions level before policies (and ideally before categories)
        $insertBeforeNode = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']/*[local-name()='categories']")
        if ($null -eq $insertBeforeNode) {
            $insertBeforeNode = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']/*[local-name()='policies']")
        }
        if ($null -eq $insertBeforeNode) {
            $policyDefinitionsNode.AppendChild($supportedOnNode) | Out-Null
        } else {
            $policyDefinitionsNode.InsertBefore($supportedOnNode, $insertBeforeNode) | Out-Null
        }
    } else {
        # If supportedOn exists in an unexpected position, move it before categories/policies.
        $insertBeforeNode = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']/*[local-name()='categories']")
        if ($null -eq $insertBeforeNode) {
            $insertBeforeNode = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']/*[local-name()='policies']")
        }
        if (($null -ne $insertBeforeNode) -and ($supportedOnNode -ne $insertBeforeNode.PreviousSibling)) {
            $policyDefinitionsNode.RemoveChild($supportedOnNode) | Out-Null
            $policyDefinitionsNode.InsertBefore($supportedOnNode, $insertBeforeNode) | Out-Null
        }
    }
    $definitionsNode = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']/*[local-name()='supportedOn']/*[local-name()='definitions']")
    if ($null -eq $definitionsNode) {
        if ([string]::IsNullOrEmpty($namespaceUri)) {
            $definitionsNode = $ADMXToChange.CreateElement('definitions')
        } else {
            $definitionsNode = $ADMXToChange.CreateElement('definitions', $namespaceUri)
        }
        $supportedOnNode.AppendChild($definitionsNode) | Out-Null
    }
    $customSupportedOnDefinition = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']/*[local-name()='supportedOn']/*[local-name()='definitions']/*[local-name()='definition'][@name='$DefinitionName']")
    if ($null -eq $customSupportedOnDefinition) {
        if ([string]::IsNullOrEmpty($namespaceUri)) {
            $customSupportedOnDefinition = $ADMXToChange.CreateElement('definition')
        } else {
            $customSupportedOnDefinition = $ADMXToChange.CreateElement('definition', $namespaceUri)
        }
        $customSupportedOnDefinition.SetAttribute('name', $DefinitionName)
        $definitionsNode.AppendChild($customSupportedOnDefinition) | Out-Null
    }
    $customSupportedOnDefinition.SetAttribute('displayName', '$(string.' + $DisplayStringId + ')')
    $ADMXToChange.Save($script:SaveADMXToWorkingDirectoryPath)
    return $true
}
function Update-ADMXRevision {
    [xml]$ADMXToChange = Get-Content -Path $script:SaveADMXToWorkingDirectoryPath
    $policyDefinitionsNode = $ADMXToChange.SelectSingleNode("/*[local-name()='policyDefinitions']")
    if ($null -eq $policyDefinitionsNode) {
        Write-Log -Message 'Could not locate policyDefinitions node to update revision.' -Component 'FMAUpdateRevision' -Type 3
        return $false
    }
    $currentRevision = $policyDefinitionsNode.GetAttribute('revision')
    if (-not($currentRevision -match '^(\d+)\.(\d+)$')) {
        Write-Log -Message "Current revision '$currentRevision' is not in major.minor format. Falling back to 1.0 before incrementing." -Component 'FMAUpdateRevision' -Type 2
        $major = 1
        $minor = 0
    } else {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
    }
    if ($IncrementMajorRevision) {
        $major++
        $minor = 0
    } else {
        $minor++
    }
    $newRevision = "$major.$minor"
    $policyDefinitionsNode.SetAttribute('revision', $newRevision)
    $ADMXToChange.Save($script:SaveADMXToWorkingDirectoryPath)
    Write-Log -Message "Updated policyDefinitions revision from '$currentRevision' to '$newRevision'." -Component 'FMAUpdateRevision'
    return $newRevision
}
function Add-textBoxToADML {
    param(
        [System.Xml.XmlElement]$presentationElement
    )
    $presentationID = $presentationElement.id
    Write-Log -Message "Replacing comboBoxes for $presentationID ... loading file $script:SaveADMLToWorkingDirectoryPath" -Component 'FMAAddtextBoxToADML'  
    [xml]$ADMLToChange = Get-Content -Path $script:SaveADMLToWorkingDirectoryPath
    $counter = 0
    foreach ($comboBox in $presentationElement.comboBox) {
        Write-Log -Message "Found comboBox $($comboBox.refID)" -Component 'FMAAddtextBoxToADML'
        $textBoxElement = $ADMLToChange.CreateElement('textBox')
        $textBoxElement.SetAttribute('refId', $comboBox.refID )
        $comboBoxReplacementElementLabel = $ADMLToChange.CreateElement('label')
        $comboBoxReplacementElementLabel.InnerText = $comboBox.label
        $textBoxElement.PrependChild($comboBoxReplacementElementLabel) | Out-Null
        $parentNodepresentationTable = $ADMLToChange.documentElement.resources.presentationTable.presentation | Where-Object { $_.id -eq $presentationID }
        $ElementToReplace = ($parentNodepresentationTable | Where-Object { $_.combobox }).combobox | Where-Object { $_.refid -eq $comboBox.refID }
        Write-Log -Message "Replacing $($elementToReplace.refId) with $($textBoxElement.refId)" -Component 'FMAAddtextBoxToADML'
        try {
            $parentNodepresentationTable.InsertAfter($textBoxElement, $ElementToReplace)
            $parentNodepresentationTable.RemoveChild($ElementToReplace)
        } catch {
            Write-Log -Message "$($Error[0].Exception.ErrorRecord)" -Component 'FMAAddtextBoxToADML' -Type 3
            Write-Log -Message "Failed to replace $($elementToReplace.refId) with $($textBoxElement.refId)" -Component 'FMAAddtextBoxToADML' -Type 3
            return $false
        }
        $counter++
    }
    Write-Log -Message "Found and replaced $counter comboBoxes in $($presentationID) in file $($script:SaveADMLToWorkingDirectoryPath)" -Component 'FMAAddtextBoxToADML'
    $ADMLToChange.Save($script:SaveADMLToWorkingDirectoryPath)
    return $true
}
function Add-explainTextAttributeToADMX {
    param(
        [System.Xml.XmlElement]$policy,
        [string]$explainTextInnerText
    )
    Write-Log -Message "Adding explainText Attribute '$explainTextInnerText'... loading file $script:SaveADMXToWorkingDirectoryPath" -Component 'FMAAddexplainTextAttributeToADMX'
    [xml]$ADMXToChange = Get-Content -Path $script:SaveADMXToWorkingDirectoryPath
    $parentPolicy = $ADMXToChange.policyDefinitions.policies.ChildNodes | Where-Object { $_.name -eq $policy.name }
    try {
        $parentPolicy.SetAttribute("explainText", $explainTextInnerText)
    } catch {
        Write-Log -Message "$($Error[0].Exception.ErrorRecord)" -Component 'FMAAddexplainTextAttributeToADMX' -Type 3
        Write-Log -Message "Failed to set the attribute '$explainTextInnerText'" -Component 'FMAAddexplainTextAttributeToADMX' -Type 3
        return $false             
    }
    $ADMXToChange.Save($script:SaveADMXToWorkingDirectoryPath)
    return $true
}
function Repair-ADMXexplainText {
    Write-Log -Message "Attempting to add missing explainText attribute in $script:SaveADMXToWorkingDirectoryPath" -Component 'FMAADMXRepairexplainText'
    [xml]$ADMXexplainTextXML = Get-Content $script:SaveADMXToWorkingDirectoryPath
    $explainTextMissing = $ADMXexplainTextXML.policyDefinitions.policies.policy | Where-Object { $_.explainText -like "" }
    [byte]$counter = 1
    $counterEdits = 0
    foreach ($policy in $explainTextMissing) {
        #Add explainText with an '_Explain' ending for the stringvariable - this is this closest to most original Microsoft ADMX/ADML files
        $explainTextRef = $policy.name + "_Explain"
        Write-Log -Message "Attempting to add string $explainTextRef to ADML" -Component 'FMAADMXRepairexplainText'
        if (-not(Add-explainText -explainTextIdentifier $explainTextRef)) {
            Write-Log "'$explainTextRef' is already a string adding counter" -Component 'FMAADMXRepairexplainText'
            $explainTextRefWithCounter = $explainTextRef + $counter
            $AddStringToADMLResult = Add-explainText -explainTextIdentifier $explainTextRefWithCounter
            $counter++
            if (-not($AddStringToADMLResult)) {
                return $false
            }
            $explainTextRef = $explainTextRefWithCounter
        }
        $explainText = '$(string.' + $explainTextRef + ")"
        Write-Log -Message "Attempting to add attribute explainText using '$explainText' to ADMX" -Component 'FMAADMXRepairexplainText'
        if (-not(Add-explainTextAttributeToADMX $policy $explainText)) {
            Write-Log -Message "Attempting to add attribute explainText using '$explainText' to ADMX" -Component 'FMAADMXRepairexplainText'
            return $false
        }
        $counterEdits++
    }
    Write-Log -Message "Added $counterEdits explainText attributes in file $($script:SaveADMXToWorkingDirectoryPath)" -Component 'FMAADMXRepairexplainText'
    return $true
}
function Repair-ADMLComboBox {
    Write-Log -Message "Attempting to replace comboBoxes in $script:SaveADMLToWorkingDirectoryPath" -Component 'FMAADMLRepaircomboBox'
    #$ADMLComboBox = Select-Xml -Path $script:SaveADMLToWorkingDirectoryPath -XPath //presentationTable
    #$PresentationUsingcomboBoxes = ($ADMLComboBox.Node.presentation | Where-Object { $_.combobox })
    [xml]$ADMLComboBoxXML = Get-Content $script:SaveADMLToWorkingDirectoryPath
    $PresentationUsingcomboBoxes = ($ADMLComboBoxXML.policyDefinitionResources.resources.presentationTable.presentation | Where-Object { $_.combobox })
    foreach ($presentation in $PresentationUsingcomboBoxes) {
        if (-not(Add-textBoxToADML $presentation)) {
            Write-Log -Message "$($presentation.id) could not be fixed - please consult the log" -Component 'FMAADMLRepaircomboBox' -Type 3
            return $false
        }
    }
    return $true
}
function Repair-ADMXWindowsReferences {
    $result = [ordered]@{
        Success = $true
        WindowsNamespaceFound = $false
        RemovedNamespace = $false
        Skipped = $false
        EnsuredCustomSupportedOnDefinition = $false
        CustomSupportedOnDefinitionName = $null
        CustomSupportedOnApplied = $false
        RewrittenWindowsSupportedOnRefs = 0
    }
    $customSupportedOnSettings = $null
    if ($UseCustomSupportedOn) {
        $customSupportedOnSettings = Get-CustomSupportedOnSettings
        $result.CustomSupportedOnDefinitionName = $customSupportedOnSettings.DefinitionName
        if (Ensure-CustomSupportedOnDefinition -DefinitionName $customSupportedOnSettings.DefinitionName -DisplayStringId $customSupportedOnSettings.StringId -DisplayStringText $customSupportedOnSettings.StringText) {
            $result.EnsuredCustomSupportedOnDefinition = $true
        } else {
            Write-Log -Message 'Failed to ensure custom supportedOn definition. Continuing with remaining fixes.' -Component 'FMAADMXRepairWindowsReferences' -Type 2
            $result.Skipped = $true
            return [pscustomobject]$result
        }
    }
    [xml]$ADMXToChange = Get-Content $script:SaveADMXToWorkingDirectoryPath
    $UsingWindowsADMX = ('Microsoft.Policies.Windows' -in $ADMXToChange.policyDefinitions.policyNamespaces.using.namespace)
    $result.WindowsNamespaceFound = $UsingWindowsADMX
    if ($UsingWindowsADMX) {
        Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath has the windows.admx added to its namespace" -Component 'FMAADMXRepairWindowsReferences'
        [string]$RawADMX = Get-Content $script:SaveADMXToWorkingDirectoryPath | Select-String -Pattern 'Windows:'
        if (($null -ne $RawADMX) -and ($RawADMX -ne "")) {
            if ($UseCustomSupportedOn) {
                Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath is actively using 'Windows:' references. Attempting custom supportedOn replacement." -Component 'FMAADMXRepairWindowsReferences' -Type 2
                $windowsSupportedOnRefNodes = $ADMXToChange.SelectNodes("/*[local-name()='policyDefinitions']/*[local-name()='policies']/*[local-name()='policy']/*[local-name()='supportedOn'][@ref]")
                foreach ($supportedOnRefNode in $windowsSupportedOnRefNodes) {
                    if ($supportedOnRefNode.ref -match '^(?i)windows:') {
                        $supportedOnRefNode.SetAttribute('ref', $customSupportedOnSettings.DefinitionName)
                        $result.RewrittenWindowsSupportedOnRefs++
                    }
                }
                if ($result.RewrittenWindowsSupportedOnRefs -eq 0) {
                    Write-Log -Message "No policy-level 'Windows:' supportedOn references were found for rewrite. Skipping Windows namespace removal and continuing with other fixes." -Component 'FMAADMXRepairWindowsReferences' -Type 2
                    $result.Skipped = $true
                    return [pscustomobject]$result
                }
                $WindowsReferences = @($ADMXToChange.policyDefinitions.policyNamespaces.using | Where-Object { $_.namespace -eq 'Microsoft.Policies.Windows' })
                foreach ($WindowsReference in $WindowsReferences) {
                    $ADMXToChange.policyDefinitions.policyNamespaces.RemoveChild($WindowsReference) | Out-Null
                }
                $ADMXToChange.Save($script:SaveADMXToWorkingDirectoryPath)
                $result.CustomSupportedOnApplied = $true
                $result.RemovedNamespace = $true
                Write-Log -Message "Rewrote $($result.RewrittenWindowsSupportedOnRefs) Windows supportedOn references to '$($customSupportedOnSettings.DefinitionName)' and removed windows.admx namespace." -Component 'FMAADMXRepairWindowsReferences' -Type 2
                return [pscustomobject]$result
            }
            Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath is actively using a 'Windows:' reference. Skipping only the Windows namespace fix and continuing with other repairs." -Component 'FMAADMXRepairWindowsReferences' -Type 2
            $result.Skipped = $true
            return [pscustomobject]$result
        } else {
            Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath is NOT actively using a 'Windows:' reference - removing namespace" -Component 'FMAADMXRepairWindowsReferences'
            $WindowsReferences = @($ADMXToChange.policyDefinitions.policyNamespaces.using | Where-Object { $_.namespace -eq 'Microsoft.Policies.Windows' })
            foreach ($WindowsReference in $WindowsReferences) {
                $ADMXToChange.policyDefinitions.policyNamespaces.RemoveChild($WindowsReference) | Out-Null
            }
            $ADMXToChange.Save($script:SaveADMXToWorkingDirectoryPath)
            $result.RemovedNamespace = $true
        }
    } else {
        Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath is not using windows.admx" -Component 'FMAADMXRepairWindowsReferences'
    }
    return [pscustomobject]$result
}
function Repair-Files {
    Write-Log -Message 'Attempting to repair files' -Component 'FMARepairCore'
    $newRevision = Update-ADMXRevision
    if (-not($newRevision)) {
        Write-Log -Message 'Failed to update the ADMX revision.' -Component 'FMARepairCore' -Type 3
        $script:RepairSummary.Revision = 'Failed'
        $script:FatalRepairError = $true
    } else {
        $script:RepairSummary.Revision = $newRevision
    }
    # The Windows.admx is often referenced, because in Microsofts examples its an imported namespace - it might be completely unnecessary...
    $windowsRepairResult = Repair-ADMXWindowsReferences
    if ($windowsRepairResult.CustomSupportedOnApplied) {
        $script:RepairSummary.WindowsNamespace = 'Applied'
        $script:RepairSummary.CustomSupportedOn = "Applied ($($windowsRepairResult.RewrittenWindowsSupportedOnRefs) refs -> $($windowsRepairResult.CustomSupportedOnDefinitionName))"
    } elseif ($windowsRepairResult.RemovedNamespace) {
        $script:RepairSummary.WindowsNamespace = 'Applied'
        if ($windowsRepairResult.EnsuredCustomSupportedOnDefinition) {
            $script:RepairSummary.CustomSupportedOn = "Ensured ($($windowsRepairResult.CustomSupportedOnDefinitionName))"
        } else {
            $script:RepairSummary.CustomSupportedOn = 'NotUsed'
        }
    } elseif ($windowsRepairResult.EnsuredCustomSupportedOnDefinition) {
        $script:RepairSummary.WindowsNamespace = 'NotNeeded'
        $script:RepairSummary.CustomSupportedOn = "Ensured ($($windowsRepairResult.CustomSupportedOnDefinitionName))"
    } elseif ($windowsRepairResult.Skipped) {
        $script:RepairSummary.WindowsNamespace = 'Skipped'
        $script:RepairSummary.CustomSupportedOn = $(if ($UseCustomSupportedOn) { 'Skipped' } else { 'Disabled' })
        Write-Log -Message 'Windows namespace fix was skipped; continuing with comboBox and explainText repairs.' -Component 'FMARepairCore' -Type 2
    } else {
        $script:RepairSummary.WindowsNamespace = 'NotNeeded'
        $script:RepairSummary.CustomSupportedOn = 'NotUsed'
    }

    $overallSuccess = $true
    # Because comboBox is not supported in the ADML
    if (-not(Repair-ADMLComboBox)) {
        Write-Log -Message 'Failed to replace the ComboBoxes used in the ADML-file - please consult the log' -Component 'FMARepairCore' -Type 3
        $script:RepairSummary.ComboBox = 'Failed'
        $script:FatalRepairError = $true
        $overallSuccess = $false
    } else {
        $script:RepairSummary.ComboBox = 'Applied'
    }
    # If the explainText attribute is missing from the <policy> element it will give an "Object reference not set to an instance of an object." error
    if (-not(Repair-ADMXexplainText)) {
        Write-Log -Message 'Failed to replace the ADMXExplainText used in the ADML-file - please consult the log' -Component 'FMARepairCore' -Type 3
        $script:RepairSummary.ExplainText = 'Failed'
        $script:FatalRepairError = $true
        $overallSuccess = $false
    } else {
        $script:RepairSummary.ExplainText = 'Applied'
    }
    Write-Log -Message "Repair summary: Revision=$($script:RepairSummary.Revision); WindowsNamespace=$($script:RepairSummary.WindowsNamespace); CustomSupportedOn=$($script:RepairSummary.CustomSupportedOn); ComboBox=$($script:RepairSummary.ComboBox); ExplainText=$($script:RepairSummary.ExplainText)" -Component 'FMARepairCore'
    return $overallSuccess
}
function Clear-TempFiles {
    if ($script:FatalRepairError) {
        Write-Log -Message 'Repairs completed with at least one fatal error. Working files are preserved for troubleshooting.' -Component 'CleanUp' -Type 2
    } else {
        Write-Log -Message 'Repairs completed. Working files are preserved.' -Component 'CleanUp'
    }
}
#Start Coding!
Backup-PolicyFiles
Repair-Files
Clear-TempFiles
Set-Location $CurrentLocation
Exit 0