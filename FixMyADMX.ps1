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

.EXAMPLE
PS> .\FixMyADMX.ps1 -ADMXFileLocation 'C:\users\MHimken\Downloads\CitrixADMX\receiver.admx' -ADMLFileLocation 'C:\users\MHimken\Downloads\CitrixADMX\receiver.adml'
Will attempt to apply all fixes within this script. This is is the minimum amount of parameters required 

.NOTES
    Version: 1.0
    Versionname: Aversion for Citrix
    Intial creation date: 06.08.2023
    Last change date: 06.08.2023
    Latest changes: https://github.com/MHimken/FixMyADMX/blob/master/changelog.md
#>
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [System.IO.FileInfo]$ADMXFileLocation,
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [System.IO.FileInfo]$ADMLFileLocation,
    [System.IO.DirectoryInfo]$WorkingDirectory = 'C:\FixMyADMX\',
    [System.IO.DirectoryInfo]$LogDirectory = "$WorkingDirectory\Logs\"
)
#Prepare folders and files
$Script:TimeStampStart = Get-Date
$Script:DateTime = Get-Date -Format ddMMyyyy_hhmmss
if (-not(Test-Path $LogDirectory)) { New-Item $LogDirectory -ItemType Directory -Force | Out-Null }
$LogPrefix = 'FMA_'
$LogFile = Join-Path -Path $LogDirectory -ChildPath ('{0}_{1}.log' -f $LogPrefix, $DateTime)

$Script:PathToScript = if ( $PSScriptRoot ) { 
    # Console or VS Code debug/run button/F5 temp console
    $PSScriptRoot 
} else {
    if ( $psISE ) { Split-Path -Path $psISE.CurrentFile.FullPath }
    else {
        if ($profile -match 'VScode') { 
            # VS Code "Run Code Selection" button/F8 in integrated console
            Split-Path $psEditor.GetEditorContext().CurrentFile.Path 
        } else { 
            Write-Output 'unknown directory to set path variable. exiting script.'
            exit
        } 
    } 
}
if (-not(Test-Path $WorkingDirectory)) { New-Item -Path $WorkingDirectory -ItemType Directory -Force | Out-Null } 
$CurrentLocation = Get-Location
Set-Location $WorkingDirectory
function Write-Log {
    <#
    .DESCRIPTION
        This is a modified version of Ryan Ephgrave's script
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
    $Time = Get-Date -Format 'HH:mm:ss.ffffff'
    $Date = Get-Date -Format 'MM-dd-yyyy'
    if (-not($Component)) { $Component = 'Runner' }
    if (-not($Type)) { $Type = 1 }
    $LogMessage = "<![LOG[$Message" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    if ($Verbose) {
        switch ($Type) {
            1 { Write-Host $Message }
            2 { Write-Warning $Message }
            3 { Write-Error $Message }
            default { Write-Host $Message }
        }        
    }
}
function Backup-PolicyFiles {
    Write-Log -Message "Creating a backup of $script:ADMXFileLocation and $script:ADMLFileLocation" -Component 'FMABackup'
    $FilenameADML = $(Split-Path -Path $script:ADMLFileLocation -Leaf)
    $FileNameADMX = $(Split-Path -Path $script:ADMXFileLocation -Leaf)
    $BackupADMLPath = $WorkingDirectory.ToString() + "Original_$FilenameADML"
    $BackupADMXPath = $WorkingDirectory.ToString() + "Original_$FileNameADMX"
    $script:SaveADMLToWorkingDirectoryPath = $WorkingDirectory.ToString() + $FilenameADML
    $script:SaveADMXToWorkingDirectoryPath = $WorkingDirectory.ToString() + $FilenameADMX
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
    Write-Log -Message "Adding $explainTextIdentifier" -Component 'FMAAddstringToADML'
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
        Write-Log -Message "$($Error[0].Exception.ErrorRecord)" -Component 'FMAAddstringToADML' -Type 3
        Write-Log -Message "Failed to append the childitem $explainTextIdentifier in $script:SaveADMLToWorkingDirectoryPath" -Component 'FMAAddstringToADML' -Type 3
        return $false
    }
    $ADMLtoEdit.Save($script:SaveADMLToWorkingDirectoryPath)
    return $true
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
        $parentPolicy.SetAttribute("explainText", $explainText)
    } catch {
        Write-Log -Message "$($Error[0].Exception.ErrorRecord)" -Component 'FMAAddexplainTextAttributeToADMX' -Type 3
        Write-Log -Message "Failed to set the attribute '$explainText' to " -Component 'FMAAddexplainTextAttributeToADMX' -Type 3
        return $false             
    }
    $ADMXToChange.Save($script:SaveADMXToWorkingDirectoryPath)
    return $true
}
function Repair-ADMXexplainText {
    Write-Log -Message "Attempting to add missing explainText attribute in $script:SaveADMXToWorkingDirectoryPath" -Component 'FMAADMXRepairexplainText'
    $ADMXexplainText = Select-Xml -Path $script:SaveADMXToWorkingDirectoryPath -XPath //policies
    $explainTextMissing = $ADMXexplainText.Node.policy | Where-Object { $_.explainText -like "" }
    [byte]$counter = 1
    $counterEdits = 0
    foreach ($policy in $explainTextMissing) {
        #Add explainText with an '_Explain' ending for the stringvariable - this is this closest to most original Microsoft ADMX/ADML files
        $explainTextRef = $policy.name + "_Explain"
        Write-Log -Message "Attempting to add string $explainTextRef to ADML" -Component 'FMAADMXRepairexplainText'
        if (-not(Add-explainText -explainTextIdentifier $explainTextRef)) {
            Write-Log "'$explainTextRef' is already a string adding counter" -Component 'FMAADMXRepairexplainText'
            $AddStringToADMLResult = Add-explainText -explainTextID $explainTextRef+$counter
            $counter++
            if (-not($AddStringToADMLResult)) {
                return $false
            }
        }
        $explainText = '$(string.' + $explainTextRef + ")"
        Write-Log -Message "Attempting to add attribute explainText using '$explainText' to ADMX" -Component 'FMAADMXRepairexplainText'
        if (-not(Add-explainTextAttributeToADMX $policy $explainText)) {
            Write-Log -Message "Attempting to add attribute explainText using '$explainText' to ADMX" -Component 'FMAADMXRepairexplainText'
            return $false
        }
        $counterEdits++
    }
    Write-Log -Message "Added $counter explainText attributes in file $($script:SaveADMXToWorkingDirectoryPath)" -Component 'FMAADMXRepairexplainText'
    return $true
}
function Repair-ADMLComboBox {
    Write-Log -Message "Attempting to replace comboBoxes in $script:SaveADMLToWorkingDirectoryPath" -Component 'FMAADMLRepaircomboBox'
    $ADMLComboBox = Select-Xml -Path $script:SaveADMLToWorkingDirectoryPath -XPath //presentationTable
    $PresentationUsingcomboBoxes = ($ADMLComboBox.Node.presentation | Where-Object { $_.combobox })
    foreach ($presentation in $PresentationUsingcomboBoxes) {
        if (-not(Add-textBoxToADML $presentation)) {
            Write-Log -Message "$($presentation.id) could not be fixed - please consult the log" -Component 'FMAADMLRepaircomboBox' -Type 3
            return $false
        }
    }
    return $true
}

