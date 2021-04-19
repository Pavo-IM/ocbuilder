#!/bin/bash

prompt() {
    dialogTitle="OCBuilder"
    authPass=$(/usr/bin/osascript <<EOT
        tell application "System Events"
            activate
            repeat
                display dialog "This application requires administrator privileges. Please enter your administrator account password below to continue:" ¬
                    default answer "" ¬
                    with title "$dialogTitle" ¬
                    with hidden answer ¬
                    buttons {"Quit", "Continue"} default button 2
                if button returned of the result is "Quit" then
                    return 1
                    exit repeat
                else if the button returned of the result is "Continue" then
                    set pswd to text returned of the result
                    set usr to short user name of (system info)
                    try
                        do shell script "echo test" user name usr password pswd with administrator privileges
                        return pswd
                        exit repeat
                    end try
                end if
            end repeat
        end tell
    EOT
    )

    if [ "$authPass" == 1 ]
    then
        /bin/echo "User aborted. Exiting..."
        exit 0
    fi

    sudo () {
        /bin/echo $authPass | /usr/bin/sudo -S "$@"
    }
}

BUILD_DIR="${1}/OCBuilder_Clone"
TARGET_DIR="${2}"
FINAL_DIR="${2}/${3}_"
# ${$3} = "Debug" or "Release"
Bld_Type_Low="${3}"
Bld_Type_Upp=$(echo "${3}"| tr [:lower:] [:upper:])
# ${4} "X64" or "Ia32"
Bld_Arch_Low="${4}"
Bld_Arch_Upp=$(echo "${4}"| tr [:lower:] [:upper:])
# ${5} "0" (Without kexts), "1" (With kexts)
With_Kexts="${5}"
BackSlash_N="\\n"

Kexts_With="With"
if [ "${5}" = "0" ]; then
    Kexts_With="${Kexts_With}out"
fi

echo "${BackSlash_N}            OC Builder ${Bld_Type_Upp} (Arch ${Bld_Arch_Upp}) ${Kexts_With} Kexts"

echo "${BackSlash_N}Argc = $# & Argv = $@" |tee -a "${Build_Log}"

installnasm () {
    pushd /tmp >/dev/null || exit 1
    rm -rf nasm-mac64.zip
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/nasm-mac64.zip" || exit 1
    nasmzip=$(cat nasm-mac64.zip)
    rm -rf nasm-*
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${nasmzip}" || exit 1
    unzip -q "${nasmzip}" nasm*/nasm nasm*/ndisasm || exit 1
    if [ -d /usr/local/bin ]; then
        sudo mv nasm*/nasm /usr/local/bin/ || exit 1
        sudo mv nasm*/ndisasm /usr/local/bin/ || exit 1
        rm -rf "${nasmzip}" nasm-*
    else
        sudo mkdir -p /usr/local/bin || exit 1
        sudo mv nasm*/nasm /usr/local/bin/ || exit 1
        sudo mv nasm*/ndisasm /usr/local/bin/ || exit 1
        rm -rf "${nasmzip}" nasm-*
    fi
    popd >/dev/null || exit 1
}

installmtoc () {
    pushd /tmp >/dev/null || exit 1
    rm -f mtoc mtoc-mac64.zip
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/mtoc-mac64.zip" || exit 1
    mtoczip=$(cat mtoc-mac64.zip)
    rm -rf mtoc-*
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${mtoczip}" || exit 1
    unzip -q "${mtoczip}" mtoc || exit 1
    sudo rm -f /usr/local/bin/mtoc /usr/local/bin/mtoc.NEW || exit 1
    sudo cp mtoc /usr/local/bin/mtoc || exit 1
    popd >/dev/null || exit 1
    mtoc_path=$(which mtoc)
    mtoc_hash_user=$(shasum -a 256 "${mtoc_path}" | cut -d' ' -f1)
}

updaterepo() {
  if [ ! -d "${2}" ]; then
    git clone "${1}" -b "${3}" --depth=1 "${2}" || exit 1
  fi
  pushd "${2}" >/dev/null || exit 1
  git pull
  if [ "${2}" != "UDK" ] && [ "$(unamer)" != "Windows" ]; then
    sym=$(find . -not -type d -exec file "{}" ";" | grep CRLF)
    if [ "${sym}" != "" ]; then
      echo "${BackSlash_N}Repository ${1} named ${2} contains CRLF line endings"
      echo "${sym}"
      exit 1
    fi
  fi
  git submodule update --init --recommend-shallow || exit 1
  popd >/dev/null || exit 1
}

