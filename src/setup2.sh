#!/bin/sh

# Set timezone to America/New_York
cp /etc/timezone /etc/timezone.dist
echo "Europe/Stockholm" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# Set the keyboard to US, don't set any modifier keys, etc.
cp /etc/default/keyboard /etc/default/keyboard.dist
sed -i -e "/XKBLAYOUT=/s/gb/us/" /etc/default/keyboard
service keyboard-setup restart

# LED and camera setup
sudo raspi-config nonint do_i2c 0
sudo raspi-config nonint do_spi 0
sudo raspi-config nonint do_camera 0
sudo apt-get -y install python3-pip python-smbus i2c-tools python3-picamera
sudo pip3 install --upgrade setuptools
sudo pip3 install RPI.GPIO adafruit-blinka adafruit-circuitpython-dotstar

# ngrok
sudo -u pi wget https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.zip -O /tmp/ngrok.zip
unzip /tmp/ngrok.zip -d /usr/local/bin/

# julia
pip3 install jill --user -U
~/.local/bin/jill install --confirm

# HD
mkdir -p /media/pi/videos
echo 'UUID=c8e182ae-7125-45b6-b3b9-4525d754c7a3 /media/pi/videos ext4 defaults 0' | sudo tee -a /etc/fstab

reboot 
