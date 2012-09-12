#!/bin/bash

# provide a filename to decrypt in argument

# Requirements:
# We expect escrow material on USBSECURE1

FILENAME=$1
if [ "$FILENAME" == "" ]
then
    echo "Error please give a filename to recover in argument"
    echo "Abort."
    exit 1
fi
if [ ! -e "$FILENAME" ]
then
    echo "Error $(pwd)/$FILENAME not found"
    echo "Abort."
    exit 1
fi


# Mount points of the USB sticks:
USBPUBLIC=$(pwd)/USBPUBLIC
if [ ! -d "$USBPUBLIC" ]
then
    echo "Error $USBPUBLIC not found"
    echo "Abort."
    exit 1
fi
USBSECURE1=$(pwd)/USBSECURE1
if [ ! -d "$USBSECURE1" ]
then
    echo "Error $USBSECURE1 not found"
    echo "Abort."
    exit 1
fi

echo "Scanning for escrow keys..."
if ls -1 $USBSECURE1/*/BCT-escrow-secretkey.gpg | grep -q " "
then
    echo "Warning, spaces in path not supported in:"
    ls -1 $USBSECURE1/*/BCT-escrow-secretkey.gpg | grep " "
    echo "Please fix."
    echo "Abort."
    exit 1
fi
i=0
for file in $(ls -1 $USBSECURE1/*/BCT-escrow-secretkey.gpg|sort -r -n)
do
    i=$(($i+1))
    ESCROWSECKEYS[$i]=$file
    # Escrow key name
    GPG_KEYS[$i]=$(basename $(dirname $file))
done
if [ ${#ESCROWSECKEYS[@]} -eq 0 ]
then
    echo "Error, no key found"
    echo "Abort."
    exit 1
fi

# Common gpg arguments
GPG_ARGS_NOBATCH="--no-default-recipient --trust-model always"
GPG_ARGS="$GPG_ARGS_NOBATCH --batch"
export GNUPGHOME=$(pwd)/bct_gnupg
mkdir -p $GNUPGHOME
chmod 700 $GNUPGHOME


for GPG_KEY in ${GPG_KEYS[@]}
do
    echo "--------------------------------------------------------------------"
    echo -e "\n\nImporting Escrow key $GPG_KEY:"
    GPG_KEY_DIR_SEC1=$USBSECURE1/$GPG_KEY
    gpg $GPG_ARGS --import $GPG_KEY_DIR_SEC1/BCT-escrow-secretkey.gpg
done

echo "--------------------------------------------------------------------"
echo -e "\n\nTesting $FILENAME:"

KEYS=$(gpg $GPG_ARGS --decrypt $FILENAME 2>&1 | awk '/encrypted with/{getline;print}'|sed 's/"//g')
if [ "$KEYS" == "" ]
then
    echo "Could not find which keys were used to encrypt this file, is it really a gpg file?"
    echo "Abort."
    exit 1
fi

GPG_KEY=""
for KEY in $KEYS
do
    if [[ " ${GPG_KEYS[@]} " =~ " $KEY " ]]
    then
        echo "Using escrow key \"$KEY\""
        GPG_KEY=$KEY
        break
    fi
done
if [ "$GPG_KEY" == "" ]
then
    echo "Could not find which escrow key was used to encrypt this file!"
    echo "Abort."
    exit 1
fi

# Members able to use this escrow key
j=0
globaltimestamp=''
globalBCT_MIN=''
globalBCT_TOTAL=''
for member in $(ls -1 $USBSECURE1/$GPG_KEY/*-sharedsecret-N*-T*-TS*.gpg)
do
    j=$(($j+1))
    member=$(basename $member)
    BCT_MIN=${member%%-TS*.gpg}
    BCT_MIN=${BCT_MIN##*-sharedsecret-N*-T}
    if [ "$globalBCT_MIN" == "" ]
    then
        globalBCT_MIN=$BCT_MIN
    elif [ "$globalBCT_MIN" != "$BCT_MIN" ]
    then
        echo "Error. There are incoherences in threshold values of the shares:"
        ls -1 $USBSECURE1/$GPG_KEY/*-sharedsecret-N*-T*-TS*.gpg
        echo "Abort."
        exit 1
    fi
    BCT_TOTAL=${member%%-T*TS*.gpg}
    BCT_TOTAL=${BCT_TOTAL##*-sharedsecret-N}
    if [ "$globalBCT_TOTAL" == "" ]
    then
        globalBCT_TOTAL=$BCT_TOTAL
    elif [ "$globalBCT_TOTAL" != "$BCT_TOTAL" ]
    then
        echo "Error. There are incoherences in member size values of the shares:"
        ls -1 $USBSECURE1/$GPG_KEY/*-sharedsecret-N*-T*-TS*.gpg
        echo "Abort."
        exit 1
    fi
    timestamp=${member%%.gpg}
    timestamp=${timestamp##*-sharedsecret-N*-T*-TS}
    if [ "$globaltimestamp" == "" ]
    then
        globaltimestamp=$timestamp
    elif [ "$globaltimestamp" != "$timestamp" ]
    then
        echo "Error. There exist shared secrets from different dates:"
        ls -1 $USBSECURE1/$GPG_KEY/*-sharedsecret-N*-T*-TS*.gpg
        echo "Abort."
        exit 1
    fi
    member=${member%%-sharedsecret-N*-T*-TS*.gpg}
    BCT_MEMBERS[$j]=${member##BCT-}
done
BCT_TOTAL=${#BCT_MEMBERS[@]}
if [ "$globalBCT_TOTAL" != "$BCT_TOTAL" ]
then
    echo "Error. There are incoherences in member size values of the shares:"
    echo "Files indicate there are $globalBCT_TOTAL members but we found $BCT_TOTAL files."
    ls -1 $USBSECURE1/$GPG_KEY/*-sharedsecret-N*-T*-TS*.gpg
    echo "Abort."
    exit 1
fi

echo -e -n "\n\nBCT members able to recover $FILENAME are: "
echo "${BCT_MEMBERS[@]}"

i=0
for member in ${BCT_MEMBERS[@]}
do
    read -p "Is $member present? [y/n]"
    if [ "$REPLY" == "y" ]
    then
        i=$(($i+1))
        BCT_MEMBERS_PRESENT[$i]=$member
    fi
done
if [ ${#BCT_MEMBERS_PRESENT[@]} -lt $BCT_MIN ]
then
    echo "Only ${#BCT_MEMBERS_PRESENT[@]} BCT members present, minimum required is $BCT_MIN"
    echo "Abort."
    exit 1
fi

i=0
for member in $(echo ${BCT_MEMBERS_PRESENT[@]}|sed 's/ /\n/g'|sort --random-sort)
do
    while :
    do
        echo "--------------------------------------------------------------------"
        echo -e "\n\nRecovering shared secret of $member:"
        share=$(gpg $GPG_ARGS_NOBATCH --decrypt --no-mdc-warning $USBSECURE1/$GPG_KEY/BCT-$member-sharedsecret-N${BCT_TOTAL}-T${BCT_MIN}-TS${timestamp}.gpg)
        if [ $? -eq 0 ]
        then
            # share successfully recovered
            i=$(($i+1))
            BCT_SHARES[$i]=$share
            break
        else
            read -p "Do you want to try again? [y/n]: "
            if [ "$REPLY" != "y" ]
            then
                break
            fi
        fi
    done
    if [ $i -eq $BCT_MIN ]
    then
        break
    fi
done
if [ ${#BCT_SHARES[@]} -ne $BCT_MIN ]
then
    echo "Recovered only ${#BCT_SHARES[@]} shares, minimum required is $BCT_MIN"
    echo "Abort."
    exit 1
fi

echo "--------------------------------------------------------------------"
echo -e "\n\nRecovering escrow passphrase:"
echo "Recovered ${#BCT_SHARES[@]} shares"
passphrase=$(echo ${BCT_SHARES[@]} |\
             sed 's/ /\n/g' |\
             ssss-combine -t $BCT_MIN 2>&1 |\
             awk '/^Resulting secret:/{print $3}')

echo "--------------------------------------------------------------------"
echo -e "\n\nDecrypting $FILENAME"
FILENAME_DEC=$(basename $FILENAME)
FILENAME_DEC=${FILENAME_DEC%%.gpg}
gpg $GPG_ARGS --passphrase $passphrase --output "$FILENAME_DEC" "$FILENAME"
echo "$FILENAME is now decrypted in"
echo "$(pwd)/$FILENAME_DEC"


echo "--------------------------------------------------------------------"
echo -e "\n\nImporting recipients GPG public keys:"
j=0
for recipient in $(ls -1 $USBPUBLIC/recipients/*.gpg)
do
    j=$(($j+1))
    RECIPIENTS[$j]=$(basename ${recipient%%.gpg})
done
RECIPIENTS_TOTAL=${#RECIPIENTS[@]}
for ((i=1;i<=$RECIPIENTS_TOTAL;i++))
do
    gpg $GPG_ARGS --import $USBPUBLIC/recipients/${RECIPIENTS[$i]}.gpg
done

echo "--------------------------------------------------------------------"
echo -e "\n\nExporting $FILENAME_DEC"

if [ $RECIPIENTS_TOTAL -eq 0 ]
then
    echo "No recipient found for re-encryption"
    read -p "Are you sure you want to copy $FILENAME_DEC in clear on USBPUBLIC?? [y/n]:"
    if [ "$REPLY" == "y" ]
    then
        cp $FILENAME_DEC $USBPUBLIC
        echo "Done."
        exit 0
    else
        echo "$FILENAME_DEC left in $(pwd). Bye."
        exit 0
    fi
fi

RECIPIENTS_TO_USE=""
for ((i=1;i<=$RECIPIENTS_TOTAL;i++))
do
    read -p "Do you want ${RECIPIENTS[$i]} to be recipient of $FILENAME_DEC ? [y/n]:"
    if [ "$REPLY" == "y" ]
    then
        RECIPIENTS_TO_USE="$RECIPIENTS_TO_USE --recipient ${RECIPIENTS[$i]}"
    fi
done

if [ "$RECIPIENTS_TO_USE" == "" ]
then
    echo "Error no recipient selected."
    echo "$FILENAME_DEC left in $(pwd). Bye."
    exit 1
fi


gpg $GPG_ARGS --encrypt --armor $RECIPIENTS_TO_USE --output $FILENAME_DEC.exported.gpg $FILENAME_DEC
cp $FILENAME_DEC.exported.gpg $USBPUBLIC/
