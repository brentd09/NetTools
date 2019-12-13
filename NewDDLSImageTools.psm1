function Get-DDLSSubnetIPInfo {
  <#
  .SYNOPSIS
    This command finds all of the IP addresses that are possible in the current subnet
  .DESCRIPTION
    This command takes the IP address and subnet masl from the current computer and then works out 
    the subnet length to produce, as an output a custom object with the following properties:
      HostIPAddress      
      HostSubnetMask    
      FirstSubnetIP     
      LastSubnetIP      
      AllValidIPs       
      AllValidStudentIPs
  .EXAMPLE
    Get-DDLSSubnetIPInfo
    There is no parameters to supply to this command as is gathers all that it needs from the 
    Instructor PC
  .NOTES
    General notes
      Created by: Brent Denny
      Created on: 13 Dec 2019
  #>
  [CmdletBinding()]
  Param()
  try {
    $PhysicalAdatpter = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {$_.Status -eq 'up'}
    $MyPcIpaddressObj = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $PhysicalAdatpter.ifIndex -ErrorAction Stop
    if (-not $MyPcIpaddressObj) {throw 'Error finding adapter or IPaddress'}
  }
  Catch {
    try {
      $HyperVAdatpter = Get-NetAdapter | Where-Object {$_.ifIndex -ne $PhysicalAdatpter.ifIndex} -ErrorAction Stop | Where-Object {$_.Status -eq 'up'}
      $MyPcIpaddressObj = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $HyperVAdatpter.ifIndex -ErrorAction Stop
      if (-not $MyPcIpaddressObj) {throw 'Error finding adapter or IPaddress'}
    }
    catch {Write-Warning 'No Adapter could be found for this computer'}
  }
  [string[]]$AllIPinSubnet = @()
  $SubnetJumpValue = [math]::Pow(2,(8 - ($MyPcIpaddressObj.PrefixLength % 8))) #What is the current jump value for each new subnet
  $RevMYIPOctets = ($MyPcIpaddressObj.IPAddress -split '\.')[3..0] # Reversing the octets and then creating an [IPAddress] object allows easy math functions in the IP address
  [ipaddress]$RevIPAddress = $RevMYIPOctets -join '.' 
  [bigint]$RevSubnetMaskValue = 4294967295 - ([math]::Pow(2,32 - $MyPcIpaddressObj.PrefixLength)) +1
  [ipaddress]$DottedRevSubnetMask = 4294967295 # Instantiating new IPAddress object
  $DottedRevSubnetMask.Address = $RevSubnetMaskValue # Assigning real subnetmask value to newly created object
  $RevSubnetMaskOctets = ($DottedRevSubnetMask.IPAddressToString -split '\.')[3..0]
  [ipaddress]$ForwardSubnetMaskAddress = $RevSubnetMaskOctets -join '.'
  [bigint]$AndedResult = $RevSubnetMaskValue -band $RevIPAddress.Address
  $FirstValidRevIP = [ipaddress]::New($AndedResult + 1)
  $LastValidRevIP  = [ipaddress]::New($FirstValidRevIP.address + $SubnetJumpValue - 3)
  [bigint[]]$Range = @()
  [bigint]$StartRange = $AndedResult + 1
  [bigint]$EndRange = $AndedResult + $SubnetJumpValue - 2
  for ($StartRange;$StartRange -le $EndRange; $StartRange = $StartRange + 1) {$Range += $StartRange}
  foreach ($RevNum in $Range){
    $TempRevIP = ([ipaddress]::new($RevNum)).IPAddressToString
    [string[]]$AllIPinSubnet += (($TempRevIP -split '\.')[3..0]) -join '.'
  }
  [ipaddress]$FirstValidIP = ($FirstValidRevIP.IPAddressToString -split '\.')[3..0] -join '.'
  [ipaddress]$LastValidIP  = ($LastValidRevIP.IPAddressToString -split '\.')[3..0] -join '.'
  $Hash = [ordered]@{
    HostIPAddress      = $MyPcIpaddressObj.IPAddress 
    HostSubnetMask     = $ForwardSubnetMaskAddress
    FirstSubnetIP      = $FirstValidIP
    LastSubnetIP       = $LastValidIP
    AllValidIPs        = $AllIPinSubnet
    AllValidStudentIPs = $AllIPinSubnet | Where-Object {$_ -ne $MyPcIpaddressObj.IPAddress}
  }
  return New-Object -TypeName psobject -Property $Hash
}

