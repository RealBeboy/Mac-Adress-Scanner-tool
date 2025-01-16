import subprocess
import re
import platform
import json
from typing import Dict, List, Tuple

class DeviceIdentifier:
    # Common MAC address prefixes and their manufacturers
    MAC_PREFIXES = {
        'CC:46:D6': 'Cisco',
        'F8:B1:56': 'Dell',
        'C4:65:16': 'Apple',
        '3C:22:FB': 'Apple iPhone',
        '28:CF:DA': 'Apple iPad',
        '00:50:56': 'VMware',
        'DC:A6:32': 'Raspberry Pi',
        '00:25:00': 'Apple',
        'B8:27:EB': 'Raspberry Pi',
        '00:0C:29': 'VMware',
        'AC:DE:48': 'Private',
        '00:1A:11': 'Google',
        '00:1B:63': 'Apple',
    }
    
    # Device type patterns
    DEVICE_PATTERNS = {
        r'iphone|ipad|ios': 'iOS Device',
        r'android': 'Android Device',
        r'mac|macbook|imac': 'Mac Computer',
        r'windows|pc|desktop': 'Windows PC',
        r'printer': 'Printer',
        r'tv|smart.?tv': 'Smart TV',
        r'playstation|ps[0-9]': 'PlayStation',
        r'xbox': 'Xbox',
        r'camera': 'IP Camera',
        r'roku|firestick|chromecast': 'Streaming Device'
    }

    @staticmethod
    def predict_device(mac: str, hostname: str = '') -> str:
        """Predict device type based on MAC address and hostname."""
        mac = mac.upper()
        hostname = hostname.lower()
        
        # Check first 8 chars of MAC (manufacturer prefix)
        mac_prefix = mac[:8].replace(':', '').replace('-', '')
        vendor = None
        
        # Look for known manufacturer prefixes
        for prefix, manufacturer in DeviceIdentifier.MAC_PREFIXES.items():
            prefix = prefix.replace(':', '').replace('-', '')
            if mac_prefix.startswith(prefix):
                vendor = manufacturer
                break
        
        # Check hostname patterns for device type
        device_type = 'Unknown Device'
        for pattern, device in DeviceIdentifier.DEVICE_PATTERNS.items():
            if re.search(pattern, hostname, re.IGNORECASE):
                device_type = device
                break
                
        if vendor:
            if device_type == 'Unknown Device':
                return f"{vendor} Device"
            return f"{vendor} {device_type}"
            
        return device_type

def get_network_devices() -> List[Dict[str, str]]:
    """
    Get information about devices connected to the local network.
    Returns a list of dictionaries containing IP, MAC, and predicted device type.
    """
    devices = []
    system = platform.system().lower()
    
    try:
        if system == "windows":
            # Get ARP table on Windows
            output = subprocess.check_output("arp -a", shell=True).decode()
            # Parse IP and MAC addresses
            pattern = r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+([0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2})'
            
        elif system in ["linux", "darwin"]:  # Linux or macOS
            # Get ARP table on Linux/Mac
            output = subprocess.check_output(["arp", "-a"]).decode()
            # Parse IP and MAC addresses
            pattern = r'\((\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\) at ([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})'
        
        else:
            return [{"error": "Unsupported operating system"}]
        
        # Find all IP and MAC address pairs
        device_matches = re.findall(pattern, output)
        
        # Get hostname information if possible
        try:
            hostname_output = subprocess.check_output(["nslookup"] + [ip for ip, _ in device_matches], 
                                                    stderr=subprocess.DEVNULL).decode()
        except:
            hostname_output = ""
        
        # Process each device
        for ip, mac in device_matches:
            # Clean up MAC address
            clean_mac = mac.replace(":", "").replace("-", "").upper()
            
            # Try to get hostname from nslookup output
            hostname = ""
            hostname_match = re.search(rf'{ip}.*?name = (.*?)[\n\r]', hostname_output, re.DOTALL)
            if hostname_match:
                hostname = hostname_match.group(1).strip()
            
            # Predict device type
            device_type = DeviceIdentifier.predict_device(mac, hostname)
            
            device_info = {
                "ip": ip,
                "mac": clean_mac,
                "predicted_device": device_type,
                "hostname": hostname
            }
            
            if device_info not in devices:
                devices.append(device_info)
                
        return devices
        
    except subprocess.CalledProcessError:
        return [{"error": "Error executing network commands"}]
    except Exception as e:
        return [{"error": f"Error: {str(e)}"}]

def print_device_table(devices: List[Dict[str, str]]) -> None:
    """Print device information in a formatted table."""
    if not devices:
        print("No devices found")
        return
        
    # Find the maximum width for each column
    ip_width = max(len(d['ip']) for d in devices)
    mac_width = max(len(d['mac']) for d in devices)
    device_width = max(len(d['predicted_device']) for d in devices)
    
    # Print header
    print("\n" + "=" * (ip_width + mac_width + device_width + 8))
    print(f"{'IP Address':<{ip_width}} | {'MAC Address':<{mac_width}} | {'Predicted Device':<{device_width}}")
    print("-" * (ip_width + mac_width + device_width + 8))
    
    # Print each device
    for device in devices:
        print(f"{device['ip']:<{ip_width}} | {device['mac']:<{mac_width}} | {device['predicted_device']:<{device_width}}")
    
    print("=" * (ip_width + mac_width + device_width + 8))

if __name__ == "__main__":
    print("Scanning network for connected devices...")
    devices = get_network_devices()
    
    if devices and "error" not in devices[0]:
        print_device_table(devices)
    else:
        print(f"Error: {devices[0].get('error', 'Unknown error occurred')}")