builddebug() {
  xcodebuild -arch x86_64 -configuration Debug  >/dev/null || return 1
}

buildrelease() {
  xcodebuild -arch x86_64 -configuration Release  >/dev/null || return 1
}

copyRepoToOthers() {
  cp -r
}

applesupportpackage() {
  pushd "$1" || exit 1
  rm -rf tmp || exit 1
  mkdir -p tmp/Drivers || exit 1
  mkdir -p tmp/Tools   || exit 1
  cp AudioDxe.efi tmp/Drivers/          || exit 1
  cp VBoxHfs.efi tmp/Drivers/           || exit 1
  pushd tmp || exit 1
  zip -qry -FS ../"AppleSupport-${ver}-${2}.zip" * || exit 1
  popd || exit 1
  rm -rf tmp || exit 1
  popd || exit 1
}

buildutil() {
  UTILS=(
    "AppleEfiSignTool"
    "EfiResTool"
    "disklabel"
    "icnspack"
    "macserial"
    "ocvalidate"
    "TestBmf"
    "TestDiskImage"
    "TestHelloWorld"
    "TestImg4"
    "TestKextInject"
    "TestMacho"
    "TestPeCoff"
    "TestRsaPreprocess"
    "TestSmbios"
  )

  if [ "$HAS_OPENSSL_BUILD" = "1" ]; then
    UTILS+=("RsaTool")
  fi

  local cores
  cores=$(getconf _NPROCESSORS_ONLN)

  pushd "${selfdir}/Utilities" || exit 1
  echo "${BackSlash_N}"
  for util in "${UTILS[@]}"; do
    cd "$util" || exit 1
    echo " Building ${util}..."
    make clean || exit 1
    make -j "$cores" || exit 1
    #
    # FIXME: Do not build RsaTool for Win32 without OpenSSL.
    #
    if [ "$util" = "RsaTool" ] && [ "$HAS_OPENSSL_W32BUILD" != "1" ]; then
      continue
    fi

    if [ "$(which i686-w64-mingw32-gcc)" != "" ]; then
      echo "${BackSlash_N}Building ${util} for Windows..."
      UDK_ARCH=${Bld_Arch_Low} CC=i686-w64-mingw32-gcc STRIP=i686-w64-mingw32-strip DIST=Windows make clean || exit 1
      UDK_ARCH=${Bld_Arch_Low} CC=i686-w64-mingw32-gcc STRIP=i686-w64-mingw32-strip DIST=Windows make -j "$cores" || exit 1
    fi
    cd - || exit 1
  done
  popd || exit
}

