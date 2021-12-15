#!/bin/bash

printf '\033c'
echo "ARCH-INSTALLER"
read -rp "Rank mirrors for faster downloads? [y/n] " answer
timedatectl set-ntp true
if [[ $answer = y ]] ; then
	reflector -c 'Germany' -a 15 -p https --sort rate --save /etc/pacman.d/mirrorlist
fi
sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 5/" /etc/pacman.conf
pacman -Syyq --noconfirm archlinux-keyring
printf '\033c'

read -rp "Encrypt disk? [y/n]: " encryptanswer
if [[ $encryptanswer = y ]] ; then
	lsblk
	echo -n "Enter the drive (/dev/sdX): "
	read -r drive
	wipefs --all "$drive"
	parted -s "$drive" mklabel msdos
	parted -s -a optimal "$drive" mkpart "primary" "fat16" "0%" "1024MiB"
	parted -s "$drive" set 1 boot on
	parted -s "$drive" align-check optimal 1
	parted -s -a optimal "$drive" mkpart "primary" "ext4" "1024MiB" "100%"
	parted -s "$drive" set 2 lvm on
	printf '\033c'
	echo "Force loading the Linux kernel modules related to Serpent and other strong encryptions..."
	cryptsetup benchmark > /dev/null
	printf '\033c'
	cryptsetup --type luks1 --cipher serpent-xts-plain64 --key-size 512 \
	 			--hash whirlpool --iter-time 5000 --use-random --verify-passphrase luksFormat "$drive"2
	cryptsetup luksOpen "$drive"2 lvm-system
	pvcreate /dev/mapper/lvm-system > /dev/null
	vgcreate lvmSystem /dev/mapper/lvm-system > /dev/null
	printf '\033c'
	read -rp "Do you need swap? [y/n]: " swapanswer
	if [[ $swapanswer = y ]] ; then
		echo "How much? (example: 4G, 8G, 12G): "
		read -r swap
		lvcreate -L "$swap" lvmSystem -n volSwap > /dev/null
		mkswap /dev/lvmSystem/volSwap > /dev/null
		swapon /dev/lvmSystem/volSwap
	fi
	lvcreate -l +100%FREE lvmSystem -n volRoot > /dev/null
	mkfs.fat -n BOOT "$drive"1 > /dev/null
	mkfs.ext4 -L volRoot /dev/lvmSystem/volRoot > /dev/null
	mount /dev/lvmSystem/volRoot /mnt
	mkdir /mnt/boot
	mount "$drive"1 /mnt/boot
else
	lsblk
	echo -n "Enter the drive (/dev/sdX): "
	read -r drive
	cfdisk "$drive"
	printf '\033c'
	read -rp "Another drive? [y/n] " answer
	if [[ $answer = y ]] ; then
		lsblk
		echo -n "Enter the drive (/dev/sdX): "
		read -r drive
		cfdisk "$drive"
	fi
	printf '\033c'
	lsblk
	echo -n "Enter the linux partition (/dev/sdXY): "
	read -r partition
	mkfs.ext4 -L ROOT "$partition" > /dev/null
	mount "$partition" /mnt
	printf '\033c'
	read -rp "Did you create a efi partition? [y/n] " answer
	if [[ $answer = y ]] ; then
		printf '\033c'
		lsblk
		echo -n "Enter EFI partition: "
		read -r efipartition
		mkfs.fat -F32 -n EFI "$efipartition" > /dev/null
		mkdir -p /mnt/boot/efi
		mount "$efipartition" /mnt/boot/efi
		printf '\033c'
	fi
	read -rp "Did you also create a home partition? [y/n] " answer
	if [[ $answer = y ]] ; then
		echo -n "Enter home partition: "
		read -r homepartition
		mkfs.ext4 -L HOME "$homepartition" > /dev/null
		mkdir /mnt/home
		mount "$homepartition" /mnt/home
	fi
fi
printf '\033c'
pacstrap /mnt base base-devel linux linux-firmware
genfstab -U /mnt >> /mnt/etc/fstab
sed '1,/^#chroot$/d' install.sh > /mnt/install2.sh
chmod +x /mnt/install2.sh
arch-chroot /mnt ./install2.sh
exit

#chroot
#!/bin/bash
printf '\033c'
echo -n "Enter Hostname: "
read -r hostname
echo -n "Give Root a "
passwd
echo -n "Create a new Username: "
read -r username
useradd -m -G audio,video,input,wheel,sys,log,rfkill,lp,adm -s /bin/bash "$username"
passwd "$username"
read -rp "Is this a UEFI installation? [y/n] " uefianswer
if [[ $uefianswer = n ]] ; then
	echo -n "Enter your main drive (/dev/sdX): "
	read -r drive
fi
read -rp "Did you encrypted the disk? [y/n]: " encryptanswer
if [[ $encryptanswer = y ]] ; then
	echo -n "Enter your main drive (/dev/sdX): "
	read -r drive
fi
read -rp "Do you need Wi-Fi? [y/n] " wifianswer

