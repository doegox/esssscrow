#!/bin/bash

# Requirements:
# We expect escrow material on USBSECURE1
# USBSECURE2 is kept as a backup in case sth goes wrong
# We expect public keys of *NEW* BCT members are available in files
# named <BCT_MEMBER>.gpg on USBPUBLIC under directory "members"
# so e.g.: USBPUBLIC/members/mrnobody.gpg

# Minimum number of members to do escrow recovering (new shares):
BCT_MIN=2


if ls -1 *.gpg >/dev/null 2>&1
then
    echo "There are still files of a previous run in the current directory."
    echo "Please delete them if you really want to generate new shares."
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

BCT_MEMBERS_DIR_PUB=$USBPUBLIC/members
BCT_MEMBERS_DIR_SEC1=$USBSECURE1/members

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

echo "Found the following escrow keys:"
for GPG_KEY in ${GPG_KEYS[@]}
do
    echo "* $GPG_KEY"
done
echo "--------------------------------------------------------------------"
echo -e "\n\nSelecting escrow key:"
GPG_KEY=""
for KEY in ${GPG_KEYS[@]}
do
    read -p "Use $KEY? [y/n]"
    if [ "$REPLY" == "y" ]
    then
        GPG_KEY=$KEY
        break
    fi
done

if [ "$GPG_KEY" == "" ]
then
    echo "Could not find which escrow key you want to work on!"
    echo "Abort."
    exit 1
fi

# Common gpg arguments
GPG_ARGS_NOBATCH="--no-default-recipient --trust-model always"
GPG_ARGS="$GPG_ARGS_NOBATCH --batch"
export GNUPGHOME=$(pwd)/bct_gnupg
mkdir -p $GNUPGHOME
chmod 700 $GNUPGHOME


echo "--------------------------------------------------------------------"
echo -e "\n\nFinding new BCT members GPG public keys"

