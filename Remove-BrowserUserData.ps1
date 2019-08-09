<#
.SYNOPSIS
  This will remove the browers records of user data
.DESCRIPTION
  This script removes all of the user data recoreded by the browser regarding 
.EXAMPLE
  Remove-BrowserUserData 
  Deletes the User Data
.NOTES
  General notes
#>
[CmdletBinding()]
Param()
Get-Process | Where-Object {$_.ProcessName -in @('chrome','firefox','iexplore')} | Stop-Process -Force
$Counter = 0
do {
  Start-Sleep -Seconds 1
  $Counter++
  $BrowserProcs = Get-Process | Where-Object {$_.ProcessName -in @('chrome','firefox','iexplore')}
} until ($BrowserProcs.Count -eq 0 -or $Counter -eq 20)
if ($BrowserProcs.Count -ne 0) {
  Write-Warning 'The browsers did not terminate, please close them manually'
  break
}

#Wipe Chrome User Data
$ChromePath = $env:LOCALAPPDATA + "\Google\Chrome\User Data\*"
try {Remove-Item -Path $ChromePath -Recurse -Force -ErrorAction stop}
catch {Write-Warning 'Cannot delete the Chrome user data'}

#Wipe Firefox User Data
$FirefoxProfileFolders = (Get-ChildItem $env:APPDATA\Mozilla\Firefox\Profiles\ -Directory).FullName
Try {
  foreach ($ProfDir in $FirefoxProfileFolders) {
    Remove-Item -Recurse -Force -Path $ProfDir\* -ErrorAction stop
  }
}
Catch {Write-Warning 'Cannot delete the Firefox user data'}

#Wipe IE User Data
invoke-command -ScriptBlock {RunDll32.exe InetCpl.cpl, ClearMyTracksByProcess 255}