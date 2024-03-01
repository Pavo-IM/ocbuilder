#!/bin/bash
if [ "${7}" = "1" ];then
    set -x
fi

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

    if [ "${authPass}" == 1 ]
    then
        echo "User aborted. Exiting..."
        exit 0
    fi

    sudo () {
        echo ${authPass} | /usr/bin/sudo -S "$@"
    }
}

abort() {
  echo "ERROR: $1!"
  exit 1
}

WORK_DIR="${1}"
BUILD_DIR="${WORK_DIR}/OCBuilder_Clone"
TARGET_DIR="${2}"
FINAL_DIR="${TARGET_DIR}/OpenCore"
# ${$3} = "Debug" or "Release" or "None"
Bld_Type_Low="${3}"
Bld_Type_Upp=$(echo "${3}"| tr [:lower:] [:upper:])
# ${4} "X64" or "Ia32" or "None"
Bld_Arch_Low="${4}"
Bld_Arch_Upp=$(echo "${4}"| tr [:lower:] [:upper:])
# ${5} "0" (Without kexts), "1" (With kexts)
With_Kexts="${5}"
With_StdOut="${6}"
With_StdErr="${7}"
BackSlash_N="\\n"

if [ -d "${BUILD_DIR}" ]; then
  rm -rf "${BUILD_DIR}/" 2>/dev/null
  sleep 5
fi
mkdir -p "${BUILD_DIR}" || exit 1

#Std Out (1)
if [ "${6}" = "1" ]; then
	STD_LOG="${BUILD_DIR}/OpenCore_Build_StdOut.log"
else
	STD_LOG="/dev/null"
fi
#Std Err (2)
if [ "${7}" = "1" ]; then
	ERR_LOG="${BUILD_DIR}/OpenCore_Build_StdErr.log"
else
	ERR_LOG="/dev/null"
fi

Kexts_With="With"
if [ "${5}" = "0" ]; then
    Kexts_With="${Kexts_With}out"
fi

if [ "${Bld_Type_Low}" != "None" ]; then
	echo "${BackSlash_N}                        OpenCore build ${Bld_Type_Upp} (Arch ${Bld_Arch_Upp}) ${Kexts_With} Kexts" | tee -a "${STD_LOG}"
else
	echo "${BackSlash_N}                        Build Kexts only without OpenCore build  " | tee -a "${STD_LOG}"
fi

echo "${BackSlash_N}            Argc = $# & Argv = $@" | tee -a "${STD_LOG}"

installnasm () {
    pushd /tmp 2>>"${ERR_LOG}" || exit 1
    rm -rf nasm-mac64.zip
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/nasm-mac64.zip" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    nasmzip=$(cat nasm-mac64.zip)
    rm -rf nasm-*
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${nasmzip}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    unzip -q "${nasmzip}" nasm*/nasm nasm*/ndisasm 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    if [ -d /usr/local/bin ]; then
        sudo mv nasm*/nasm /usr/local/bin/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        sudo mv nasm*/ndisasm /usr/local/bin/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        rm -rf "${nasmzip}" nasm-* 2>>"${ERR_LOG}"
    else
        sudo mkdir -p /usr/local/bin 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        sudo mv nasm*/nasm /usr/local/bin/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        sudo mv nasm*/ndisasm /usr/local/bin/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        rm -rf "${nasmzip}" nasm-* 2>>"${ERR_LOG}"
    fi
    popd 2>>"${ERR_LOG}" || exit 1
}

installmtoc () {
    pushd /tmp 2>>"${ERR_LOG}" || exit 1
    rm -f mtoc mtoc-mac64.zip 2>>"${ERR_LOG}"
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/mtoc-mac64.zip" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    mtoczip=$(cat mtoc-mac64.zip)
    rm -rf mtoc-* 2>>"${ERR_LOG}"
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${mtoczip}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    unzip -q "${mtoczip}" mtoc 2>>"${ERR_LOG}" || exit 1
    sudo rm -f /usr/local/bin/mtoc /usr/local/bin/mtoc.NEW 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    sudo cp mtoc /usr/local/bin/mtoc 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    popd 2>>"${ERR_LOG}" || exit 1
    mtoc_path=$(which mtoc)
    mtoc_hash_user=$(shasum -a 256 "${mtoc_path}" | cut -d' ' -f1)
}

