#!/bin/sh

sudo umount /dev/sda1 /dev/sda2

# raspian lite 32bit
wget https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2020-12-04/2020-12-02-raspios-buster-armhf-lite.zip -q -O -| funzip | sudo dd of=/dev/sda bs=4M

sudo mount /dev/sda1 /media/yakir/boot
sudo mount /dev/sda2 /media/yakir/rootfs

# julia 1.3.1
wget https://julialang-s3.julialang.org/bin/linux/armv7l/1.3/julia-1.3.1-linux-armv7l.tar.gz -q -O - | tar -xzf - -C /media/yakir/rootfs/home/pi/

# julia 1.5.3
wget https://julialangnightlies.s3.amazonaws.com/pretesting/linux/armv7l/1.5/julia-788b2c77c1-linuxarmv7l.tar.gz -q -O - | tar -xzf - -C /media/yakir/rootfs/home/pi/

# julia 1.6
wget https://s3.amazonaws.com/julialangnightlies/assert_pretesting/linux/armv7l/1.6/julia-a8393c4a3b-linuxarmv7l.tar.gz -q -O - | tar -xzf - -C /media/yakir/rootfs/home/pi/

     https://s3.amazonaws.com/julialangnightlies/assert_pretesting/linux/armv7l/1.6/julia-a8393c4a3b-linuxarmv7l.tar.gz

# kill on board LEDs and allow greyworld
echo "disable_camera_led=1
awb_auto_is_greyworld=1
start_x=1
gpu_mem=128" >> /media/yakir/boot/config.txt 

# echo "[pi4]
# # Disable the PWR LED
# dtparam=pwr_led_trigger=none
# dtparam=pwr_led_activelow=off
# # Disable the Activity LED
# dtparam=act_led_trigger=none
# dtparam=act_led_activelow=off
# # Disable ethernet port LEDs
# dtparam=eth_led0=4
# dtparam=eth_led1=4" >> /media/yakir/boot/config.txt 

# harden ssh
sudo tee -a /media/yakir/rootfs/etc/ssh/sshd_config > /dev/null <<EOT
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
UsePAM no
X11Forwarding no
EOT

# enable sshing
mkdir /media/yakir/rootfs/home/pi/.ssh 
chmod 700 /media/yakir/rootfs/home/pi/.ssh
cp ~/.ssh/authorized_keys /media/yakir/rootfs/home/pi/.ssh/
chmod 600 /media/yakir/rootfs/home/pi/.ssh/authorized_keys
touch /media/yakir/boot/SSH

# prepare auto mount
mkdir /media/yakir/rootfs/home/pi/mnt
chmod 770 /media/yakir/rootfs/home/pi/mnt
# echo "PARTUUID=78c0b7af-fa04-46d0-b119-3d80fe55942e /home/pi/mnt ext4 defaults,users,nofail 0 0" | sudo tee -a /media/yakir/rootfs/etc/fstab > /dev/null
# echo "PARTUUID=5b8d4d0d-01 /home/pi/mnt ext4 defaults,users,nofail 0 0" | sudo tee -a /media/yakir/rootfs/etc/fstab > /dev/null

# change hostname
sudo sed -i 's/raspberrypi/skyroom/g' /etc/hostname 
sudo sed -i 's/raspberrypi/skyroom/g' /etc/hosts


# add aws credentials
cp /home/yakir/.aws -rp /media/yakir/rootfs/home/pi/

sudo umount /dev/sda1 /dev/sda2
