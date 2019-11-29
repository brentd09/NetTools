function Get-CurrentSubnetIPInfo {
  [CmdletBinding()]
  Param()
  try {
    $NetAdatpter = Get-NetAdapter -Physical -ErrorAction Stop
    $IPInfo = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $NetAdatpter.ifIndex -ErrorAction Stop
  }
  Catch {Write-Warning 'Could not identify a network card or IP address'; break}
  $SubnetJump = [math]::Pow(2,(8 - ($IPInfo.PrefixLength % 8)))
  $RevOctets = ($IPInfo.IPAddress -split '\.')[3..0]
  [ipaddress]$RevIPAddress = $RevOctets -join '.' 
  [ipaddress]$DottedRevSubnetMask = 4294967295 - ([math]::Pow(2,32 - $IPInfo.PrefixLength))
  $RevSNMOctets = ($DottedRevSubnetMask.IPAddressToString -split '\.')[3..0]
  [ipaddress]$FwdSnmAddress = $RevSNMOctets -join '.'
  $AndedResult = $RevSnmAddress.Address -band $RevIPAddress.Address
  $FirstValidRevIP = [ipaddress]::New($AndedResult + 1)
  $LastValidRevIP  = [ipaddress]::New($FirstValidRevIP.address + $SubnetJump - 3)
  foreach ($RevNum in (($AndedResult+1)..($AndedResult+$SubnetJump - 2))){
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