updaterepo() {
  if [ ! -d "${2}" ]; then
    git clone "${1}" -b "${3}" --depth=1 "${2}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  fi
  pushd "${2}" 2>>"${ERR_LOG}" || exit 1
  git pull --rebase --autostash
  if [ "${2}" != "UDK" ] && [ "$(unamer)" != "Windows" ]; then
    sym=$(find . -not -type d -exec file "{}" ";" | grep CRLF)
    if [ "${sym}" != "" ]; then
      echo "${BackSlash_N}Repository ${1} named ${2} contains CRLF line endings" | tee -a "${ERR_LOG}"
      echo "${sym}" | tee -a "${ERR_LOG}"
      exit 1
    fi
  fi
  git submodule update --init --recommend-shallow 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  popd 2>>"${ERR_LOG}" || exit 1
}

buildComponent() {
  xcodebuild -arch x86_64 -configuration ${bldType}  1>/dev/null 2>>"${ERR_LOG}"|| return 1
}

buildutil() {
  UTILS=(
    "AppleEfiSignTool"
    "ACPIe"
    "EfiResTool"
    "LogoutHook"
    "acdtinfo"
    "disklabel"
    "icnspack"
    "macserial"
    "ocpasswordgen"
    "ocvalidate"
    "TestBmf"
    "TestCpuFrequency"
    "TestDiskImage"
    "TestHelloWorld"
    "TestImg4"
    "TestKextInject"
    "TestMacho"
    "TestMp3"
    "TestExt4Dxe"
    "TestNtfsDxe"
    "TestPeCoff"
    "TestProcessKernel"
    "TestRsaPreprocess"
    "TestSmbios"
  )

  if [ "$HAS_OPENSSL_BUILD" = "1" ]; then
    UTILS+=("RsaTool")
  fi

  local cores
  cores=$(getconf _NPROCESSORS_ONLN)

  pushd "${selfdir}/Utilities" 2>>"${ERR_LOG}" || exit 1
  echo "${BackSlash_N}"
  for util in "${UTILS[@]}"; do
    cd "$util" 2>>"${ERR_LOG}" || exit 1
    echo " Building ${util}..."
    make clean || exit 1
    make -j "$cores" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    #
    # FIXME: Do not build RsaTool for Win32 without OpenSSL.
    #
    if [ "$util" = "RsaTool" ] && [ "$HAS_OPENSSL_W32BUILD" != "1" ]; then
      continue
    fi

    if [ "$(which i686-w64-mingw32-gcc)" != "" ]; then
      echo "${BackSlash_N}Building ${util} for Windows..."
      UDK_ARCH=${Bld_Arch_Low} CC=i686-w64-mingw32-gcc STRIP=i686-w64-mingw32-strip DIST=Windows make clean 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
      UDK_ARCH=${Bld_Arch_Low} CC=i686-w64-mingw32-gcc STRIP=i686-w64-mingw32-strip DIST=Windows make -j "$cores" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    fi
    cd - 2>>"${ERR_LOG}" || exit 1
  done
  popd 2>>"${ERR_LOG}" || exit
}

