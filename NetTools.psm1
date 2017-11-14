function Get-NetStat { 
  [cmdletbinding()]
  Param()
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
  $rawNS = netstat -ano 
  $CleanNS = ($rawNS.trim() | Select-String -Pattern "^(TCP|UDP)") -replace "\s+",',' -replace "(?=(^UDP))(^udp.+),(\d+)",'$2,NO_STATE,$3'
  foreach ($NSline in $CleanNS) {
    if ($NSline -match "^TCP") {
      $objProp = $NSline -match  "$RegexStr"
      write-debug "$matches"
      new-object -TypeName NetstatTCP -Property $matches | Select-Object Protocol,SrcIP,SrcPort,DestIP,DestPort,State,PID
    }
    elseif ($NSline -match "^UDP") {
      $objProp = $NSline -match  "$RegexStr"
      write-debug "$matches"
      new-object -TypeName NetstatUDP -Property $matches | Select-Object Protocol,SrcIP,SrcPort,DestIP,DestPort,State,PID
    }
  }
}