function Repair-ADMXWindowsReferences {
    [xml]$ADMXToChange = Get-Content $script:SaveADMXToWorkingDirectoryPath
    $UsingWindowsADMX = ('Microsoft.Policies.Windows' -in $ADMXToChange.policyDefinitions.policyNamespaces.using.namespace)
    if ($UsingWindowsADMX) {
        Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath has the windows.admx added to its namespace" -Component 'FMAADMXRepairWindowsReferences'
        [string]$RawADMX = Get-Content $script:SaveADMXToWorkingDirectoryPath | Select-String -Pattern 'Windows:'
        if ($RawADMX) {
            Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath is actively using a 'Windows:' reference, which needs to be replaced. Consult the blog to find out more about this issue" -Component 'FMAADMXRepairWindowsReferences' -Type 2
            return $false
        } else {
            Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath is not actively using a 'Windows:' reference - removing namespace" -Component 'FMAADMXRepairWindowsReferences'
            $WindowsReference = $ADMXToChange.policyDefinitions.policyNamespaces.using | Where-Object { $_.namespace -eq 'Microsoft.Policies.Windows' }
            $ADMXToChange.policyDefinitions.policyNamespaces.RemoveChild($WindowsReference)
            $ADMXToChange.Save($script:SaveADMXToWorkingDirectoryPath)
        }
    } else {
        Write-Log -Message "$script:SaveADMXToWorkingDirectoryPath is not using windows.admx" -Component 'FMAADMXRepairWindowsReferences'
    }
    return $true
}
function Repair-Files {
    Write-Log -Message 'Attempting to repair files' -Component 'FMARepairCore'
    # Because comboBox is not supported in the ADML
    if (-not(Repair-ADMLComboBox)) {
        Write-Log -Message 'Failed to replace the ComboBoxes used in the ADML-file - please consult the log' -Component 'FMARepairCore' -Type 3
        return $false
    }
    # If the explainText attribute is missing from the <policy> element it will give an "Object reference not set to an instance of an object." error
    if (-not(Repair-ADMXexplainText)) {
        Write-Log -Message 'Failed to replace the ComboBoxes used in the ADML-file - please consult the log' -Component 'FMARepairCore' -Type 3
        return $false
    }
    # The Windows.admx is often referenced, because in Microsofts examples its an imported namespace - it might be completely unnecessary...
    if (-not(Repair-ADMXWindowsReferences)) {
        Write-Log -Message 'Failed to replace the ComboBoxes used in the ADML-file - please consult the log' -Component 'FMARepairCore' -Type 3
        return $false
    }
}
function Clear-TempFiles {
    #NothingToDoYet
}
#Start Coding!
Backup-PolicyFiles
Repair-Files
Clear-TempFiles
Set-Location $CurrentLocation
Exit 0