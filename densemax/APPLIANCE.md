# Appliance installation

```shell
sudo su

git clone -b 580.82.09 https://github.com/NVIDIA/open-gpu-kernel-modules.git
cd open-gpu-kernel-modules/
sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia
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