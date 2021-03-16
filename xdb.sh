#! /bin/bash
echo "XPlayADB by soup-bowl - Version 0.1-Alpha"
echo "Works with R800i on Linux-based commands with fastboot."
echo "-----------------------------"

case "$OSTYPE" in
	"linux"*)
		if [[ $(uname -r) =~ WSL ]]
		then
			xadb="./platform-tools/windows/adb.exe"
		else
			xadb="./platform-tools/linux/adb"
		fi
		;;

	"darwin"*)
		xadb="./platform-tools/darwin/adb"
		;;

	*)
		xadb="adb"
		;;
esac

# Trims response from adb shell.
# Modified from https://stackoverflow.com/a/43432097
trim()
{
	if [[ $1 =~ ^[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]]
	then
		local result="${BASH_REMATCH[1]}"
	else
		local result="$1"
	fi
	eval $2=$result
}

# --- Pre-run tests ---
# Test for ADB.
if ! command -v $xadb > /dev/null 2>&1
then
	echo "Error: ADB package not found."
	exit 1
fi

isplugged=`${xadb} get-state`
if [[ $isplugged == "" ]]
then
	echo ""
	echo "Unable to get an Android Debugging response from phone."
	echo "Make sure that your phone:"
	echo "1) Is plugged in to a USB port with a cable that supports data transmission."
	echo "2) USB Debugging is enabled in settings > Applications > Development > USB debugging."
	exit 1
fi

trim $(${xadb} shell getprop ro.product.model) 'device'
if [[ $device == "R800i" ]]
then
	echo "Xperia PLAY $device detected!"
else
	echo "Device identifer was incorrect. Discovered '$device'. Expecting R800i."
	exit 1
fi

isrootcmd=$(${xadb} shell stat /system/bin/su 2>&1)
if [[ $isrootcmd == *"No such file or"* || $isrootcmd == *"permission den"* ]]
then
	isroot="ready to root"
else
	isroot="already rooted"
fi

echo "" >> ./system.log
echo "Starting xdb for $device" >> ./system.log
echo "Using $(${xadb} version) on ${OSTYPE}" >> ./system.log
echo "Timestamp: $(date)" >> ./system.log
echo "---------------" >> ./system.log

# --- Identify user desires ---
echo "What do you want to do?"
echo ""
echo "[1] Root device (${isroot})."
echo "[2] Install all apps."
echo "[3] Remove recognised bloatware (experimental - Requires root)."
echo ""
echo "[r] Reboot into fastboot."
echo "[q] Cancel."
echo ""
read -p 'choose [q]: ' choice

commands=()
case "$choice" in
	"1")
		# Thanks to DooMLoRD for the original impelementations.
		# Based upon:
		# https://forum.xda-developers.com/t/04-jan-rooting-unrooting-doomlords-easy-rooting-toolkit-v4-0-zergrush-exploit.1321582/
		# https://forum.xda-developers.com/t/how-to-zergrush-root-root-w-v2-2-x-2-3-x-not-ics-4-x-or-gb-after-11-2011.1312859/

		trim $(${xadb} shell echo true) 'resp'
		if [[ $resp != "true" ]]
		then
			echo "Error: Unable to run commands on device. Ensure ONLY the Xperia PLAY is plugged in, and Android Debugging is enabled."
			exit 1
		fi

		echo "> Preparing for exploit."
		$xadb shell "mkdir /data/local/rootmp" >> ./system.log
		$xadb push root/zergRush /data/local/rootmp/. >> ./system.log
		$xadb shell "chmod 777 /data/local/rootmp/zergRush" >> ./system.log
		echo "> Running zergRush exploit."
		$xadb shell "./data/local/rootmp/zergRush" >> ./system.log
		echo "> Exploit complete, waiting for device to re-appear."
		$xadb wait-for-device
		echo "> Installing BusyBox."
		$xadb push root/busybox /data/local/rootmp/. >> ./system.log
		$xadb shell "chmod 755 /data/local/rootmp/busybox" >> ./system.log
		diditwork=`${xadb} shell "/data/local/rootmp/busybox mount -o remount,rw /system"` >> ./system.log
		if [[ $diditwork == *"are you root"* ]]
		then
			echo ""
			echo "Root payload failed to install using zergRush exploit."
			echo "Flash a compatible exploitable firmware (e.g. R800i_4.0.2.A.0.58_Enhanced.ftf), or look on the XDA forums to find a root solution for your device."
			exit 1
		fi
		$xadb shell "dd if=/data/local/rootmp/busybox of=/system/xbin/busybox" >> ./system.log
		$xadb shell "chmod 04755 /system/xbin/busybox" >> ./system.log
		$xadb shell "/system/xbin/busybox --install -s /system/xbin" >> ./system.log
		echo "> Enabling the su (superuser) command."
		$xadb push root/su /system/bin/su >> ./system.log
		$xadb shell "chown 0:0 /system/bin/su" >> ./system.log
		$xadb shell "chmod 06755 /system/bin/su" >> ./system.log
		$xadb shell "rm /system/xbin/su" >> ./system.log
		$xadb shell "ln -s /system/bin/su /system/xbin/su" >> ./system.log
		echo "> Installing Superuser."
		$xadb push root/Superuser.apk /system/app/. >> ./system.log
		$xadb shell "rm -r /data/local/rootmp" >> ./system.log
		echo ""
		echo "Device rooted. Rebooting..."
		$xadb reboot
		exit
		;;
	
	"2")
		apks=($( ls apps/*.apk ))
		for ((i=0; i<${#apks[@]}; i++))
		do
			$xadb install -s ${apks[$i]}
		done
		exit
		;;
	
	"3")
		echo "This experimental feature will remove apps determined to be bloatware, or otherwise unnessesary for modern usage."
		echo "Based upon information found here - https://revive.today/xpapk (cellular)."
		echo "Further apps can be removed without detrimental effects depending on use, see the document linked above."
		echo "If you encounter issues, please report them at the GitHub tracker - https://github.com/soup-bowl/XPLAY-Manager."
		echo "THIS IS REMOVING SYSTEM APPS - BACKUP IMPORTANT DATA BEFORE EXECUTING THIS SCRIPT."
		echo ""
		echo "Do you wish to continue?"
		read -p 'choose [y/N]: ' choice

		commands=()
		case "$choice" in
			"y"|"Y")
				$xadb shell "su -c 'mount -o remount,rw /system /system'"
				sep=$'\n' ipt=($(cat removals.txt))
				for i in $(seq ${#ipt[*]})
				do
					if [[ ${ipt[$i]: -4} == ".apk" ]]
					then
						echo "Removing ${ipt[$i]} ..."
						$xadb shell "su -c 'rm ${ipt[$i]}'" >> ./system.log 2> ./system.log
					fi
				done
				echo "Removals complete - Rebooting..."
				$xadb reboot >> ./system.log
				exit
				;;
			*)
				echo "Exited."
				exit
				;;
		esac
		;;
	
	"r")
		echo "Rebooting. xfast command will work in fastboot mode."
		$xadb reboot bootloader >> ./system.log
		exit
		;;

	*)
		echo "Exited."
		exit
		;;
esac