function New-DDLSStudentPSSessions {
  <#
  .SYNOPSIS
    This command creates PS sessions to DDLS Student PCs
  .DESCRIPTION
    This command takes into account the IP address of the machine you are running the script from and 
    treats it as though it was the Instructor PC, what this means is that it automatically excludes its
    own IP address from the IPs it uses to establish classroom sessions. 
  .EXAMPLE
    New-DDLSStudentPSSessions
    Running this script calls upon another cmdlet that will discover the IPs in the classroom, the output 
    of this called cmdlet shows first and last IP in the subnet, Subnet mask, all valid IPs and all IPs 
    excluding the current IP of the computer where this script is running.
  .NOTES
    General notes
      Created by: Brent Denny
      Created on: 13 Dec 2019
  #>
  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
  Param()
  Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value '*' -Force
  $StudentIPs = (Get-DDLSSubnetIPInfo).AllValidStudentIPs
  Get-PSSession | Remove-PSSession | Out-Null
  Write-Warning "Please wait while sessions are established"
  $SessOpt = New-PSSessionOption -MaxConnectionRetryCount 0 -MaximumRedirection 0 
  if ($PSCmdlet.ShouldProcess("Clasroom Student PCs", "Setting up PowerShell sessions")) {
    New-PSSession -ComputerName $StudentIPs -ErrorAction SilentlyContinue -ThrottleLimit 180 -SessionOption $SessOpt | Where-Object {$_.State -eq 'Opened' -and $_.Availability -eq 'Available' }
  }
}

function Restart-DDLSStudentPC {
  <#
  .SYNOPSIS
    This command will restart all of the computers that this computer can make PS sessions to, in the current subnet.
  .DESCRIPTION
    If you supply the sessions as a parameter this command will check if any are stale and remake those sessions, once 
    all of the sessions are available this will proceed to restart each computer after a given inverval, this interval 
    will assist us in selecting f12 when it boots to lay down a new image for the next class
  .EXAMPLE
    Restart-DDLSStudentPC -StudentSessions $ClassSessions  -SecondsBetweenReboots 25
    This will send restart commands each 25 seconds to each of the sessions given to the parameter StudentSessions
  .EXAMPLE
    Restart-DDLSStudentPC 
    This will first establish PS sessions to the student PCs and then send restart commands each 20 seconds to each 
    of the sessions, 20 Seconds is the default    
  .PARAMETER StudentSessions
    This accepts PSSession objects and normally is all of the sessions to every studentPC
  .PARAMETER SecondsBetweenReboots
    Enter an integer value for the number of seconds to wait before the next reboot
  .NOTES
    General notes
      Created by: Brent Denny
      Created on: 13 Dec 2019
  #>
  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
  Param (
    $StudentSessions = (New-DDLSStudentPSSessions),
    $SecondsBetweenReboots = 20
  )
  if ($PSCmdlet.ShouldProcess("Clasroom Student PCs", "Restarting")) {
    if ($StudentSessions.State -contains 'Broken') {$StudentSessions = (New-DDLSStudentPSSessions)}
    $StudentSessions | ForEach-Object {Invoke-Command -Session $_ -ScriptBlock {Restart-Computer -force}}
    Start-Sleep -Seconds $SecondsBetweenReboots
  }
}

function Copy-DDLSFileToStudentPC {
  <#
  .SYNOPSIS
    This command can copy a file to the student PCs in the room
  .DESCRIPTION
    This command uses a powershell session to each student computer and then the 
    Copy-Item -ToSession command to copy the file to the computer without the need 
    for RPC access
  .EXAMPLE
    Copy-DDLSFileToStudentPC -StudentSessions $ClassSessions -FilePath d:\file.pdf -DestinationPath c:\
    This will copy a file from the local PCs D:\ drive, called file.pdf, to each student computer's C:\ 
    drive. 
  .PARAMETER StudentSessions
    This accepts PSSession objects and normally is all of the sessions to every studentPC
  .PARAMETER FilePath
    Points to the file that will be copied to the Student PCs 
  .PARAMETER Destination
    Points to the directory on the student PC where the file wil be copied to
  .NOTES
    General notes
      Created by: Brent Denny
      Created on: 13 Dec 2019
  #>
  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
  Param (
    $StudentSessions = (New-DDLSStudentPSSessions),
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    $DestinationPath = 'C:\users\Administrator\Desktop\'
  )
  if ($StudentSessions.State -contains 'Broken') {$StudentSessions = (New-DDLSStudentPSSessions)}
  $Counter = 0
  ForEach ($StudentSession in $StudentSessions) {
    $Counter++
    if ($PSCmdlet.ShouldProcess("IP address $($StudentSession.Comptername)", "Copy file")) {
      Copy-Item -ToSession $StudentSession -Path $FilePath -Destination $DestinationPath -Force
    }
    Write-Host "Copied to $Counter computer/s"
  }
}

