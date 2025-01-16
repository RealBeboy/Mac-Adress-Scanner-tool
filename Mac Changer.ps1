# Function to generate random MAC
function Get-RandomMAC {
    # First byte (locally administered)
    $firstByte = '02'  # Using 02 to ensure it's a locally administered address
    
    # Generate 5 more bytes
    $bytes = 2..6 | ForEach-Object {
        (Get-Random -Minimum 0 -Maximum 255).ToString('X2')
    }
    
    # Combine all bytes
    return "$firstByte$($bytes -join '')"
}

# Get all network adapters and create selection menu
$adapters = Get-NetAdapter
Write-Host "`nAvailable Network Adapters:"
for ($i = 0; $i -lt $adapters.Count; $i++) {
    Write-Host "$($i+1). $($adapters[$i].Name) - $($adapters[$i].MacAddress)"
}

# Get user selection
do {
    $selection = Read-Host "`nSelect adapter number (1-$($adapters.Count))"
    $selection = $selection -as [int]
} while ($selection -lt 1 -or $selection -gt $adapters.Count)

$selectedAdapter = $adapters[$selection-1]

# Show current MAC
Write-Host "`nCurrent MAC Address: $($selectedAdapter.MacAddress)"

# Ask if user wants random MAC or manual input
do {
    $choice = Read-Host "`nDo you want to (1) Generate random MAC or (2) Enter manual MAC? (1/2)"
} while ($choice -ne "1" -and $choice -ne "2")

if ($choice -eq "1") {
    $newMac = Get-RandomMAC
    Write-Host "Generated MAC: $newMac"
    
    $confirm = Read-Host "Use this MAC? (Y/N)"
    while ($confirm -ne "Y" -and $confirm -ne "y") {
        $newMac = Get-RandomMAC
        Write-Host "Generated MAC: $newMac"
        $confirm = Read-Host "Use this MAC? (Y/N)"
    }
}
else {
    do {
        $newMac = Read-Host "`nEnter new MAC address (12 hex digits, no colons)"
    } while ($newMac -notmatch '^[0-9A-Fa-f]{12}$')
}

# Backup current MAC
$oldMac = $selectedAdapter.MacAddress

try {
    Write-Host "`nChanging MAC address..."
    
    # Disable adapter
    Disable-NetAdapter -Name $selectedAdapter.Name -Confirm:$false
    
    # Set new MAC
    Set-NetAdapter -Name $selectedAdapter.Name -MacAddress $newMac
    
    # Enable adapter
    Enable-NetAdapter -Name $selectedAdapter.Name -Confirm:$false
    
    Write-Host "MAC address successfully changed!"
    Write-Host "Old MAC: $oldMac"
    Write-Host "New MAC: $newMac"
}
catch {
    Write-Host "`nError changing MAC address: $($_.Exception.Message)"
    Write-Host "Attempting to re-enable network adapter..."
    Enable-NetAdapter -Name $selectedAdapter.Name -Confirm:$false
}

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')