printf '\033c'
pacman -Sq --noconfirm sed
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 5/;s/^#Color$/Color/" /etc/pacman.conf
pacman -Syuq
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc --utc
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=de_DE.UTF-8" > /etc/locale.conf
export LANG=de_DE.UTF-8
echo "KEYMAP=de-latin1" > /etc/vconsole.conf
echo "$hostname" > /etc/hostname
{
	echo "127.0.0.1       localhost"
	echo "::1             localhost"
	echo "127.0.0.1       $hostname.localdomain $hostname"
} >> /etc/hosts
if [[ $encryptanswer = y ]] ; then
	sed -i "52 d" /etc/mkinitcpio.conf
	echo 'HOOKS=(base udev autodetect modconf block encrypt keyboard keymap lvm2 resume filesystems fsck)' >> /etc/mkinitcpio.conf
	pacman -Sq --noconfirm lvm2 cryptsetup grub libisoburn mtools dosfstools freetype2 fuse2
	rootuuid=$(blkid -s UUID -o value "$drive"2)
	sed -i "6 d" /etc/default/grub
	sed -i "/GRUB_CMDLINE_LINUX=\"\"/a GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=$rootuuid:lvm-system loglevel=3 quiet net.ifnames=0\"" /etc/default/grub
	{
		echo 'GRUB_ENABLE_CRYPTODISK="true"'
		echo 'GRUB_DISABLE_LINUX_RECOVERY="true"'
	} >> /etc/default/grub
	grub-install --target=i386-pc --boot-directory=/boot --bootloader-id=arch --recheck "$drive"
elif [[ $uefianswer = y ]] ; then
	pacman -Sq --noconfirm grub efibootmgr os-prober
	grub-install --target=x86_64-efi --bootloader-id=grub_uefi --efi-directory=/boot/efi --recheck
else
	pacman -Sq --noconfirm grub os-prober
	grub-install --target=i386-pc --recheck "$drive"
fi
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

pacman -Sq --noconfirm linux-headers vim git jshon expac git wget acpid avahi net-tools xdg-user-dirs \
                       sysfsutils usbutils e2fsprogs inetutils netctl less which \
                       man-db man-pages man-pages-de \
                       xorg-server xorg-xinit xorg-xrandr xorg-xfontsel \
                       xorg-xlsfonts xorg-xkill xorg-xinput \
                       xorg-xwininfo xorg-xsetroot xorg-xbacklight xorg-xprop xclip \
                       xf86-input-synaptics xf86-input-libinput xf86-input-evdev \
                       xf86-video-amdgpu xf86-video-intel xf86-video-vmware \
                       noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono \
                       ttf-joypixels ttf-font-awesome \
                       brightnessctl sxiv mpv zathura zathura-pdf-mupdf ffmpeg \
                       imagemagick libnotify pamixer unclutter firefox-i18n-de \
                       xcompmgr youtube-dl rsync dunst arandr \
                       mesa vulkan-icd-loader \
                       networkmanager \
                       p7zip unrar unarchiver unzip unace xz rsync \
                       nfs-utils cifs-utils ntfs-3g exfat-utils \
                       alsa-utils pulseaudio-alsa pulseaudio-equalizer \
                       dash zsh zsh-completions zsh-syntax-highlighting


if [[ $wifianswer = y ]] ; then
	pacman -Sq --noconfirm wireless_tools wpa_supplicant ifplugd dialog
fi

systemctl enable acpid avahi-daemon NetworkManager lightdm

rm /bin/sh
ln -s dash /bin/sh
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
useradd -m -G audio,video,input,wheel,sys,log,rfkill,lp,adm -s /bin/zsh "$username"

# Disable beep
rmmod pcspkr
echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

printf '\033c'
install3_path=/home/$username/install3.sh
sed '1,/^#postinstall$/d' install2.sh > "$install3_path"
chown "$username":"$username" "$install3_path"
chmod +x "$install3_path"
su -c "$install3_path" -s /bin/sh "$username"
exit

#postinstall
#!/bin/bash
printf '\033c'
cd "$HOME" || exit

git clone --separate-git-dir="$HOME"/.dotfiles https://github.com/yungsnowx/dotfiles.git tmpdotfiles
rsync --recursive --verbose --exclude '.git' tmpdotfiles/ "$HOME"/
rm -r tmpdotfiles
git clone --depth=1 https://github.com/yungsnowx/dwm.git ~/.local/src/dwm
sudo make -C ~/.local/src/dwm clean install
git clone --depth=1 https://github.com/yungsnowx/st.git ~/.local/src/st
sudo make -C ~/.local/src/st install
git clone --depth=1 https://github.com/yungsnowx/dmenu.git ~/.local/src/dmenu
sudo make -C ~/.local/src/dmenu install

ln -s ~/.config/x11/xinitrc .xinitrc
ln -s ~/.config/shell/profile .zprofile
rm ~/.zshrc ~/.zsh_history
alias dots='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
dots config --local status.showUntrackedFiles no

printf '\033c'
echo "Finished!"
echo "You can reboot now."
echo "Please login with the root user and then with your own user. You need to set the passwords!."
echo "Do: umount -R /mnt && reboot"
exit