function Set-DDLSPowerOptions {
  <#
  .SYNOPSIS
    This command disables the sleep settings in the power options of the student PCs
  .DESCRIPTION
    This command disables the sleep settings in the power options of the student PCs 
    by using powercfg.exe settings
  .EXAMPLE
    Set-DDLSPowerOptions -StudentSessions $ClassSessions
    This runs the PowerCFG commands on every student PC that it has a PS session to
  .PARAMETER StudentSessions
    This accepts PSSession objects and normally is all of the sessions to every studentPC
  .NOTES
    General notes
      Created by: Brent Denny
      Created on: 13 Dec 2019    
  #>
  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
  Param (
    $StudentSessions = (New-DDLSStudentPSSessions)
  )
  if ($PSCmdlet.ShouldProcess("Clasroom Student PCs", "Disabling Sleep settings")) {
    if ($StudentSessions.State -contains 'Broken') {$StudentSessions = (New-DDLSStudentPSSessions)}
    Invoke-Command -Session $StudentSessions -ScriptBlock {
      & powercfg.exe /x -hibernate-timeout-ac 0
      & powercfg.exe /x -disk-timeout-ac 0
      & powercfg.exe /x -monitor-timeout-ac 0
      & Powercfg.exe /x -standby-timeout-ac 0
    }  
  }
}

function Disable-DDLSLanguageHotKey {
  <#
  .SYNOPSIS
    This command disables the language switching hotkey on the student PCs
  .DESCRIPTION
    This command disables the language switching hotkey on the student PCs 
    by using Registry hacks
  .EXAMPLE
    Disable-DDLSLanguageHotKey -StudentSessions $ClassSessions
    This edits the registry on every student PC that it has a PS session to
  .PARAMETER StudentSessions
    This accepts PSSession objects and normally is all of the sessions to every studentPC
  .NOTES
    General notes
      Created by: Brent Denny
      Created on: 13 Dec 2019    
  #>
  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
  Param (
    $StudentSessions = (New-DDLSStudentPSSessions)
  )
  if ($PSCmdlet.ShouldProcess("Clasroom Student PCs", "Disabling KB layout hotkey")) {
    if ($StudentSessions.State -contains 'Broken') {$StudentSessions = (New-DDLSStudentPSSessions)}
    Invoke-Command -Session $StudentSessions -ScriptBlock {
      Set-ItemProperty -Path 'HKCU:\Keyboard Layout\Toggle' -Name 'Language Hotkey' -Value 3
      Set-ItemProperty -Path 'HKCU:\Keyboard Layout\Toggle' -Name 'Hotkey' -Value 3
      Set-ItemProperty -Path 'HKCU:\Keyboard Layout\Toggle' -Name 'Layout Hotkey' -Value 3
    }
  }  
}

function Enable-DDLSAutoLogon {
  <#
  .SYNOPSIS
    This command is meant to enable AutoAdminLogon on the student PCs, It does not work
    yet
  .DESCRIPTION
    This command is meant to enable AutoAdminLogon on the student PCs, It does not work
    yet
  .EXAMPLE
    Enable-DDLSAutoLogon -StudentSessions $ClassSessions
    This edits the registry on every student PC that it has a PS session to
  .PARAMETER StudentSessions
    This accepts PSSession objects and normally is all of the sessions to every studentPC
  .NOTES
    General notes
      Created by: Brent Denny
      Created on: 13 Dec 2019    
  #>  
  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
  Param (
    $StudentSessions = (New-DDLSStudentPSSessions)
  )  
  if ($PSCmdlet.ShouldProcess("Clasroom Student PCs", "Setting up Autologon")) {
    if ($StudentSessions.State -contains 'Broken') {$StudentSessions = (New-DDLSStudentPSSessions)}
    Invoke-Command -Session $StudentSessions -ScriptBlock {
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultDomainName' -Value 'Administrator'
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultPassword' -Value 'password'
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'DefaultUserName' -Value 'Administrator'
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 1
    }
  }
}