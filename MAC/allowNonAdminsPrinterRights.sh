#!/bin/bash

# Define the URL of the cupsd.conf file in Azure Blob Storage
AZURE_CUPS_CONF_URL="https://ssintunedata.blob.core.windows.net/printers/cupsd.conf"

# Define a temporary path to store the downloaded cupsd.conf file
TEMP_CUPS_CONF="/tmp/cupsd.conf"

# Download the cupsd.conf file from Azure Blob Storage
curl -o "$TEMP_CUPS_CONF" "$AZURE_CUPS_CONF_URL"

# Check if the file was successfully downloaded
if [ ! -f "$TEMP_CUPS_CONF" ]; then
  echo "Failed to download cupsd.conf from Azure Blob Storage"
  exit 1
fi

# Backup existing cupsd.conf
if [ -f /etc/cups/cupsd.conf ]; then
  sudo cp /etc/cups/cupsd.conf /etc/cups/cupsd.conf.backup
fi

# Copy the downloaded cupsd.conf to /etc/cups/
sudo cp "$TEMP_CUPS_CONF" /etc/cups/cupsd.conf

# Restart the CUPS service to apply the new configuration
sudo launchctl stop org.cups.cupsd
sudo launchctl start org.cups.cupsd

# Cleanup the temporary file
rm "$TEMP_CUPS_CONF"

echo "cupsd.conf has been successfully updated and CUPS service restarted."