opencorepackage() {
  selfdir=$(pwd)
  pushd "$1" 2>>"${ERR_LOG}" || exit 1
  rm -rf tmp 2>>"${ERR_LOG}" || exit 1

  # "tmp/(X64 or IA32)/EFI"
  Arch_EFI_Dir="tmp/${Bld_Arch_Upp}/EFI"
  dirs=(
    "BOOT"
    "OC/ACPI"
    "OC/Drivers"
    "OC/Kexts"
    "OC/Tools"
    "OC/Resources/Audio"
    "OC/Resources/Font"
    "OC/Resources/Image"
    "OC/Resources/Label"
    )
  for dir in "${dirs[@]}"; do
    mkdir -p "${Arch_EFI_Dir}/${dir}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  done
  dirs=(
    "tmp/Docs/AcpiSamples"
    "tmp/Utilities"
    )
  for dir in "${dirs[@]}"; do
    mkdir -p "${dir}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  done

  # copy OpenCore main program.
  cp OpenCore.efi "${Arch_EFI_Dir}"/OC/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
   printf "%s" "OpenCore" > "${Arch_EFI_Dir}/OC/.contentFlavour" || exit 1
   printf "%s" "Disabled" > "${Arch_EFI_Dir}/OC/.contentVisibility" || exit 1

  # Mark binaries to be recognisable by OcBootManagementLib.
  ##bootsig="${selfdir}/Library/OcBootManagementLib/BootSignature.bin"
  ##efiOCBMs=(
    ##"Bootstrap.efi"
    ##"OpenCore.efi"
    ##)
  ##for efiOCBM in "${efiOCBMs[@]}"; do
    ##dd if="${bootsig}" \
       ##of="${efiOCBM}" seek=64 bs=1 count=64 conv=notrunc 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  ##done
  cp Bootstrap.efi "${Arch_EFI_Dir}"/BOOT/BOOT"${Bld_Arch_Low}".efi 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  printf "%s" "OpenCore" > "${Arch_EFI_Dir}/BOOT/.contentFlavour" || exit 1
  printf "%s" "Disabled" > "${Arch_EFI_Dir}/BOOT/.contentVisibility" || exit 1

  efiTools=(
      "BootKicker.efi"
      "ChipTune.efi"
      "CleanNvram.efi"
      "CsrUtil.efi"
      "GopStop.efi"
      "KeyTester.efi"
      "MmapDump.efi"
      "ResetSystem.efi"
      "RtcRw.efi"
      "TpmInfo.efi"
      "OpenControl.efi"
      "ControlMsrE2.efi"
    )
  for efiTool in "${efiTools[@]}"; do
    cp "${efiTool}" "${Arch_EFI_Dir}"/OC/Tools/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  done
  # Special case: OpenShell.efi
  cp Shell.efi "${Arch_EFI_Dir}"/OC/Tools/OpenShell.efi 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1

  efiDrivers=(
      "ArpDxe.efi"
      "AudioDxe.efi"
      "BiosVideo.efi"
      "CrScreenshotDxe.efi"
      "Dhcp4Dxe.efi"
      "DnsDxe.efi"
      "DpcDxe.efi"
      "Ext4Dxe.efi"
      "HiiDatabase.efi"
      "HttpBootDxe.efi"
      "HttpDxe.efi"
      "HttpUtilitiesDxe.efi"
      "Ip4Dxe.efi"
      "MnpDxe.efi"
      "NvmExpressDxe.efi"
      "OpenCanopy.efi"
      "OpenHfsPlus.efi"
      "OpenLinuxBoot.efi"
      "OpenNtfsDxe.efi"
      "OpenPartitionDxe.efi"
      "OpenRuntime.efi"
      "OpenUsbKbDxe.efi"
      "OpenVariableRuntimeDxe.efi"
      "Ps2KeyboardDxe.efi"
      "Ps2MouseDxe.efi"
      "ResetNvramEntry.efi"
      "SnpDxe.efi"
      "TcpDxe.efi"
      "ToggleSipEntry.efi"
      "Udp4Dxe.efi"
      "UsbMouseDxe.efi"
      "XhciDxe.efi"
    )
  for efiDriver in "${efiDrivers[@]}"; do
    cp "${efiDriver}" "${Arch_EFI_Dir}"/OC/Drivers/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  done

  docs=(
    "Configuration.pdf"
    "Differences/Differences.pdf"
    "Sample.plist"
    "SampleCustom.plist"
    )
  for doc in "${docs[@]}"; do
    cp "${selfdir}/Docs/${doc}" tmp/Docs/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  done
  cp "${selfdir}/Changelog.md" tmp/Docs/ || exit 1
  cp -r "${selfdir}/Docs/AcpiSamples/" tmp/Docs/AcpiSamples/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1

  utilScpts=(
    "LegacyBoot"
    "CreateVault"
    "FindSerialPort"
    "macrecovery"
    "kpdescribe"
    "ShimToCert"
    )
  for utilScpt in "${utilScpts[@]}"; do
	if [ -d "${utilScpt}" ]; then
	    cp -r "${selfdir}/Utilities/${utilScpt}" tmp/Utilities/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
	fi
  done
  
  buildutil 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  
  # Copy LogoutHook.
  mkdir -p "tmp/Utilities/LogoutHook" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  logoutFiles=(
    "Launchd.command"
    "Launchd.command.plist"
    "README.md"
    "nvramdump"
    )
  for file in "${logoutFiles[@]}"; do
	if [ -f "${file}" ]; then
        cp "${selfdir}/Utilities/LogoutHook/${file}" tmp/Utilities/LogoutHook/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    fi
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
    cp "${booter}" tmp/Utilities/LegacyBoot/boot 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  else
    echo "      Failed to find OpenDuetPkg at ${booter}!" | tee -a "${ERR_LOG}"
  fi
  
  utils=(
    "ACPIe"
    "acdtinfo"
    "macserial"
    "ocpasswordgen"
    "ocvalidate"
    "disklabel"
    "icnspack"
    )
  for util in "${utils[@]}"; do
    dest="tmp/Utilities/${util}"
    mkdir -p "${dest}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    bin="${selfdir}/Utilities/${util}/${util}"
    cp "${bin}" "${dest}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    if [ -f "${bin}.exe" ]; then
      cp "${bin}.exe" "${dest}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
    fi
  done

  # additional docs for macserial.
  cp "${selfdir}/Utilities/macserial/FORMAT.md" tmp/Utilities/macserial/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  cp "${selfdir}/Utilities/macserial/README.md" tmp/Utilities/macserial/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  # additional docs for ocvalidate.
  cp "${selfdir}/Utilities/ocvalidate/README.md" tmp/Utilities/ocvalidate/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1

  ocv_tool=""
  if [ -x tmp/Utilities/ocvalidate/ocvalidate ]; then
	ocv_tool=tmp/Utilities/ocvalidate/ocvalidate
  elif [ -x tmp/Utilities/ocvalidate/ocvalidate.exe ]; then
	ocv_tool=tmp/Utilities/ocvalidate/ocvalidate.exe
  fi
  if [ -x "$ocv_tool" ]; then
	"$ocv_tool" tmp/Docs/Sample.plist || abort "${BackSlash_N}Wrong Sample.plist"
	"$ocv_tool" tmp/Docs/SampleCustom.plist || abort "${BackSlash_N}Wrong SampleCustom.plist"
  fi

  pushd tmp >/dev/null || exit 1
  zip -qr -FS ../"OpenCore-${ver}-${2}.zip" ./* 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
  popd 2>>"${ERR_LOG}" || exit 1
  rm -rf tmp 2>>"${ERR_LOG}"|| exit 1
  popd 2>>"${ERR_LOG}" || exit 1
}

opencoreudkclone() {
  OCDCommit_ID=$(git ls-remote https://github.com/acidanthera/audk.git|grep "HEAD"|cut -c1-7)
  echo "${BackSlash_N}Cloning AUDK Repo (commit ${OCDCommit_ID}) into OpenCorePkg ${OCLastRel} commit ${OCHash}..." | tee -a "${STD_LOG}"
  updaterepo "https://github.com/acidanthera/audk" UDK master 1>>"${STD_LOG}" 2>>"${ERR_LOG}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
}

opencoreclone() {
  OCCommit_ID=$(git ls-remote https://github.com/acidanthera/OpenCorePkg.git|grep "HEAD"|cut -c1-7)
  echo "${BackSlash_N}Cloning OpenCorePkg Git repo (commit ${OCCommit_ID})..." | tee -a "${STD_LOG}"
  git clone -q https://github.com/acidanthera/OpenCorePkg.git 1>>"${STD_LOG}" 2>>"${ERR_LOG}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
}

ocbinarydataclone () {
  OCBCommit_ID=$(git ls-remote https://github.com/acidanthera/OcBinaryData.git|grep "HEAD"|cut -c1-7)
  echo "${BackSlash_N}Cloning OcBinaryData Git repo (commit ${OCBCommit_ID})..." | tee -a "${STD_LOG}"
  git clone -q https://github.com/acidanthera/OcBinaryData.git 1>>"${STD_LOG}" 2>>"${ERR_LOG}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
}

copyBuildProducts() {

    cd "${FINAL_DIR}/"

    #Release=9 ie. No OC build
    if [ "${Release}" != "9" ]; then
        cp "${BUILD_DIR}"/OpenCorePkg/Binaries/${Bld_Type_Upp}/*.zip "${FINAL_DIR}/" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        unzip *.zip  1>>"${STD_LOG}" 2>>"${ERR_LOG}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        rm -rf *.zip 2>>"${ERR_LOG}"
        cp -r "${BUILD_DIR}"/OcBinaryData/Resources "${FINAL_DIR}/${Bld_Arch_Upp}/"/EFI/OC/ 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
        cp -r "${BUILD_DIR}"/OcBinaryData/Drivers/*.efi "${FINAL_DIR}/${Bld_Arch_Upp}/"/EFI/OC/Drivers 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
    fi                                              #if [ "${Release}" != "9" ];

    #Kext(s) copy
    if [ "${With_Kexts}" = "1" ]; then
        if [ ! -d "${FINAL_DIR}"/KextsPKG ]; then
            mkdir -p "${FINAL_DIR}"/KextsPKG 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        fi
        for KEXT in $(cat "${KextListTxt}" | sed -e '/^$/d' -e 's/;$//g' );do
            if [ $(echo "${KEXT}" | cut -c1-1) != "#" ]; then
                KXID=$(echo "${KEXT}" | awk -F ';' '{print $1}')
                KURL=$(echo "${KEXT}" | awk -F ';' '{print $3}')
                KXBD=$(echo "${KEXT}" | awk -F ';' '{print $4}')
                
                if [ "${Release}" != "9" ];then
                    for KXKX in $(find "${BUILD_DIR}/${KXBD}" -name "*.kext" | grep "${Bld_Type_Low}" | egrep -v "/PlugIns/|/firmwares/|/package/");  do
                        FINAL_KXKX=$(basename "${KXKX}")
                        cp -rf "${KXKX}" "${FINAL_DIR}/${Bld_Arch_Upp}"/EFI/OC/Kexts/"${FINAL_KXKX}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
                    done
                    #Kext(s) Package(s) copy
                    for KXZIP in $(find "${BUILD_DIR}/${KXBD}" -name "*-*-*.zip"  | grep "${Bld_Type_Low}" | egrep -v "/PlugIns/|/firmwares/|/package/");  do
                        FINAL_KXZIP=$(basename "${KXZIP}")
                        cp -rf "${KXZIP}" "${FINAL_DIR}"/KextsPKG/"${FINAL_KXZIP}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
                    done
                else                            #"${Release}" = "9"
                    for bldType in "${bldTypeArray[@]}"; do
                        for KXZIP in $(find "${BUILD_DIR}/${KXBD}" -name "*-*-*.zip"  | grep "${bldType}" | egrep -v "/PlugIns/|/firmwares/|/package/");  do
#                            FINAL_KXZIP=$(basename "${KXZIP}")
 #                           cp -rf "${KXZIP}" "${FINAL_DIR}"/KextsPKG/"${FINAL_KXZIP}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
                            cp -rf "${KXZIP}" "${FINAL_DIR}"/KextsPKG 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
                        done
                    done
                fi                                 #if [ "${Release}" != "9" ]
                
            fi
        done
    fi                                                          #if [ "${With_Kexts}" = "1" ]
}

#Kext(s) list
creatKextsList() {
  echo "      "
  echo "----> Kexts list decode start !..." | tee -a "${STD_LOG}"
  KextListWrk="${BUILD_DIR}/OC_KEXT.plist"   #Work OC_KEXT.plist
  KextListTxt="${BUILD_DIR}/OC_KEXT.txt"   #Work OC_KEXT.text
  rm -f "${KextListWrk}" "${KextListTxt}" 2>/dev/null

  source $(dirname $0)/OC_kexts.command 2>>"${ERR_LOG}"

  if [ -f "${KextListTxt}" ]
	then echo "----> Kexts list decode done !..." | tee -a "${STD_LOG}"
  fi
}


#MAIN
if [ "${Bld_Type_Low}" = "None" ]; then
	Release="9"									#ie. No OC build
else
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
fi

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

echo "${BackSlash_N}Build   Directory is : ${BUILD_DIR}" | tee -a "${STD_LOG}"
echo "Target Directory is : ${TARGET_DIR}" | tee -a "${STD_LOG}"
cd "${BUILD_DIR}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"

if [ "${With_Kexts}" = "1" ]; then
	#KEXTS : Col1= Kext Name;Col2= Kext Description;Col3=Kext(s) repo;Col4=Debug needed too;Col5=Dependance(s);Col6=Clone SubModule;Col7=Copy SubModule;Col8=Exit on Compil Abort
	creatKextsList

    if [ -f "${KextListTxt}" ]
    then 
        for KEXT in $(cat "${KextListTxt}" | sed -e '/^$/d' -e 's/;$//g' );do
            KXID=$(echo "${KEXT}" | awk -F ';' '{print $1}')
	        KURL=$(echo "${KEXT}" | awk -F ';' '{print $3}')
            KXBD=$(echo "${KEXT}" | awk -F ';' '{print $4}')
            KDBG=$(echo "${KEXT}" | awk -F ';' '{print $5}')
            KDEP=$(echo "${KEXT}" | awk -F ';' '{print $6}')
            KCLSM=$(echo "${KEXT}" | awk -F ';' '{print $7}')
            KCPSM=$(echo "${KEXT}" | awk -F ';' '{print $8}')
            KEXIT=$(echo "${KEXT}" | awk -F ';' '{print $9}')
   	
            cd "${BUILD_DIR}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
    	
            if [ -d "${BUILD_DIR}/${KXBD}" ]; then
                rm -rf "${BUILD_DIR}/${KXBD}/" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
            fi

            # Col1 : Clone KEXT
            echo "${BackSlash_N}Cloning ${KXID} repo..."
            git clone "${KURL}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
        
            cd "${BUILD_DIR}/${KXBD}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
        
            KXHash=$(git rev-parse origin/master|cut -c1-7)
            KXHashDate=$(git log -1 --format=%ci origin/master|cut -c 1-10|sed 's/-//g')
            KXLastRel=$(git describe --tags $(git rev-list --tags --max-count=1))

            # Col6 : Clone SubModule
            if [ "${KCLSM}" != "NO" ]; then
                echo "          --> Cloning ${KCLSM} repo..."
                git clone "${KCLSM}" >/dev/null 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
            fi

            # Col7 : Copy SubModule
            if [ "${KCPSM}" != "NO" ]; then
                echo "          --> Link ${KCPSM} repo..."
                ln -s "${BUILD_DIR}${KCPSM}" ./ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
            fi

            # Col5 : Copy dependance(s)
            if [ "${KDEP}" != "NO" ]; then
                echo "          --> Link Dep. ${KDEP} ..."
                 ln -s "${BUILD_DIR}/${KDEP}/build/Debug/${KDEP}.kext" ./ 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
            fi
            
            unset FINAL_KXKX        
            unset FINAL_KXZIP        
            unset bldTypeArray 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
            # Col4 : Debug compilation  (don't mix next code lines with # Col4 : Release compilation code (above) it's not an interchangeable condition)
            if [ "${KDBG}" != "NO" -o "${Release}" = "0" ] ; then
                bldTypeArray=("Debug")
            fi
            # Debug AND/OR Release compilation
            if [ "${Release}" = "1" ]; then
                if [ "${KDBG}" != "NO" ] ; then
                    bldTypeArray=("Debug" "Release")
                else
                    bldTypeArray=("Release")
                fi
            fi
             #Only Kexts build without OpenCore build
             if [ "${Release}" = "9" ] ; then
                    bldTypeArray=("Debug" "Release")
            fi
            
            for bldType in "${bldTypeArray[@]}"; do
			    echo "      Compiling the latest (${KXHashDate}) commited (${KXHash}) ${bldType} version of ${KXID} v${KXLastRel}..." | tee -a "${STD_LOG}"
			    buildComponent
     		   if [ $? -eq 0 ]; then
                    echo "		${KXID} ${bldType}  v${KXLastRel}-${KXHashDate}-${KXHash} Completed..." | tee -a "${STD_LOG}"; sleep 1
			   else
                    echo "!!!!!!!!!!!!!!!!!!!!! ${KXID} ${bldType}  ABORTED...!!!!!!!!!!!!!!!!!!!!!" | tee -a "${ERR_LOG}"
                    if [ "${KEXIT}" = "YES" ]; then
                        exit
                    fi
                fi
                sleep 2
                ##Rename or create ".zip" wth KextName-Last Version-Last Version Date-Last Version Commit.zip
                zipCount=0
                for KXZIP in $(find "${BUILD_DIR}/${KXBD}" -name "*-*-*.zip"  | grep "${Bld_Type_Low}" | egrep -v "/PlugIns/|/firmwares/|/package/");  do
                    zipCount=1
#                    FINAL_ZIP=$(echo "${KXZIP}" | sed 's/"-${Bld_Type_Upp}\.zip/-${KXHashDate}-${KXHash}-${Bld_Type_Upp}"\.zip/g')
                    FINAL_KXZIP=$(echo "${KXZIP}" | sed 's/'${Bld_Type_Upp}'\.zip//g')
                    FINAL_KXZIP=$(echo "${FINAL_KXZIP}${KXHashDate}-${KXHash}-${Bld_Type_Upp}.zip")
                    echo "          --> Rename $(basename ${KXZIP}) $(basename ${FINAL_KXZIP})" | tee -a "${STD_LOG}"
                    mv -f "${KXZIP}" "${FINAL_KXZIP}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
                done
                if [ ${zipCount} = 0 ]; then
                    pwdDir=$(pwd)
                    for KXKX in $(find "${BUILD_DIR}/${KXBD}" -name "*.kext" | grep "${Bld_Type_Low}" | egrep -v "/PlugIns/|/firmwares/|/package/");  do
#                        FINAL_KX=$(echo "${KXKX}" | sed 's/\.kext/"-v${KXLastRel}-${KXHashDate}-${KXHash}-${Bld_Type_Upp}"\.zip/g')
                        zipDir=$(dirname "${KXKX}")
                        zipkext=$(basename "${KXKX}")
                        FINAL_KXKX=$(echo "${zipkext}" | sed 's/\.kext//g')
                        FINAL_KXKX=$(echo "${FINAL_KXKX}-v${KXLastRel}-${KXHashDate}-${KXHash}-${Bld_Type_Upp}.zip")
                        echo "          --> Zip ${zipkext} in ${FINAL_KXKX}" | tee -a "${STD_LOG}"
                        cd "${zipDir}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
                        zip -q "${FINAL_KXKX}" "${zipkext}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
                        cd "${pwdDir}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
                    done
                fi
            done
        done
    fi          #if [ -f "${KextListTxt}" ] Kexts list file
fi			#if [ "${With_Kexts}" = "1" ] Build Kexts
  
cd "${BUILD_DIR}"

#Release=9 ie. No OC build
if [ "${Release}" != "9" ]; then

	if [ "$(nasm -v)" = "" ]; then
		echo "${BackSlash_N}NASM is missing!, installing..." | tee -a "${STD_LOG}"
		prompt
		installnasm
	else
		echo "${BackSlash_N}NASM Already Installed..." | tee -a "${STD_LOG}"
	fi

	if [ "$(which mtoc)" == "" ]; then
		echo "${BackSlash_N}MTOC is missing!, installing..." | tee -a "${STD_LOG}"
		prompt
		installmtoc
	else
		echo "${BackSlash_N}MTOC Already Installed..." | tee -a "${STD_LOG}"
	fi

	cd "${BUILD_DIR}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"

	opencoreclone 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
	unset WORKSPACE
	unset PACKAGES_PATH
	cd "${BUILD_DIR}/OpenCorePkg" 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
	OCHash=$(git rev-parse origin/master|cut -c1-7)
	OCLastRel=$(git describe --tags $(git rev-list --tags --max-count=1))
	OCHashDate=$(git log -1 --format=%ci origin/master|cut -c 1-10|sed 's/-//g')
	#FINAL_DIR="${FINAL_DIR}-${OCLastRel}-${OCHashDate}-${OCHash}-${Bld_Type_Upp}_${Kexts_With}_Kexts"

	mkdir Binaries 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
	cd Binaries 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1

	#ln -s ../UDK/Build/OpenCorePkg/(DEBUG or RELEASE)_XCODE5/(X64 or IA32)  (DEBUG or RELEASE)
	ln -s ../UDK/Build/OpenCorePkg/${Bld_Type_Upp}_XCODE5/${Bld_Arch_Upp} ${Bld_Type_Upp} 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1

	cd ..
	opencoreudkclone 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
	cd UDK
	HASH=$(git rev-parse origin/master) 1>>"${STD_LOG}" 2>>"${ERR_LOG}"

	if [ -d ../Patches ]; then
		if [ ! -f patches.ready ]; then
			git config user.name ocbuild
			git config user.email ocbuild@acidanthera.local
			echo "${BackSlash_N} "
			for i in ../Patches/* ; do
				git apply --ignore-whitespace "$i" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
				git add .
				git commit -m "Applied patch $i" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
			done
			touch patches.ready 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
		fi
	fi
	#ln -s .. OpenCorePkg 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
	export NASM_PREFIX=/usr/local/bin/
	source edksetup.sh --reconfig >/dev/null
	make -C BaseTools -j >/dev/null 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
	touch UDK.ready 1>>"${STD_LOG}" 2>>"${ERR_LOG}"
	sleep 1
	echo "${BackSlash_N}Compiling the latest  (${OCHashDate}) commited (${OCHash}) ${Bld_Type_Upp} version of OpenCorePkg ${OCLastRel}..." | tee -a "${STD_LOG}"
	#build -a X64 or IA32 -b DEBUG or RELEASE -t XCODE5 -p OpenCorePkg/OpenCorePkg.dsc >/dev/null || exit 1
	build -a ${Bld_Arch_Upp} -b ${Bld_Type_Upp} -t XCODE5 -p OpenCorePkg/OpenCorePkg.dsc 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1


	cd .. 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
	opencorepackage "Binaries/${Bld_Type_Upp}" "${Bld_Type_Upp}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1

	if [ "$BUILD_UTILITIES" = "1" ]; then
		UTILS=(
		"AppleEfiSignTool"
		"EfiResTool"
		"disklabel"
		"RsaTool"
		)

	cd Utilities 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
	for util in "${UTILS[@]}"; do
		cd "$util" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
		make || exit 1
		cd - || exit 1
	done
	fi

	cd "${BUILD_DIR}"/OpenCorePkg/Library/OcConfigurationLib 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
	./CheckSchema.py OcConfigurationLib.c >/dev/null 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || abort "${BackSlash_N}Wrong OcConfigurationLib.c"

	cd "${BUILD_DIR}"
	ocbinarydataclone 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
	FINAL_DIR="${FINAL_DIR}-${OCLastRel}-${OCHashDate}-${OCHash}-${Bld_Type_Upp}"
	echo "${BackSlash_N}Copying compiled products into EFI Structure folder in ${FINAL_DIR}..." | tee -a "${STD_LOG}"
else
    horoDate=$(date -I minutes | sed -e 's/-//g' -e 's/T/-/g' | awk -F'+' '{print $1}'  | sed 's/:/h/g' )
    FINAL_DIR="${TARGET_DIR}/0 OCBuilder_Kext-${horoDate}"
	echo "${BackSlash_N}Copying compiled Kexts into ${FINAL_DIR}/KextsPKG..." | tee -a "${STD_LOG}"
fi		#if [ "${Release}" != "9" ]

if [ -d "${FINAL_DIR}" ]; then
    rm -rf "${FINAL_DIR}"/* 1>>"${STD_LOG}" 2>>"${ERR_LOG}" 
else
    mkdir -p "${FINAL_DIR}" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1
fi

copyBuildProducts 1>>"${STD_LOG}" 2>>"${ERR_LOG}" || exit 1

sleep 5
echo "${BackSlash_N}All Done !...                   That's all Folks !" | tee -a "${STD_LOG}"
#echo "${BackSlash_N}                  This is the END... my only friend... the END !..."
#  rm -rf "${BUILD_DIR}/" 1>>"${STD_LOG}" 2>>"${ERR_LOG}" 