i=0
for member in $(ls -1 $BCT_MEMBERS_DIR_PUB/*gpg)
do
    i=$(($i+1))
    member=$(basename $member)
    BCT_MEMBERS[$i]=${member%%.gpg}
done

BCT_TOTAL=${#BCT_MEMBERS[@]}
for ((i=1;i<=$BCT_TOTAL;i++))
do
    if [ ! -e $BCT_MEMBERS_DIR_PUB/${BCT_MEMBERS[$i]}.gpg ]
    then
        echo "${BCT_MEMBERS[$i]}.gpg not found on USBPUBLIC"
        echo "Abort!"
        exit 1
    fi
done
if [ $BCT_TOTAL -lt $BCT_MIN ]
then
    echo "Error found only $BCT_TOTAL BCT members, minimum is $BCT_MIN"
    echo "Abort."
    exit 1
fi


echo "--------------------------------------------------------------------"
echo -e "\n\nParameters:"
echo " * GPG escrow key named \"$GPG_KEY\""
echo " * $BCT_TOTAL BCT members in the new composition"
echo " * Need collusion of at least $BCT_MIN members to use escrow key passphrase"
read -p "Is it correct? [y/n]: "
if [ "$REPLY" != "y" ]
then
    echo "Quitting..."
    exit 1
fi


echo "--------------------------------------------------------------------"
echo -e "\n\nImporting BCT members GPG public keys:"
for ((i=1;i<=$BCT_TOTAL;i++))
do
    gpg $GPG_ARGS --import $BCT_MEMBERS_DIR_PUB/${BCT_MEMBERS[$i]}.gpg
done

echo "--------------------------------------------------------------------"
echo -e "\n\nTesting BCT public keys:"
RECIPIENTS=""
for ((i=1;i<=$BCT_TOTAL;i++))
do
    RECIPIENTS="$RECIPIENTS  --recipient ${BCT_MEMBERS[$i]}"
done
n=0
for i in $(echo "1234" |\
           gpg $GPG_ARGS --encrypt --armor $RECIPIENTS |\
           pgpdump |\
           grep "Key ID" |\
           sed 's/.*0x//')
do
    gpg $GPG_ARGS --list-key $i | awk '
                             BEGIN {
                                 u=0
                             }
                             /^uid/ && u==0 {
                                 print
                                 u=1
                                 next
                             }
                             /^pub/ {
                                 u=0
                             }'
    n=$(($n+1))
done
if [ $n -ne $BCT_TOTAL ]
then
    echo ">>>>> WARNING: expected $BCT_TOTAL members and got $n when testing GPG encryption <<<<<"
fi
read -p "Is it the correct *NEW* BCT members list? [y/n]: "
if [ "$REPLY" != "y" ]
then
    echo "Quitting..."
    exit 1
fi


echo "--------------------------------------------------------------------"
echo -e "\n\nImporting Escrow key $GPG_KEY:"
GPG_KEY_DIR_PUB=$USBPUBLIC/$GPG_KEY
GPG_KEY_DIR_SEC1=$USBSECURE1/$GPG_KEY
gpg $GPG_ARGS --import $GPG_KEY_DIR_SEC1/BCT-escrow-secretkey.gpg

# Members able to use this escrow key
j=0
globaltimestamp=''
globalOLDBCT_MIN=''
globalOLDBCT_TOTAL=''
for member in $(ls -1 $USBSECURE1/$GPG_KEY/*-sharedsecret-N*-T*-TS*.gpg)
do
    j=$(($j+1))
    member=$(basename $member)
    OLDBCT_MIN=${member%%-TS*.gpg}
    OLDBCT_MIN=${OLDBCT_MIN##*-sharedsecret-N*-T}
    if [ "$globalOLDBCT_MIN" == "" ]
    then
        globalOLDBCT_MIN=$OLDBCT_MIN
    elif [ "$globalOLDBCT_MIN" != "$OLDBCT_MIN" ]
    then
        echo "Error. There are incoherences in threshold values of the shares:"
        ls -1 $USBSECURE1/$GPG_KEY/*-sharedsecret-N*-T*-TS*.gpg
        echo "Abort."
        exit 1
    fi
    OLDBCT_TOTAL=${member%%-T*TS*.gpg}
    OLDBCT_TOTAL=${OLDBCT_TOTAL##*-sharedsecret-N}
    if [ "$globalOLDBCT_TOTAL" == "" ]
    then
        globalOLDBCT_TOTAL=$OLDBCT_TOTAL
    elif [ "$globalOLDBCT_TOTAL" != "$OLDBCT_TOTAL" ]
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
    OLDBCT_MEMBERS[$j]=${member##BCT-}
done
OLDBCT_TOTAL=${#OLDBCT_MEMBERS[@]}
if [ "$globalOLDBCT_TOTAL" != "$OLDBCT_TOTAL" ]
then
    echo "Error. There are incoherences in member size values of the shares:"
    echo "Files indicate there are $globalOLDBCT_TOTAL members but we found $OLDBCT_TOTAL files."
    ls -1 $USBSECURE1/$GPG_KEY/*-sharedsecret-N*-T*-TS*.gpg
    echo "Abort."
    exit 1
fi

echo -e -n "\n\nBCT members able to use $GPG_KEY are: "
echo "${OLDBCT_MEMBERS[@]}"

i=0
for member in ${OLDBCT_MEMBERS[@]}
do
    read -p "Is $member present? [y/n]"
    if [ "$REPLY" == "y" ]
    then
        i=$(($i+1))
        OLDBCT_MEMBERS_PRESENT[$i]=$member
    fi
done
if [ ${#OLDBCT_MEMBERS_PRESENT[@]} -lt $OLDBCT_MIN ]
then
    echo "Only ${#OLDBCT_MEMBERS_PRESENT[@]} old BCT members present, minimum required is $OLDBCT_MIN"
    echo "Abort."
    exit 1
fi

i=0
for member in $(echo ${OLDBCT_MEMBERS_PRESENT[@]}|sed 's/ /\n/g'|sort --random-sort)
do
    while :
    do
        echo "--------------------------------------------------------------------"
        echo -e "\n\nRecovering shared secret of $member:"
        share=$(gpg $GPG_ARGS_NOBATCH --decrypt --no-mdc-warning $USBSECURE1/$GPG_KEY/BCT-$member-sharedsecret-N${OLDBCT_TOTAL}-T${OLDBCT_MIN}-TS${timestamp}.gpg)
        if [ $? -eq 0 ]
        then
            # share successfully recovered
            i=$(($i+1))
            OLDBCT_SHARES[$i]=$share
            break
        else
            read -p "Do you want to try again? [y/n]: "
            if [ "$REPLY" != "y" ]
            then
                break
            fi
        fi
    done
    if [ $i -eq $OLDBCT_MIN ]
    then
        break
    fi
done
if [ ${#OLDBCT_SHARES[@]} -ne $OLDBCT_MIN ]
then
    echo "Recovered only ${#OLDBCT_SHARES[@]} shares, minimum required is $OLDBCT_MIN"
    echo "Abort."
    exit 1
fi


echo "--------------------------------------------------------------------"
echo -e "\n\nRecovering escrow passphrase:"
echo "Recovered ${#OLDBCT_SHARES[@]} shares"
passphrase=$(echo ${OLDBCT_SHARES[@]} |\
             sed 's/ /\n/g' |\
             ssss-combine -t $OLDBCT_MIN 2>&1 |\
             awk '/^Resulting secret:/{print $3}')


echo "--------------------------------------------------------------------"
echo -e "\n\nTesting passphrase:"

data1="hello world"
data2=$(echo $data1 |\
        gpg $GPG_ARGS --encrypt --armor --recipient $GPG_KEY |\
        gpg $GPG_ARGS --decrypt --passphrase $passphrase )
if [ "$data1" == "$data2" ]
then
    echo "Test successful."
else
    echo "Error. It seems recovered passphrase doesn't allow to use escrow key :-("
    echo "Abort."
    exit 1
fi


echo "--------------------------------------------------------------------"
echo -e "\n\nDeleting old BCT member GPG public keys and saving new ones on USBSECURE1:"
rm -rf $BCT_MEMBERS_DIR_SEC1
mkdir $BCT_MEMBERS_DIR_SEC1
for ((i=1;i<=$BCT_TOTAL;i++))
do
    cp $BCT_MEMBERS_DIR_PUB/${BCT_MEMBERS[$i]}.gpg $BCT_MEMBERS_DIR_SEC1
done


echo "--------------------------------------------------------------------"
echo -e "\n\nWiping off old shares on USBSECURE1:"
for member in ${OLDBCT_MEMBERS[@]}
do
    # wiping on USB memory, no need for dozen passes
    wipe -f -q -Q1 $GPG_KEY_DIR_SEC1/BCT-$member-sharedsecret-N${OLDBCT_TOTAL}-T${OLDBCT_MIN}-TS${timestamp}.gpg
    wipe -f -q -Q1 $GPG_KEY_DIR_SEC1/BCT-$member-password-N${OLDBCT_TOTAL}-T${OLDBCT_MIN}-TS${timestamp}.gpg
done


echo "--------------------------------------------------------------------"
echo -e "\n\nSplitting passphrase in new shares, this takes a while:"
sharedsuffix="N${BCT_TOTAL}-T${BCT_MIN}-TS$(date +'%Y%m%d_%H%M%S').gpg"
i=0
for key in $(echo $passphrase |\
             ssss-split -t $BCT_MIN -n $BCT_TOTAL -Q)
do
    i=$(($i+1))
    echo "Handling Shared Secret #$i of ${BCT_MEMBERS[$i]}"
    while :
    do
      read -r -s -p "Enter password:" pwd1
      echo " ok"
      read -r -s -p "Repeat password:" pwd2
      if [ "$pwd1" == "$pwd2" ] && [ "$pwd1" != "" ]
      then
        echo " ok"
        break
      else
        echo " failed, try again!"
      fi
    done
    # don't use --passphrase on a multi-user system but here on live-cd it is acceptable
    echo "$key" | gpg $GPG_ARGS --symmetric --cipher-algo AES256 --armor --passphrase "$pwd1" > BCT-${BCT_MEMBERS[$i]}-sharedsecret-$sharedsuffix
    cp BCT-${BCT_MEMBERS[$i]}-sharedsecret-$sharedsuffix $GPG_KEY_DIR_SEC1
    echo "$pwd1" | gpg $GPG_ARGS --encrypt --armor --recipient ${BCT_MEMBERS[$i]} > BCT-${BCT_MEMBERS[$i]}-password-$sharedsuffix
    cp BCT-${BCT_MEMBERS[$i]}-password-$sharedsuffix $GPG_KEY_DIR_PUB
    cp BCT-${BCT_MEMBERS[$i]}-password-$sharedsuffix $GPG_KEY_DIR_SEC1
done

echo "--------------------------------------------------------------------"
echo -e "\n\nDone."
echo "We advise you to test escrowed data recovery with the new shares"
echo "and if it's ok, to replace USBSECURE2 content by USBSECURE1 content"
echo "otherwise, restore USBSECURE1 content based on USBSECURE2 content"
