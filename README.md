# sagespice
Powershell script that primes the VM display and gets and automatically launches the .vv file for virt_viewer.

Authenticates to proxmox and gets a ticket
Calls vncproxy to wake up all 4 SPICE display heads
Waits 2 seconds for QEMU to initialise them
Fetches the SPICE ticket and writes the .vv file
Launches virt-viewer with the .vv file.


Prereqs - Working Spice on client and server.

Edit the powershell file with your relevant config details and launch it.

Enjoy


