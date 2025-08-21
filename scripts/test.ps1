$hostname = @{
  "scriptInfo" = hostname 
}
$hostname | ConvertTo-Json -Compress