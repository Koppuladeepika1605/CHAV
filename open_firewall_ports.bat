@echo off
echo Opening firewall ports for CHAV Telehealth App...
echo.

netsh advfirewall firewall delete rule name="CHAV Flutter Web" >nul 2>&1
netsh advfirewall firewall delete rule name="CHAV LiveKit HTTP" >nul 2>&1
netsh advfirewall firewall delete rule name="CHAV LiveKit TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="CHAV LiveKit UDP" >nul 2>&1

netsh advfirewall firewall add rule name="CHAV Flutter Web" dir=in action=allow protocol=TCP localport=5678
netsh advfirewall firewall add rule name="CHAV LiveKit HTTP" dir=in action=allow protocol=TCP localport=7880
netsh advfirewall firewall add rule name="CHAV LiveKit TCP" dir=in action=allow protocol=TCP localport=7881
netsh advfirewall firewall add rule name="CHAV LiveKit UDP" dir=in action=allow protocol=UDP localport=7882

echo.
echo =============================================
echo  DONE! All ports opened successfully.
echo  Patient can now open: http://192.168.0.1:5678

echo =============================================
pause
