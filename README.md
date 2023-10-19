# OCBuilder [![Build Status](https://app.bitrise.io/app/02a5f2e98eed0a99/status.svg?token=IGZ097OMVjP9e_-cbFWIlg&branch=master)](https://app.bitrise.io/app/02a5f2e98eed0a99)
MacOS App to compile Opencore, common drivers and kexts that are used with OpenCore from source.

## This app will git clone from the following sources:
- [Lilu](https://github.com/acidanthera/Lilu.git)
- [WhateverGreen](https://github.com/acidanthera/WhateverGreen.git)
- [AppleALC](https://github.com/acidanthera/AppleALC.git)
- [VirtualSMC](https://github.com/acidanthera/VirtualSMC.git)
- [AirportBrcmFixup](https://github.com/acidanthera/AirportBrcmFixup.git)
- [IntelMausiEthernet](https://github.com/Mieze/IntelMausiEthernet.git)
- [AtherosE2200Ethernet](https://github.com/Mieze/AtherosE2200Ethernet.git)
- [RealtekRTL8111](https://github.com/Mieze/RTL8111_driver_for_OS_X.git)
- [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg.git)
- [AppleSupportPkg](https://github.com/acidanthera/AppleSupportPkg.git)
- [OpenCoreShell](https://github.com/acidanthera/OpenCoreShell.git)
and more ... if you manage manually the kexts list "OC_kexts.plist" with your pefered plist editor

## The app can be installed from unofficial [Homebrew](https://brew.sh/) cask tap via one-line command:
`brew cask install yurikoles/yurikoles/ocbuilder`

This GitHub isn't famous enough for this app to be accepted to officical Homebrew Cask repo. We need your stars :)

## This app requires the full Xcode app installed in order to compile the source. You also must agree to the User Agreement after installing Xcode app.
You can install Xcode directly from the following link
- [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12)

This app will check to see if you have all the required tools installed in order to compile these sources. If the required tools are not installed, it will install them for you, except for the full application of Xcode. It will give you an alert warning you that you do not have Xcode installed and give you the download link. This app gives you choice for selection on where you want to save the completed builds folder(for when everything has been compiled). When you click the Build button it will compile the latest commits to the sources using xcodebuild, nasm, and mtoc. Once compile has completed a OCBuilder_Completed folder with the Opencore EFI structure will be produced with all the Drivers, kexts and tools will be placed in the OCBuilder_Completed folder on the location of your selection. You may not need all of them, so make sure you remove any Drivers or Kext you do not need. "They are examples only. You have been WARNED!!!!" 

## Discord To chat with Devs and help with Opencore
- [osxx86 Discord](https://discord.gg/j3UEyJ)

## This app will create the following folder structure on the location that you have selected for Completed Builds folder.:
```
|--CompletedBuilds
|   |--Docs
|   |   |--AcpiSamples
|   |   |   |--SSDT-AWAC.dsl
|   |   |   |--SSDT-EC-USBX.dsl
|   |   |   |--SSDT-EC.dsl
|   |   |   |--SSDT-EHCx_OFF.dsl
|   |   |   |--SSDT-PLUG.dsl
|   |   |   |--SSDT-SBUS-MCHC.dsl
|   |   |--Changelog.md
|   |   |--Configuration.pdf
|   |   |--Differences.pdf
|   |   |--Sample.plist
|   |   |--SampleFull.plist
|   |--EFI
|   |   |--BOOT
|   |   |   |--BOOTx64.efi
|   |   |--OC
|   |   |   |--ACPI
|   |   |   |--Drivers
|   |   |   |   |--ApfsDriverLoader.efi
|   |   |   |   |--AppleGenericInput.efi
|   |   |   |   |--AppleUiSupport.efi
|   |   |   |   |--FwRuntimeService.efi
|   |   |   |   |--UsbKbDxe.efi
|   |   |   |   |--VBoxHfs.efi
|   |   |   |   |--VirtualSmc.efi
|   |   |   |--Kexts
|   |   |   |   |--AppleALC.kext
|   |   |   |   |--CPUFriend.kext
|   |   |   |   |--Lilu.kext
|   |   |   |   |--SMCBatteryManager.kext
|   |   |   |   |--SMCLightSensor.kext
|   |   |   |   |--SMCProcessor.kext
|   |   |   |   |--SMCSuperIO.kext
|   |   |   |   |--VirtualSMC.kext
|   |   |   |   |--WhateverGreen.kext
|   |   |   |--OpenCore.efi
|   |   |   |--Tools
|   |   |   |   |--CleanNvram.efi
|   |   |   |   |--Shell.efi
|   |   |   |   |--VerifyMsrE2.efi
|   |--Utilities
|   |   |--BootInstall
|   |   |   |--boot
|   |   |   |--boot0af
|   |   |   |--boot1f32
|   |   |   |--BootInstall.command
|   |   |   |--README.md
|   |   |--CreateVault
|   |   |   |--create_vault.sh
|   |   |   |--RsaTool
|   |   |   |--sign.command
|   |   |--LogoutHook
|   |   |   |--LogoutHook.command
|   |   |   |--nvram.mojave
|   |   |   |--README.md
|   |   |--Recovery
|   |   |   |--obtain_recovery.php
|   |   |   |--recovery_urls.txt
```

You choose to build a Release a Debug X64 IA32 or you don't want to build OpenCore.
You choose the build dest. repert.
You choose to build some kexts or not.
You choose to get std and/or err logs (in working dir, aka /private/tmp/OCBuilder_Clone).

![image](https://github.com/matxpa/ocbuilder/assets/70573409/a82ede90-f164-4b8c-82fd-298300a2141c)

You manage the kexts list (manually) if you want to build kext(s)

![image](https://github.com/matxpa/ocbuilder/assets/70573409/40202ef0-d030-4b1d-a2f8-e3cf0b830a6a)

Working dir content

![image](https://github.com/matxpa/ocbuilder/assets/70573409/09b5e242-efa9-460c-b7a5-4ff830cafe9a)

At the end you can select and save the content of that main window

![image](https://github.com/matxpa/ocbuilder/assets/70573409/64292bf7-d62d-429f-a659-a4c936a7dbe6)

And the result in the build dest. dir.

![image](https://github.com/matxpa/ocbuilder/assets/70573409/d5dcc515-d7b3-4706-8ef8-802220045022)



