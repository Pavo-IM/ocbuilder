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
FINAL_DIR="${2}/Debug_Without_Kext_OCBuilder_Completed"

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
  if [ ! -d "$2" ]; then
    git clone "$1" -b "$3" --depth=1 "$2" || exit 1
  fi
  pushd "$2" >/dev/null || exit 1
  git pull
  if [ "$2" != "UDK" ] && [ "$(unamer)" != "Windows" ]; then
    sym=$(find . -not -type d -exec file "{}" ";" | grep CRLF)
    if [ "${sym}" != "" ]; then
      echo "Repository $1 named $2 contains CRLF line endings"
      echo "$sym"
      exit 1
    fi
  fi
  git submodule update --init --recommend-shallow || exit 1
  popd >/dev/null || exit 1
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
  for util in "${UTILS[@]}"; do
    cd "$util" || exit 1
    echo "Building ${util}..."
    make clean || exit 1
    make -j "$cores" || exit 1
    #
    # FIXME: Do not build RsaTool for Win32 without OpenSSL.
    #
    if [ "$util" = "RsaTool" ] && [ "$HAS_OPENSSL_W32BUILD" != "1" ]; then
      continue
    fi

    if [ "$(which i686-w64-mingw32-gcc)" != "" ]; then
      echo "Building ${util} for Windows..."
      UDK_ARCH=Ia32 CC=i686-w64-mingw32-gcc STRIP=i686-w64-mingw32-strip DIST=Windows make clean || exit 1
      UDK_ARCH=Ia32 CC=i686-w64-mingw32-gcc STRIP=i686-w64-mingw32-strip DIST=Windows make -j "$cores" || exit 1
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
  cp Bootstrap.efi tmp/EFI/BOOT/BOOTia32.efi || exit 1
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
    "VerifyMsrE2.efi"
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
    echo "Copying OpenDuetPkg boot file from ${booter}..."
    cp "${booter}" tmp/Utilities/LegacyBoot/boot || exit 1
  else
    echo "Failed to find OpenDuetPkg at ${booter}!"
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
  echo "Cloning AUDK Repo into OpenCorePkg..."
  updaterepo "https://github.com/acidanthera/audk" UDK master || exit 1
}

opencoreclone() {
  echo "Cloning OpenCorePkg Git repo..."
  git clone -q https://github.com/acidanthera/OpenCorePkg.git
}

ocbinarydataclone () {
  echo "Cloning OcBinaryData Git repo..."
  git clone -q https://github.com/acidanthera/OcBinaryData.git
}

copyBuildProducts() {
  echo "Copying compiled products into EFI Structure folder in ${FINAL_DIR}..."
  cp "${BUILD_DIR}"/OpenCorePkg/Binaries/DEBUG/*.zip "${FINAL_DIR}/"
  cd "${FINAL_DIR}/"
  unzip *.zip  >/dev/null || exit 1
  rm -rf *.zip
  cp -r "${BUILD_DIR}"/OcBinaryData/Resources "${FINAL_DIR}"/EFI/OC/
  cp -r "${BUILD_DIR}"/OcBinaryData/Drivers/*.efi "${FINAL_DIR}"/EFI/OC/Drivers
  echo "All Done!..."
}

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

if [ ! -d "${BUILD_DIR}" ]; then
  mkdir -p "${BUILD_DIR}"
else
  rm -rf "${BUILD_DIR}/"
  mkdir -p "${BUILD_DIR}"
fi

cd "${BUILD_DIR}"

if [ "$(nasm -v)" = "" ]; then
    echo "NASM is missing!, installing..."
    prompt
    installnasm
else
    echo "NASM Already Installed..."
fi

if [ "$(which mtoc)" == "" ]; then
    echo "MTOC is missing!, installing..."
    prompt
    installmtoc
else
    echo "MTOC Already Installed..."
fi

cd "${BUILD_DIR}"

opencoreclone
unset WORKSPACE
unset PACKAGES_PATH
cd "${BUILD_DIR}/OpenCorePkg"
mkdir Binaries
cd Binaries
ln -s ../UDK/Build/OpenCorePkg/DEBUG_XCODE5/IA32 DEBUG
cd ..
opencoreudkclone
cd UDK
HASH=$(git rev-parse origin/master)

if [ -d ../Patches ]; then
  if [ ! -f patches.ready ]; then
    git config user.name ocbuild
    git config user.email ocbuild@acidanthera.local
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
echo "Compiling the latest commited Debug version of OpenCorePkg..."
build -a IA32 -b DEBUG -t XCODE5 -p OpenCorePkg/OpenCorePkg.dsc >/dev/null || exit 1
cd .. >/dev/null || exit 1
opencorepackage "Binaries/DEBUG" "DEBUG" >/dev/null || exit 1

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

if [ ! -d "${FINAL_DIR}" ]; then
  mkdir -p "${FINAL_DIR}"
  copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
else
  rm -rf "${FINAL_DIR}"/*
  copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
fi


