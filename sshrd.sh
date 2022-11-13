#!/usr/bin/env sh

set -e

oscheck=$(uname)
archceheck=$(arch)
abicheck="$(uname)/$(arch)"

ERR_HANDLER () {
    [ $? -eq 0 ] && exit
    echo "[-] An error occurred"
    rm -rf work
}

trap ERR_HANDLER EXIT

# git submodule update --init --recursive

if [ ! -e "$oscheck"/"$archcheck"/gaster ]; then
    curl -sLO https://nightly.link/palera1n/gaster/workflows/makefile/main/gaster-"$oscheck".zip
    unzip gaster-"$oscheck".zip
    mv gaster "$oscheck"/
    rm -rf gaster gaster-"$oscheck".zip
fi

chmod +x "$abicheck"/*

if [ "$abicheck" = 'Darwin' ]; then
    if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); then
        echo "[*] Waiting for device in DFU mode"
    fi
    
    while ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); do
        sleep 1
    done
else
    if ! (lsusb 2> /dev/null | grep ' Apple, Inc. Mobile Device (DFU Mode)' >> /dev/null); then
        echo "[*] Waiting for device in DFU mode"
    fi
    
    while ! (lsusb 2> /dev/null | grep ' Apple, Inc. Mobile Device (DFU Mode)' >> /dev/null); do
        sleep 1
    done
fi

check=$("$abicheck"/irecovery -q | grep CPID | sed 's/CPID: //')
replace=$("$abicheck"/irecovery -q | grep MODEL | sed 's/MODEL: //')
deviceid=$("$abicheck"/irecovery -q | grep PRODUCT | sed 's/PRODUCT: //')
ipswurl=$(curl -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$abicheck"/jq '.firmwares | .[] | select(.version=="'$1'")' | "$abicheck"/jq -s '.[0] | .url' --raw-output)

if [ -e work ]; then
    rm -rf work
fi

if [ ! -e sshramdisk ]; then
    mkdir sshramdisk
fi

if [ "$1" = 'boot' ]; then
    if [ ! -e sshramdisk/iBSS.img4 ]; then
        echo "[-] Please create an SSH ramdisk first!"
        exit
    fi

    "$abicheck"/gaster pwn
    sleep 1
    "$abicheck"/gaster reset
    sleep 1
    "$abicheck"/irecovery -f sshramdisk/iBSS.img4
    sleep 2
    "$abicheck"/irecovery -f sshramdisk/iBEC.img4
    if [ "$check" = '0x8010' ] || [ "$check" = '0x8015' ] || [ "$check" = '0x8011' ] || [ "$check" = '0x8012' ]; then
        sleep 1
        "$abicheck"/irecovery -c go
    fi
    sleep 1
    "$abicheck"/irecovery -f sshramdisk/bootlogo.img4
    sleep 1
    "$abicheck"/irecovery -c "setpicture 0x1"
    sleep 1
    "$abicheck"/irecovery -f sshramdisk/ramdisk.img4
    sleep 1
    "$abicheck"/irecovery -c ramdisk
    sleep 1
    "$abicheck"/irecovery -f sshramdisk/devicetree.img4
    sleep 1
    "$abicheck"/irecovery -c devicetree
    sleep 1
    "$abicheck"/irecovery -f sshramdisk/trustcache.img4
    sleep 1
    "$abicheck"/irecovery -c firmware
    sleep 1
    "$abicheck"/irecovery -f sshramdisk/kernelcache.img4
    sleep 1
    "$abicheck"/irecovery -c bootx

    echo "[*] Device should now show text on screen"
    exit
fi

if [ -z "$1" ]; then
    printf "1st argument: iOS version for the ramdisk\n"
    exit
fi

if [ ! -e work ]; then
    mkdir work
fi

"$abicheck"/gaster pwn
"$abicheck"/img4tool -e -s shsh/"${check}".shsh -m work/IM4M

cd work
../"$abicheck"/pzb -g BuildManifest.plist "$ipswurl"
../"$abicheck"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"
../"$abicheck"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"
../"$abicheck"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/DeviceTree[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"

if [ "$abicheck" = 'Darwin' ]; then
    ../"$abicheck"/pzb -g Firmware/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)".trustcache "$ipswurl"
else
    ../"$abicheck"/pzb -g Firmware/"$(../Linux/PlistBuddy BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')".trustcache "$ipswurl"
fi

../"$abicheck"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"

if [ "$abicheck" = 'Darwin' ]; then
    ../"$abicheck"/pzb -g "$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" "$ipswurl"
else
    ../"$abicheck"/pzb -g "$(../Linux/PlistBuddy BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')" "$ipswurl"
fi

cd ..
"$abicheck"/gaster decrypt work/"$(awk "/""${replace}""/{x=1}x&&/iBSS[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')" work/iBSS.dec
"$abicheck"/gaster decrypt work/"$(awk "/""${replace}""/{x=1}x&&/iBEC[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')" work/iBEC.dec
"$abicheck"/iBoot64Patcher work/iBSS.dec work/iBSS.patched
"$abicheck"/img4 -i work/iBSS.patched -o sshramdisk/iBSS.img4 -M work/IM4M -A -T ibss
"$abicheck"/iBoot64Patcher work/iBEC.dec work/iBEC.patched -b "rd=md0 debug=0x2014e -v wdt=-1 `if [ -z "$2" ]; then :; else echo "$2=$3"; fi` `if [ "$check" = '0x8960' ] || [ "$check" = '0x7000' ] || [ "$check" = '0x7001' ]; then echo "-restore"; fi`" -n
"$abicheck"/img4 -i work/iBEC.patched -o sshramdisk/iBEC.img4 -M work/IM4M -A -T ibec

"$abicheck"/img4 -i work/"$(awk "/""${replace}""/{x=1}x&&/kernelcache.release/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" -o work/kcache.raw
"$abicheck"/Kernel64Patcher work/kcache.raw work/kcache.patched -a
python3 kerneldiff.py work/kcache.raw work/kcache.patched work/kc.bpatch
"$abicheck"/img4 -i work/"$(awk "/""${replace}""/{x=1}x&&/kernelcache.release/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" -o sshramdisk/kernelcache.img4 -M work/IM4M -T rkrn -P work/kc.bpatch `if [ "$abicheck" = 'Linux' ]; then echo "-J"; fi`
"$abicheck"/img4 -i work/"$(awk "/""${replace}""/{x=1}x&&/DeviceTree[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]//')" -o sshramdisk/devicetree.img4 -M work/IM4M -T rdtr

if [ "$abicheck" = 'Darwin' ]; then
    "$abicheck"/img4 -i work/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)".trustcache -o sshramdisk/trustcache.img4 -M work/IM4M -T rtsc
    "$abicheck"/img4 -i work/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" -o work/ramdisk.dmg
else
    "$abicheck"/img4 -i work/"$(Linux/PlistBuddy work/BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')".trustcache -o sshramdisk/trustcache.img4 -M work/IM4M -T rtsc
    "$abicheck"/img4 -i work/"$(Linux/PlistBuddy work/BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')" -o work/ramdisk.dmg
fi

if [ "$abicheck" = 'Darwin' ]; then
    hdiutil resize -size 256MB work/ramdisk.dmg
    hdiutil attach -mountpoint /tmp/SSHRD work/ramdisk.dmg

    "$abicheck"/gtar -x --no-overwrite-dir -f other/ramdisk.tar.gz -C /tmp/SSHRD/

    if [ ! "$2" = 'rootless' ]; then
        curl -LO https://nightly.link/elihwyma/Pogo/workflows/build/root/Pogo.zip
        mv Pogo.zip work/Pogo.zip
        unzip work/Pogo.zip -d work/Pogo
        unzip work/Pogo/Pogo.ipa -d work/Pogo/Pogo
        rm -rf /tmp/SSHRD/usr/local/bin/loader.app/*
        cp -R work/Pogo/Pogo/Payload/Pogo.app/* /tmp/SSHRD/usr/local/bin/loader.app
        mv /tmp/SSHRD/usr/local/bin/loader.app/Pogo /tmp/SSHRD/usr/local/bin/loader.app/Tips
    fi

    hdiutil detach -force /tmp/SSHRD
    hdiutil resize -sectors min work/ramdisk.dmg
else
    if [ -f other/ramdisk.tar.gz ]; then
        gzip -d other/ramdisk.tar.gz
    fi

    "$abicheck"/hfsplus work/ramdisk.dmg grow 300000000 > /dev/null
    "$abicheck"/hfsplus work/ramdisk.dmg untar other/ramdisk.tar > /dev/null

    if [ ! "$2" = 'rootless' ]; then
        curl -LO https://nightly.link/elihwyma/Pogo/workflows/build/root/Pogo.zip
        mv Pogo.zip work/Pogo.zip
        unzip work/Pogo.zip -d work/Pogo
        unzip work/Pogo/Pogo.ipa -d work/Pogo/Pogo
        mkdir -p work/Pogo/uwu/usr/local/bin/loader.app
        cp -R work/Pogo/Pogo/Payload/Pogo.app/* work/Pogo/uwu/usr/local/bin/loader.app

        "$abicheck"/hfsplus work/ramdisk.dmg rmall usr/local/bin/loader.app > /dev/null
        "$abicheck"/hfsplus work/ramdisk.dmg addall work/Pogo/uwu > /dev/null
        "$abicheck"/hfsplus work/ramdisk.dmg mv /usr/local/bin/loader.app/Pogo /usr/local/bin/loader.app/Tips > /dev/null
    fi
fi
"$abicheck"/img4 -i work/ramdisk.dmg -o sshramdisk/ramdisk.img4 -M work/IM4M -A -T rdsk
"$abicheck"/img4 -i other/bootlogo.im4p -o sshramdisk/bootlogo.img4 -M work/IM4M -A -T rlgo

rm -rf work
