#!/bin/sh

sudo chown -R pi:pi /home/pi/mnt
sudo usermod -a -G dialout $USER
sudo passwd pi
sudo timedatectl set-timezone Europe/Stockholm
sudo apt-get update
sudo apt-get -y upgrade 
sudo apt-get install -y python3-picamera awscli python3-distutils
sudo ln -s /home/pi/julia-1.3.1/bin/julia /usr/local/bin/julia
sudo reboot -h now
