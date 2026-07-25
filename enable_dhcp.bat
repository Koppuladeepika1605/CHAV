@echo off
echo =======================================================
echo  Enabling DHCP (Automatic IP) on Wi-Fi Interface...
echo =======================================================
echo.
echo Requesting Administrator privileges to modify network adapter...
powershell -Command "Start-Process powershell -ArgumentList '-Command Set-NetIPInterface -InterfaceAlias Wi-Fi -Dhcp Enabled; Set-DnsClientServerAddress -InterfaceAlias Wi-Fi -ResetServerAddresses' -Verb RunAs"
echo.
echo UAC prompt should have appeared. If approved, your Wi-Fi is now resetting.
echo.
pause
