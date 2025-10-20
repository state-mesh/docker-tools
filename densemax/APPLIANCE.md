# Appliance installation

```shell
sudo su

# install Mellanox infiniband
cd /root/MLNX_OFED_LINUX-24.10-3.2.5.0-ubuntu24.04-x86_64
./mlnxofedinstall

# configure network
nano /etc/netplan//50-cloud-init.yaml
```yaml
network:
  version: 2
  ethernets:
    enp225s0f0:
      dhcp4: false
      addresses:
        - 172.17.30.156/24
      routes:
          - to: default
            via: 172.17.30.254
            metric: 100
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      
# rename Mellanox interface to ib0
# 1. find the serial number for the Mellanox card from `lshw -C network`

nano /etc/systemd/network/10-ib.link
```text
[Match]
PermanentMACAddress=10:70:fd:c0:de:88

[Link]
Name=ib0
```
netplan try
netplan apply

mst start
lspci -nn | grep -i mellanox # get the PIC ID of the Mellanox card
# 61:00.0 Ethernet controller [0200]: Mellanox Technologies MT27800 Family [ConnectX-5] [15b3:1017]

# Enable SR-IOV in the NIC's Firmware.
mlxconfig -d 61:00.0 set SRIOV_EN=1 NUM_OF_VFS=8 (16 is better)
reboot

# Enable SR-IOV in the NIC's Driver.
ibdev2netdev
echo 4 > /sys/class/net/ib0/device/sriov_numvfs


git clone -b 580.82.09 https://github.com/NVIDIA/open-gpu-kernel-modules.git
cd open-gpu-kernel-modules/
sudo rmmod gdrdrv nvidia_drm nvidia_modeset nvidia_uvm nvidia
rm /lib/modules/6.8.0-84-generic/kernel/drivers/video/nvidia*

make modules -j$(nproc)
make modules_install -j$(nproc)
modprobe nvidia
update-initramfs -u

wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.82.09/NVIDIA-Linux-x86_64-580.82.09.run
chmod 755 ./NVIDIA-Linux-x86_64-580.82.09.run 
./NVIDIA-Linux-x86_64-580.82.09.run --no-kernel-modules
reboot

cd /root
wget https://developer.download.nvidia.com/compute/cuda/12.9.1/local_installers/cuda_12.9.1_575.57.08_linux.run
sh cuda_12.9.0_575.51.03_linux.run (install only the toolkit, without the driver)

apt install build-essential devscripts debhelper fakeroot pkg-config dkms

## GDR is not supported on RTX 5090
cd /root
git clone https://github.com/NVIDIA/gdrcopy.git 
cd gdrcopy
cd packages
CUDA=/usr/loca/cuda ./build-deb-packages.sh
dpkg -i gdrdrv-dkms_2.5.1-1_amd64.Ubuntu24_04.deb
dpkg -i libgdrapi_2.5.1-1_amd64.Ubuntu24_04.deb
dpkg -i gdrcopy-tests_2.5.1-1_amd64.Ubuntu24_04+cuda12.9.deb 
dpkg -i gdrcopy_2.5.1-1_amd64.Ubuntu24_04.deb 
```
