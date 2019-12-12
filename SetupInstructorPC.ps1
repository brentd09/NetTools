[CmdletBinding()]
Param(
  [string]$InstructorFolderPath = 'c:\InstructorShare',
  [string]$ShareName = 'InstructorShare',
  [string]$RemoteMappedDrive = 'I:'
)
function Get-CurrentSubnetIPInfo {
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
  $SubnetJumpValue = [math]::Pow(2,(8 - ($MyPcIpaddressObj.PrefixLength % 8)))
  $RevMYIPOctets = ($MyPcIpaddressObj.IPAddress -split '\.')[3..0]
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
    HostIPAddress  = $MyPcIpaddressObj.IPAddress 
    HostSubnetMask = $ForwardSubnetMaskAddress
    FirstSubnetIP  = $FirstValidIP
    LastSubnetIP   = $LastValidIP
    AllValidIPs    = $AllIPinSubnet
  }
  return New-Object -TypeName psobject -Property $Hash
}

Clear-Host
try {
  new-item -Path (Split-Path $InstructorFolderPath) -Name ($InstructorFolderPath  -split '\\')[-1] -ItemType Directory -Force -ErrorAction Stop *> $null
  New-SmbShare -Path $InstructorFolderPath -Name $ShareName -FullAccess Everyone -ErrorAction Stop  *> $null
}
catch {}
$Shares = Get-SmbShare
if ($Shares.name -notcontains $ShareName) {$Sharesuccess = $false}
else {$Sharesuccess = $true}
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value '*' -Force
Get-PSSession | Remove-PSSession
Write-Host "`n Please wait about 20-30 seconds while the PCs are discovered"
$ClassIPRange = (Get-CurrentSubnetIPInfo).AllValidIPs
$MyIPObj = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex (Get-NetAdapter -Physical).ifIndex
$MyIPAddress = $MyIPObj.IPAddress
$OtherClassIPs = $ClassIPRange | Where-Object {$_ -ne $MyIPAddress}
$sessOpt = New-PSSessionOption -MaxConnectionRetryCount 0 -MaximumRedirection 0 
$ClassSessions = New-PSSession -ComputerName $OtherClassIPs -ErrorAction SilentlyContinue -ThrottleLimit 180 -SessionOption $sessOpt 
if ($Sharesuccess -eq $true) {Invoke-Command -Session $ClassSessions -ScriptBlock {
  net use $using:RemoteMappedDrive /del *>$null
  net use $using:RemoteMappedDrive \\$using:MyIPAddress\$using:ShareName /persistent:yes /user:administrator password} *>$null
  Write-Host "Students should now be able to access files in your $InstructorFolderPath directory by using the $RemoteMappedDrive on their computer" 
}

