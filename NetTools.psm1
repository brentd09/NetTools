function Get-NetStat { 
<#
.SYNOPSIS
   'netstat -ano' in PowerShell Style
.DESCRIPTION
   This script get the raw output from a netstat -ano command and reformats the 
   data into two powershell custom objects (NetstatTCP and NetstatUDP objects)
   (A better option to this script would be the Get-NetTCPConnection cmdlet)
.EXAMPLE
   Get-Netstat
   This gets all output from the netstat -ano and converts the data into PowerShell objects
.EXAMPLE
   Get-Netstat -Protocol TCP -AddressFamily IPv4
   This gets IPv4 information for the TCP protocol only
.PARAMETER Protocol
   This parameter can take either TCP or UDP as parameter values
.PARAMETER AddressFamily
   This parameter can take either IPv4 or IPv6 as parameter values
.NOTES
   Created 
   By:       Brent Denny
   when:     13 Nov 2017
   Modified: 14 Nov 2017 
#>
  [cmdletbinding()]
  Param(
    [validateset('TCP','UDP')]
    [string]$Protocol = 'BOTH',
    [validateset('IPv4','IPv6')]
    [string]$AddressFamily = 'BOTH'
  )
  class NetstatTCP {
    [string]$Protocol
    [string]$SrcIP
    [int]$SrcPort
    [string]$DestIP
    [int]$DestPort
    [string]$State
    [int]$PID
    [string]$0
  }
  class NetstatUDP {
    [string]$Protocol
    [string]$SrcIP
    [int]$SrcPort
    [string]$DestIP
    [string]$DestPort
    [string]$State
    [int]$PID
    [string]$0
  }
  $RegexStr = "^(?<Protocol>TCP|UDP),(?<SrcIP>(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\[.*\])):(?<SrcPort>\d+),(?<DestIP>(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\[.*\]|\*)):(?<DestPort>\d+|\*),(?<State>[a-zA-Z_]+),(?<PID>\d+)$"
  $RawNS = netstat -ano 
  $CleanNS = ($RawNS.trim() | Select-String -Pattern "^(TCP|UDP)") -replace "\s+",',' -replace "(?=(^UDP))(^udp.+),(\d+)",'$2,NO_STATE,$3'
  foreach ($NSline in $CleanNS) {
    if ($NSline -match "^TCP" -and $Protocol -match 'TCP|both') {
      $objProp = $NSline -match  "$RegexStr"
      write-debug "$matches"
      $OutputObj = new-object -TypeName NetstatTCP -Property $matches | Select-Object Protocol,SrcIP,SrcPort,DestIP,DestPort,State,PID
    }
    if ($NSline -match "^UDP" -and $Protocol -match 'UDP|both') {
      $objProp = $NSline -match  "$RegexStr"
      write-debug "$matches"
      $OutputObj = new-object -TypeName NetstatUDP -Property $matches | Select-Object Protocol,SrcIP,SrcPort,DestIP,DestPort,State,PID
    }
    if ($AddressFamily -match 'ipv4|both' -and $OutputObj.srcip -match '^\d') {$OutputObj}
    if ($AddressFamily -match 'ipv6|both' -and $OutputObj.srcip -match '^\[') {$OutputObj}
  }
}
