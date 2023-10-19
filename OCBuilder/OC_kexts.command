#!/bin/bash
if [ "${7}" = "1" ];then
    set -x
fi

KextListPrj=$(dirname $0)/OC_kexts.plist

if [ ! -f "${KextListPrj}" ]
then
    echo "${BackSlash_N}        ----> Kexts list file (${KextListPrj}) does not exist !.."; exit 1
else
    #head -$(expr $(grep -n "<key>End-of-Kexts-List</key>" "${KextListPrj}" | awk -F':' '{print $1}') - 1) "${KextListPrj}" > "${KextListWrk}"
    head -$(expr $(grep -n "<key>Kexts-List-End</key>" "${KextListPrj}" | awk -F':' '{print $1}')) "${KextListPrj}" | \
    tail -$(expr $(grep -n "<key>Kexts-List-End</key>" "${KextListPrj}" | awk -F':' '{print $1}') - $(grep -n "<key>Kexts-List-Start</key>" "${KextListPrj}" | head -1 | awk -F':' '{print $1 -1}'))  > "${KextListWrk}"
fi

KextNotUsed=0
EndOfList=0
First_Loop=1
for NumLine in $(egrep -n "\<key\>" ${KextListWrk} | awk -F':' '{print $1}'); do
     if [ ${EndOfList} = 0 ]; then
        NextLine=$(expr ${NumLine} + 1)
        Key=$(head -${NumLine} ${KextListWrk} | tail -1);Key=$(echo ${Key} | sed -e 's/^      *//g' -e 's/\<key\>//g' -e 's/\<\/key\>//g')
        Val=$(head -${NextLine} ${KextListWrk} | tail -1);Val=$(echo  ${Val} | sed -e 's/^      *//g' -e 's/\<string\>//g' -e 's/\<\/string\>//g' -e 's/\<true\/\>/YES/g' -e 's/\<false\/\>/NO/g')
        if [ "${Key}" != "Kexts-List-End" ]; then
            if [  "${Key}" != "Kexts-List-Start" -a "$(echo -e "${Key}" | cut -c 1)" != "#" ]; then
                if [ $(echo "${Val}" | sed -e 's/ /_/g'  -e 's/\<dict\>/DICTIONNARY/g') != "DICTIONNARY" ]; then
                    if [ ${KextNotUsed} = 0 ]; then
                        if [ "${Key}" = "Kext-Description" ]; then
                            Val=$(echo -e "${Val}" | sed -e 's/ /_/g' -e 's/;/_/g')
                        fi
                        echo -e "${Val};\c" >>"${KextListTxt}"
                    fi
                else
                    KextNotUsed=0
                    if [ ${First_Loop} = 0 ]; then
                        echo -e "\n\c" >>"${KextListTxt}"
                    else
                        First_Loop=0
                    fi
                fi
            else
                if [ "${Key}" = "Kexts-List-Start" -o $(echo "${Val}" | sed -e 's/ /_/g' -e 's/;/_/g' -e 's/\<dict\>/DICTIONNARY/g') = "DICTIONNARY" ]; then
                    KextNotUsed=1
                fi
            fi
        else
            EndOfList=1
        fi
     fi
done