opencorepackage() {
  selfdir=$(pwd)
  pushd "$1" || exit 1
  rm -rf tmp || exit 1

  dirs=(
    "tmp/EFI/BOOT"
    "tmp/EFI/OC/ACPI"
    "tmp/EFI/OC/Bootstrap"
    "tmp/EFI/OC/Drivers"
    "tmp/EFI/OC/Kexts"
    "tmp/EFI/OC/Tools"
    "tmp/EFI/OC/Resources/Audio"
    "tmp/EFI/OC/Resources/Font"
    "tmp/EFI/OC/Resources/Image"
    "tmp/EFI/OC/Resources/Label"
    "tmp/Docs/AcpiSamples"
    "tmp/Utilities"
    )
  for dir in "${dirs[@]}"; do
    mkdir -p "${dir}" || exit 1
  done

  # copy OpenCore main program.
  cp OpenCore.efi tmp/EFI/OC/ || exit 1

  # Mark binaries to be recognisable by OcBootManagementLib.
  bootsig="${selfdir}/Library/OcBootManagementLib/BootSignature.bin"
  efiOCBMs=(
    "Bootstrap.efi"
    "OpenCore.efi"
    )
  for efiOCBM in "${efiOCBMs[@]}"; do
    dd if="${bootsig}" \
       of="${efiOCBM}" seek=64 bs=1 count=64 conv=notrunc || exit 1
  done
  cp Bootstrap.efi tmp/EFI/BOOT/BOOT${Bld_Arch_Low}.efi || exit 1
  cp Bootstrap.efi tmp/EFI/OC/Bootstrap/ || exit 1

  efiTools=(
    "BootKicker.efi"
    "ChipTune.efi"
    "CleanNvram.efi"
    "GopStop.efi"
    "KeyTester.efi"
    "MmapDump.efi"
    "ResetSystem.efi"
    "RtcRw.efi"
    "OpenControl.efi"
    )
  for efiTool in "${efiTools[@]}"; do
    cp "${efiTool}" tmp/EFI/OC/Tools/ || exit 1
  done
  # Special case: OpenShell.efi
  cp Shell.efi tmp/EFI/OC/Tools/OpenShell.efi || exit 1

  efiDrivers=(
    "HiiDatabase.efi"
    "NvmExpressDxe.efi"
    "AudioDxe.efi"
    "CrScreenshotDxe.efi"
    "OpenCanopy.efi"
    "OpenRuntime.efi"
    "OpenUsbKbDxe.efi"
    "Ps2MouseDxe.efi"
    "Ps2KeyboardDxe.efi"
    "UsbMouseDxe.efi"
    "XhciDxe.efi"
    )
  for efiDriver in "${efiDrivers[@]}"; do
    cp "${efiDriver}" tmp/EFI/OC/Drivers/ || exit 1
  done

  docs=(
    "Configuration.pdf"
    "Differences/Differences.pdf"
    "Sample.plist"
    "SampleCustom.plist"
    )
  for doc in "${docs[@]}"; do
    cp "${selfdir}/Docs/${doc}" tmp/Docs/ || exit 1
  done
  cp "${selfdir}/Changelog.md" tmp/Docs/ || exit 1
  cp -r "${selfdir}/Docs/AcpiSamples/" tmp/Docs/AcpiSamples/ || exit 1

  utilScpts=(
    "LegacyBoot"
    "CreateVault"
    "LogoutHook"
    "macrecovery"
    "kpdescribe"
    )
  for utilScpt in "${utilScpts[@]}"; do
    cp -r "${selfdir}/Utilities/${utilScpt}" tmp/Utilities/ || exit 1
  done

  # Copy OpenDuetPkg booter.
  local arch
  local tgt
  local booter
  arch="$(basename "$(pwd)")"
  tgt="$(basename "$(dirname "$(pwd)")")"
  booter="$(pwd)/../../../OpenDuetPkg/${tgt}/${arch}/boot"

  if [ -f "${booter}" ]; then
    echo "${BackSlash_N}Copying OpenDuetPkg boot file from ${booter}..."
    cp "${booter}" tmp/Utilities/LegacyBoot/boot || exit 1
  else
    echo "      Failed to find OpenDuetPkg at ${booter}!"
  fi

  buildutil || exit 1
  utils=(
    "macserial"
    "ocvalidate"
    "disklabel"
    "icnspack"
    )
  for util in "${utils[@]}"; do
    dest="tmp/Utilities/${util}"
    mkdir -p "${dest}" || exit 1
    bin="${selfdir}/Utilities/${util}/${util}"
    cp "${bin}" "${dest}" || exit 1
    binEXE="${bin}.exe"
    if [ -f "${binEXE}" ]; then
      cp "${binEXE}" "${dest}" || exit 1
    fi
  done
  # additional docs for macserial.
  cp "${selfdir}/Utilities/macserial/FORMAT.md" tmp/Utilities/macserial/ || exit 1
  cp "${selfdir}/Utilities/macserial/README.md" tmp/Utilities/macserial/ || exit 1

  pushd tmp || exit 1
  zip -qr -FS ../"OpenCore-${ver}-${2}.zip" ./* || exit 1
  popd || exit 1
  rm -rf tmp || exit 1
  popd || exit 1
}

opencoreudkclone() {
  echo "${BackSlash_N}Cloning AUDK Repo into OpenCorePkg ${OCLastRel} commit ${OCHash}..."
  updaterepo "https://github.com/acidanthera/audk" UDK master || exit 1
}

opencoreclone() {
  OCCommit_ID=$(git ls-remote https://github.com/acidanthera/OpenCorePkg.git|grep "HEAD"|cut -c1-7)
  echo "${BackSlash_N}Cloning OpenCorePkg Git repo (commit ${OCCommit_ID})..."
  git clone -q https://github.com/acidanthera/OpenCorePkg.git
}

ocbinarydataclone () {
  echo "${BackSlash_N}Cloning OcBinaryData Git repo..."
  git clone -q https://github.com/acidanthera/OcBinaryData.git
}

copyBuildProducts() {
  echo "${BackSlash_N}Copying compiled products into EFI Structure folder in ${FINAL_DIR}..."
  cp "${BUILD_DIR}"/OpenCorePkg/Binaries/${Bld_Type_Upp}/*.zip "${FINAL_DIR}/"

  cd "${FINAL_DIR}/"
  unzip *.zip  >/dev/null || exit 1
  rm -rf *.zip

  #Kext(s) copy
  if [ "${With_Kexts}" = "1" ]; then
	for KEXT in "${KEXTS[@]}"; do
		if [ $(echo "${KEXT}" | cut -c1-1) != "#" ]; then
    		KURL=$(echo "${KEXT}" | awk -F ';' '{print $1}')
    		KXID=$(echo "${KURL}" | awk -F '/' '{print $NF}' | awk -F '.' '{print $1}')
    		for KXBLD in $(find "${BUILD_DIR}/${KXID}/build/${Bld_Type_Low}" -name "*.kext" | grep -v "/PlugIns/");  do
            	cp -rf "${KXBLD}" "${FINAL_DIR}"/EFI/OC/Kexts
        	done
  			#Kext(s) Package(s) copy
        	mkdir -p "${FINAL_DIR}"/KextsPKG
     		for KXZIP in $(find "${BUILD_DIR}/${KXID}/build/${Bld_Type_Low}" -name "*-*-*.zip");  do
            	cp -rf "${KXZIP}" "${FINAL_DIR}"/KextsPKG
        	done
 		fi
	done
  fi
  cp -r "${BUILD_DIR}"/OcBinaryData/Resources "${FINAL_DIR}"/EFI/OC/
  cp -r "${BUILD_DIR}"/OcBinaryData/Drivers/*.efi "${FINAL_DIR}"/EFI/OC/Drivers
  sleep 5
  echo "${BackSlash_N}All Done!..."
}

if [ "${Bld_Type_Low}" = "Debug" ]; then
    if [ "${Bld_Arch_Low}" = "X64" ]; then
        Release="0"
    else
        if [ "${Bld_Arch_Low}" = "Ia32" ]; then
            Release="2"
        else
            exit 1
        fi
    fi
else
    if [ "${Bld_Type_Low}" = "Release" ]; then
        if [ "${Bld_Arch_Low}" = "X64" ]; then
            Release="1"
        else
            if [ "${Bld_Arch_Low}" = "Ia32" ]; then
                Release="3"
            else
                exit 1
            fi
        fi
    else
        exit 1
    fi
fi

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

if [ -d "${BUILD_DIR}" ]; then
  rm -rf "${BUILD_DIR}/" || exit 1
  sleep 5
fi
mkdir -p "${BUILD_DIR}" || exit 1
cd "${BUILD_DIR}"

echo "${BackSlash_N}Build   Directory is : ${BUILD_DIR}"
echo "Target Directory is : ${TARGET_DIR}"

if [ "${With_Kexts}" = "1" ]; then
#KEXTS : Col1=Kext(s) repo;Col2=Debug needed too;Col3=Dependance(s);Col4=Clone SubModule;Col5=Copy SubModule;Col6=Exit on Compil Abort
KEXTS=(
"https://github.com/acidanthera/Lilu.git;Y;N;https://github.com/acidanthera/MacKernelSDK;N;Y"
"https://github.com/acidanthera/AppleALC.git;N;Lilu;N;/Lilu/MacKernelSDK;N"
"https://github.com/acidanthera/WhateverGreen.git;N;Lilu;N;/Lilu/MacKernelSDK;N"
"https://github.com/acidanthera/VirtualSMC.git;Y;Lilu;N;/Lilu/MacKernelSDK;N"
"https://github.com/acidanthera/AirportBrcmFixup.git;N;Lilu;N;/Lilu/MacKernelSDK;N"
"https://github.com/Mieze/AtherosE2200Ethernet.git;N;N;N;N;N"
"https://github.com/acidanthera/IntelMausi.git;N;N;N;/Lilu/MacKernelSDK;N"
"https://github.com/Mieze/RTL8111_driver_for_OS_X.git;N;N;N;N;N"
"https://github.com/acidanthera/NVMeFix.git;N;Lilu;N;/Lilu/MacKernelSDK;N"
"https://github.com/acidanthera/VoodooPS2.git;N;Lilu;N;/Lilu/MacKernelSDK;N"
"https://github.com/acidanthera/CPUFriend.git;N;Lilu;N;/Lilu/MacKernelSDK;N"
"https://github.com/acidanthera/RTCMemoryFixup.git;N;Lilu;N;/Lilu/MacKernelSDK;N"
"#https://github.com/OpenIntelWireless/IntelBluetoothFirmware.git;N;N;N;N;N"
"#https://github.com/OpenIntelWireless/itlwm.git;N;N;N;N;N"
"#https://github.com/OpenIntelWireless/IntelBluetoothInjector.git;N;N;N;N;N"
"#https://github.com/acidanthera/VoodooInput.git;N;N;N;N;N"
"#https://github.com/VoodooI2C/VoodooI2C.git;N;N;N;N;N"
"#https://github.com/sinetek/Sinetek-rtsx.git;N;N;N;N;N"
"#com.AnV_Software.driver.AnyiSightCam;N;N;N;N;N"
)

    for KEXT in "${KEXTS[@]}"; do
    if [ $(echo "${KEXT}" | cut -c1-1) != "#" ]; then
    	KURL=$(echo "${KEXT}" | awk -F ';' '{print $1}')
    	KXID=$(echo "${KURL}" | awk -F '/' '{print $NF}' | awk -F '.' '{print $1}')
     	KDBG=$(echo "${KEXT}" | awk -F ';' '{print $2}')
       	KDEP=$(echo "${KEXT}" | awk -F ';' '{print $3}')
       	KCLSM=$(echo "${KEXT}" | awk -F ';' '{print $4}')
       	KCPSM=$(echo "${KEXT}" | awk -F ';' '{print $5}')
       	KEXIT=$(echo "${KEXT}" | awk -F ';' '{print $6}')
   	
    	cd "${BUILD_DIR}"
    	
    	if [ -d "${BUILD_DIR}/${KXID}" ]; then
            rm -rf "${BUILD_DIR}/${KXID}/"
        fi

        # Col1 : Clone KEXT
		echo "${BackSlash_N}Cloning ${KXID} repo..."
		git clone "${KURL}" >/dev/null || exit 1
        
        #Verify Project SDKROOT : must be macosx
#	    PROJ=$(find ${KXID} -name "*.xcodeproj")
#	    if [ $(grep "SDKROOT = " "${PROJ}"/project.pbxproj | grep -v "SDKROOT = macosx;" | sort -u | wc -l) -ne 0 ]
#	    then
#		    sed 's/SDKROOT = .*;$/SDKROOT = macosx;/g' "${PROJ}"/project.pbxproj > "${PROJ}"/project.pbxprojNEW
#		    mv -f "${PROJ}"/project.pbxprojNEW "${PROJ}"/project.pbxproj
#	    fi

		cd "${BUILD_DIR}/${KXID}"
        
        KXHash=$(git rev-parse origin/master|cut -c1-7)
        KXLastRel=$(grep "#### v*" Changelog.md 2/dev/null|sort -r|head -1|awk '{print $NF}')
        if [ -z ${KXLastRel} ]; then
        	 KXLastRel=$(find . -type f -name project.pbxproj -exec grep "MODULE_VERSION =" {} \; 2>/dev/null | sort -u| awk -F "=" '{print $2}'| sed -e 's/ /v/g' -e 's/;//g')
		fi

        # Col4 : Clone SubModule
     	if [ "${KCLSM}" != "N" ]; then
        	git clone "${KCLSM}" >/dev/null || exit 1
        fi

        # Col5 : Copy SubModule
     	if [ "${KCPSM}" != "N" ]; then
        	cp -r "${BUILD_DIR}${KCPSM}" ./ 2>/dev/null || exit 1
        fi

		# Col3 : Copy dependance(s)
     	if [ "${KDEP}" != "N" ]; then
			cp -r "${BUILD_DIR}/${KDEP}/build/Debug/${KDEP}.kext" "${BUILD_DIR}/${KXID}"
		fi
        
		# Col2 : Debug compilation
     	if [ "${KDBG}" != "N" -o "${Release}" = "0" ] ; then
			echo "      Compiling the latest commited (${KXHash}) Debug version of ${KXID} ${KXLastRel}..."
			builddebug
     		if [ $? -eq 0 ]; then
				echo "		${KXID} Debug ${KXLastRel}-${KXHash} Completed..."
				sleep 1
			else
		   	 echo "!!!!!!!!!!!!!!!!!!!!! ${KXID} Debug ABORTED...!!!!!!!!!!!!!!!!!!!!!"
	     		if [ "${KEXIT}" = "Y" ]; then
		    	    exit
		   		fi
			fi
		fi
		
		#Release compilation
     	if [ "${Release}" = "1" ]; then
            echo "      Compiling the latest commited (${KXHash}) Release version of ${KXID} ${KXLastRel}..."
			buildrelease
     		if [ $? -eq 0 ]; then
		    	echo "		${KXID} Release ${KXLastRel}-${KXHash} Completed..."
                sleep 1
			else
		   	 echo "!!!!!!!!!!!!!!!!!!!!! ${KXID} Release ABORTED...!!!!!!!!!!!!!!!!!!!!!"
	     		if [ "${KEXIT}" = "Y" ]; then
		    	    exit
		   		fi
			fi
		fi
	fi
  done
fi			#if [ "${With_Kexts}" = "1" ]
  
cd "${BUILD_DIR}"

if [ "$(nasm -v)" = "" ]; then
    echo "${BackSlash_N}NASM is missing!, installing..."
    prompt
    installnasm
else
    echo "${BackSlash_N}NASM Already Installed..."
fi

if [ "$(which mtoc)" == "" ]; then
    echo "${BackSlash_N}MTOC is missing!, installing..."
    prompt
    installmtoc
else
    echo "${BackSlash_N}MTOC Already Installed..."
fi

cd "${BUILD_DIR}"

opencoreclone
unset WORKSPACE
unset PACKAGES_PATH
cd "${BUILD_DIR}/OpenCorePkg"
OCHash=$(git rev-parse origin/master|cut -c1-7)
OCLastRel=$(grep "#### v*.*.*" Changelog.md 2/dev/null|sort -r|head -1|awk '{print $NF}'|sed 's/^v//g')

FINAL_DIR="${FINAL_DIR}${OCLastRel}-${OCHash}_${Kexts_With}_Kext_OCBuilder_Completed"

mkdir Binaries
cd Binaries

ln -s ../UDK/Build/OpenCorePkg/${Bld_Type_Upp}_XCODE5/${Bld_Arch_Upp} ${Bld_Type_Upp}

cd ..
opencoreudkclone
cd UDK
HASH=$(git rev-parse origin/master)

if [ -d ../Patches ]; then
  if [ ! -f patches.ready ]; then
    git config user.name ocbuild
    git config user.email ocbuild@acidanthera.local
    echo "${BackSlash_N} "
    for i in ../Patches/* ; do
      git apply --ignore-whitespace "$i" || exit 1
      git add .
      git commit -m "Applied patch $i" || exit 1
    done
    touch patches.ready
  fi
fi
ln -s .. OpenCorePkg
export NASM_PREFIX=/usr/local/bin/
source edksetup.sh --reconfig >/dev/null
make -C BaseTools -j >/dev/null || exit 1
touch UDK.ready
sleep 1


echo "${BackSlash_N}Compiling the latest commited (${OCHash}) ${Bld_Type_Upp} version of OpenCorePkg ${OCLastRel}..."
#build -a X64 or IA32 -b DEBUG or RELEASE -t XCODE5 -p OpenCorePkg/OpenCorePkg.dsc >/dev/null || exit 1
build -a ${Bld_Arch_Upp} -b ${Bld_Type_Upp} -t XCODE5 -p OpenCorePkg/OpenCorePkg.dsc >/dev/null || exit 1

cd .. >/dev/null || exit 1
opencorepackage "Binaries/${Bld_Type_Upp}" "${Bld_Type_Upp}" >/dev/null || exit 1

if [ "$BUILD_UTILITIES" = "1" ]; then
  UTILS=(
    "AppleEfiSignTool"
    "EfiResTool"
    "disklabel"
    "RsaTool"
  )

  cd Utilities || exit 1
  for util in "${UTILS[@]}"; do
    cd "$util" || exit 1
    make || exit 1
    cd - || exit 1
  done
fi

cd "${BUILD_DIR}"/OpenCorePkg/Library/OcConfigurationLib || exit 1
./CheckSchema.py OcConfigurationLib.c >/dev/null || exit 1

cd "${BUILD_DIR}"

ocbinarydataclone

if [ -d "${FINAL_DIR}" ]; then
  rm -rf "${FINAL_DIR}"/* || exit 1
fi
mkdir -p "${FINAL_DIR}" || exit 1
copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
