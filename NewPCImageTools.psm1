function Get-CurrentSubnetIPInfo {
  [CmdletBinding()]
  Param()
  try {
    $PhysicalAdatpter = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {$_.Status -eq 'up'}
    $Script:IPInfo = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $PhysicalAdatpter.ifIndex -ErrorAction Stop
  }
  Catch {
    try {
      $HyperVAdatpter = Get-NetAdapter | Where-Object {$_.ifIndex -ne $PhysicalAdatpter.ifIndex} -ErrorAction Stop | Where-Object {$_.Status -eq 'up'}
      $Script:IPInfo = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $HyperVAdatpter.ifIndex -ErrorAction Stop
    }
    catch {Write-Warning 'No Adapter could be found for this computer'}
  }
  [string[]]$AllIPinSubnet = @()
  $SubnetJump = [math]::Pow(2,(8 - ($IPInfo.PrefixLength % 8)))
  $RevOctets = ($IPInfo.IPAddress -split '\.')[3..0]
  [ipaddress]$RevIPAddress = $RevOctets -join '.' 
  [bigint]$RevSmnInt = 4294967295 - ([math]::Pow(2,32 - $IPInfo.PrefixLength)) +1
  [ipaddress]$DottedRevSubnetMask = 4294967295
  $DottedRevSubnetMask.Address = $RevSmnInt
  $RevSNMOctets = ($DottedRevSubnetMask.IPAddressToString -split '\.')[3..0]
  [ipaddress]$FwdSnmAddress = $RevSNMOctets -join '.'
  [bigint]$AndedResult = $RevSmnInt -band $RevIPAddress.Address
  $FirstValidRevIP = [ipaddress]::New($AndedResult + 1)
  $LastValidRevIP  = [ipaddress]::New($FirstValidRevIP.address + $SubnetJump - 3)
  [bigint[]]$Range = @()
  [bigint]$StartRange = $AndedResult + 1
  [bigint]$EndRange = $AndedResult + $SubnetJump - 2
  for ($StartRange;$StartRange -le $EndRange; $StartRange = $StartRange + 1) {$Range += $StartRange}
  foreach ($RevNum in $Range){
    $TempRevIP = ([ipaddress]::new($RevNum)).IPAddressToString
    [string[]]$AllIPinSubnet += (($TempRevIP -split '\.')[3..0]) -join '.'
  }
  [ipaddress]$FirstValidIP = ($FirstValidRevIP.IPAddressToString -split '\.')[3..0] -join '.'
  [ipaddress]$LastValidIP  = ($LastValidRevIP.IPAddressToString -split '\.')[3..0] -join '.'
  $Hash = [ordered]@{
    HostIPAddress = $IPInfo.IPAddress 
    HostSubnetMask =  $FwdSnmAddress
    FirstSubnetIP = $FirstValidIP
    LastSubnetIP = $LastValidIP
    AllValidIPs = $AllIPinSubnet
  }
  return New-Object -TypeName psobject -Property $Hash
}

function Grant-TrustedHostsToAll {
  Set-Item -Path WSMan:\localhost\client\TrustedHosts -Value '*'
}

function Open-ClassPSSession {
  $SubnetInfo = Get-CurrentSubnetIPInfo
  $Sessions = New-PSSession -ComputerName $SubnetInfo.AllValidIPs -ErrorAction SilentlyContinue
  return $Sessions
}