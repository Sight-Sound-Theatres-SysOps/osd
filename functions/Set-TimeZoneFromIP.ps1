# Fetch the time zone data from the API
$URIRequest = "http://worldtimeapi.org/api/ip"
$Response = (Invoke-WebRequest -Uri $URIRequest -UseBasicParsing).Content | ConvertFrom-Json

# Extract the timezone from the response
$TimeZoneAPI = $Response.timezone

# Define the mapping
$WindowsTimeZones = @{
    "America/Chicago" = "Central Standard Time"
    "America/New_York" = "Eastern Standard Time"
    "America/Denver" = "Mountain Standard Time"
    "America/Phoenix" = "US Mountain Standard Time" 
    "America/Los_Angeles" = "Pacific Standard Time"
    "America/Indiana/Indianapolis" = "Eastern Standard Time"
    "America/Detroit" = "Eastern Standard Time"
    "America/Kentucky/Louisville" = "Eastern Standard Time"
    "America/North_Dakota/Center" = "Central Standard Time"
    "America/Boise" = "Mountain Standard Time"
}

# Check if the timezone exists in the mapping
if ($WindowsTimeZones.ContainsKey($TimeZoneAPI)) {
    $WindowsTimeZone = $WindowsTimeZones[$TimeZoneAPI]
    Set-TimeZone -Id $WindowsTimeZone
    Write-Host "[+] Time zone has been updated to - $WindowsTimeZone" -ForegroundColor Green 
} else {
    Write-Warning "Time zone not found in the mapping. Using the default Windows time zone."
}