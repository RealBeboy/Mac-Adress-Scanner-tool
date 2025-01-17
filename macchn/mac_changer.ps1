# Function to scan network using arp -a
function Get-NetworkScan {
    $arpResult = arp -a
    $networkDevices = @()
    
    # Parse arp -a output
    $arpResult | ForEach-Object {
        if ($_ -match '(?<IP>\d+\.\d+\.\d+\.\d+)\s+(?<MAC>[\da-f-]+)\s+(?<Type>\w+)') {
            $networkDevices += [PSCustomObject]@{
                IP = $matches.IP
                MAC = $matches.MAC.Replace("-", "")  # Remove hyphens for consistent format
                Type = $matches.Type
            }
        }
    }
    return $networkDevices
}

# Get all network adapters
$adapters = Get-NetAdapter

# Scan network first
Write-Host "`nScanning network devices..."
$networkDevices = Get-NetworkScan
Write-Host "`nDiscovered Network Devices:"
for ($i = 0; $i -lt $networkDevices.Count; $i++) {
    Write-Host "$($i+1). IP: $($networkDevices[$i].IP) - MAC: $($networkDevices[$i].MAC) - Type: $($networkDevices[$i].Type)"
}

# Get user selection for the network device to copy MAC from
do {
    $networkSelection = Read-Host "`nSelect network device number to copy MAC from (1-$($networkDevices.Count))"
    $networkSelection = $networkSelection -as [int]
} while ($networkSelection -lt 1 -or $networkSelection -gt $networkDevices.Count)

$selectedDevice = $networkDevices[$networkSelection-1]
$newMac = $selectedDevice.MAC

# Show available adapters
Write-Host "`nAvailable Network Adapters:"
for ($i = 0; $i -lt $adapters.Count; $i++) {
    Write-Host "$($i+1). $($adapters[$i].Name) - $($adapters[$i].MacAddress)"
}

# Get user selection for adapter to modify
do {
    $adapterSelection = Read-Host "`nSelect adapter number to modify (1-$($adapters.Count))"
    $adapterSelection = $adapterSelection -as [int]
} while ($adapterSelection -lt 1 -or $adapterSelection -gt $adapters.Count)

$selectedAdapter = $adapters[$adapterSelection-1]

# Show current and new MAC
Write-Host "`nCurrent MAC Address: $($selectedAdapter.MacAddress)"
Write-Host "New MAC Address (from selected device): $newMac"

# Confirm change
$confirm = Read-Host "`nProceed with MAC address change? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Operation cancelled."
    exit
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
$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') > $null
