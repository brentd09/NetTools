function Show-SubnetInformation {
  [cmdletbinding()]
  Param (
    [Parameter(Mandatory=$true)]
    [int]$SubnetLength,
    [Parameter(Mandatory=$true)]
    [string]$IPAddress
  )
 
  [int[]]$OctetArrayFromIPAddress = $IPAddress -split '\.'
  
  $OctetSubnetBitIndex = $SubnetLength % 8
  $NumberOfSubnetsInOctet = [math]::Pow(2,$OctetSubnetBitIndex)
  $SubnetJumpValue =  256 / $NumberOfSubnetsInOctet

  $SubnetOctetIndex = [math]::Truncate($SubnetLength / 8)

  $StartOctetForSubnet = [math]::Truncate($OctetArrayFromIPAddress[$SubnetOctetIndex] / $SubnetJumpValue) * $SubnetJumpValue

  $SubnetAddressOctetArray = $OctetArrayFromIPAddress.psobject.copy()
  $BroadCastAddressArray = $OctetArrayFromIPAddress.psobject.copy()

  $NumberOfZerosNeededInSubnetID = 3 - $SubnetOctetIndex
  $SubnetAddressOctetArray[$SubnetOctetIndex]=$StartOctetForSubnet
  $BroadCastAddressArray[$SubnetOctetIndex]=$StartOctetForSubnet + $SubnetJumpValue - 1

  if ($NumberOfZerosNeededInSubnetID -gt 0) {
    1..$NumberOfZerosNeededInSubnetID | ForEach-Object {
      $SubnetAddressOctetArray[$SubnetOctetIndex+$_]=0
      $BroadCastAddressArray[$SubnetOctetIndex+$_]=255
    }
  }

  [int[]]$ReverseSubnetAddressOctetArray = $SubnetAddressOctetArray[3..0]
  $ReverseSubnetAddress = [ipaddress]::Parse($ReverseSubnetAddressOctetArray -join '.')
  $HostAddressesPerSubnet = [math]::Pow(2,(32-$SubnetLength))
  $TraditionalSubnetMaskDecimal = [convert]::ToInt64(('1'*$SubnetLength+'0'*(32-$SubnetLength)),2)
  $TraditionalSubnetMask = ((([ipaddress]::new($TraditionalSubnetMaskDecimal)).IPAddressToString -split '\.')[3..0] ) -join '.'

  [ipaddress[]]$AllValidHostAddressesInSubnet = (0+1)..($HostAddressesPerSubnet-2) | ForEach-Object {
    $SubnetIDToInteger = $ReverseSubnetAddress.Address + $_
    $TempReverseSubnet = New-Object -TypeName ipaddress -ArgumentList $SubnetIDToInteger
    ((($TempReverseSubnet.IPAddressToString) -split "\.")[3..0]) -join '.'
  }

  $ObjProps = [ordered]@{
    IPAddress        = $IPAddress
    CIDRSubnetMask   = $SubnetLength
    SubnetMask       = $TraditionalSubnetMask
    IPSubnet         = $SubnetAddressOctetArray -join '.'
    Broadcast        = $BroadCastAddressArray -join '.'
    AllHostAddresses = $AllValidHostAddressesInSubnet
    NumberOfHosts    = $AllValidHostAddressesInSubnet.Count
  }
  New-Object -TypeName psobject -Property $ObjProps
}


Show-SubnetInformation -SubnetLength 28 -IPAddress 50.45.52.222