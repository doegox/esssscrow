#!/bin/bash

# Requirements:
# We expect public keys of BCT members are available in files 
# named <BCT_MEMBER>.gpg on USBPUBLIC under directory "members"
# so e.g.: USBPUBLIC/members/mrnobody.gpg

# key name is "Escrow_key_myorg_YYYY" where YYYY is the current year
# you can overwrite it by providing it as argument to the script

# Minimum number of members to do escrow recovering:
BCT_MIN=2

# Keyserver in use
KEYSERVER=http://pgp.mit.edu:11371
# Passphrase length in BYTES
GPG_PASSLENGTH=16
# RSA keylength in BITS
GPG_KEYLENGTH=2048
# Key validity: 5 years
GPG_VALIDITY=5y


# Escrow key name
GPG_KEY="$1"
if [[ "$GPG_KEY" =~ " " ]]
then
    echo "Spaces in GPG keyname are *NOT* supported!"
    echo "Abort."
    exit 1
fi
GPG_KEY="${GPG_KEY:-Escrow_key_myorg_$(date +'%Y')}"

if ls -1 *.gpg >/dev/null 2>&1
then
    echo "There are still files of a previous run in the current directory."
    echo "Please delete them if you really want to generate a second key in the same run."
    echo "Abort."
    exit 1
fi
# Mount points of the three USB sticks:
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
USBSECURE2=$(pwd)/USBSECURE2
if [ ! -d "$USBSECURE2" ]
then
    echo "Error $USBSECURE2 not found"
    echo "Abort."
    exit 1
fi

BCT_MEMBERS_DIR_PUB=$USBPUBLIC/members
BCT_MEMBERS_DIR_SEC1=$USBSECURE1/members
BCT_MEMBERS_DIR_SEC2=$USBSECURE2/members
GPG_KEY_DIR_PUB=$USBPUBLIC/$GPG_KEY
GPG_KEY_DIR_SEC1=$USBSECURE1/$GPG_KEY
if [ -d $GPG_KEY_DIR_SEC1 ]
then
    echo "Error, a directory $GPG_KEY_DIR_SEC1 already exists!!"
    echo "You can change the GPG key name by providing it as argument."
    echo "Abort."
    exit 1
fi
GPG_KEY_DIR_SEC2=$USBSECURE2/$GPG_KEY
if [ -d $GPG_KEY_DIR_SEC2 ]
then
    echo "Error, a directory $GPG_KEY_DIR_SEC2 already exists!!"
    echo "You can change the GPG key name by providing it as argument."
    echo "Abort."
    exit 1
fi
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

# Common gpg arguments
GPG_ARGS_NOBATCH="--no-default-recipient --trust-model always"
GPG_ARGS="$GPG_ARGS_NOBATCH --batch"
export GNUPGHOME=$(pwd)/bct_gnupg


echo "--------------------------------------------------------------------"
echo -e "\n\nParameters:"
echo " * $((8*$GPG_PASSLENGTH))-bit passphrase to protect"
echo "   GPG escrow key named \"$GPG_KEY\""
echo "   ${GPG_KEYLENGTH}-bit RSA, valid for the next $GPG_VALIDITY"
echo " * $BCT_TOTAL BCT members"
echo " * Need collusion of at least $BCT_MIN members to use escrow key passphrase"
read -p "Is it correct? [y/n]: "
if [ "$REPLY" != "y" ]
then
    echo "Quitting..."
    exit 1
fi

mkdir -p $BCT_MEMBERS_DIR_SEC1
mkdir -p $BCT_MEMBERS_DIR_SEC2
mkdir -p $GPG_KEY_DIR_PUB
mkdir $GPG_KEY_DIR_SEC1
mkdir $GPG_KEY_DIR_SEC2
mkdir -p $GNUPGHOME
chmod 700 $GNUPGHOME


echo "--------------------------------------------------------------------"
echo -e "\n\nImporting BCT members GPG public keys:"
for ((i=1;i<=$BCT_TOTAL;i++))
do
    gpg $GPG_ARGS --import $BCT_MEMBERS_DIR_PUB/${BCT_MEMBERS[$i]}.gpg
    cp $BCT_MEMBERS_DIR_PUB/${BCT_MEMBERS[$i]}.gpg $BCT_MEMBERS_DIR_SEC1
    cp $BCT_MEMBERS_DIR_PUB/${BCT_MEMBERS[$i]}.gpg $BCT_MEMBERS_DIR_SEC2
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
read -p "Is it the correct BCT members list? [y/n]: "
if [ "$REPLY" != "y" ]
then
    echo "Quitting..."
    exit 1
fi


#echo "--------------------------------------------------------------------"
#echo -e "\n\nTesting random generation of $((8*$GPG_PASSLENGTH)) bits (base64-encoded):"
#openssl rand -base64 $GPG_PASSLENGTH


echo "--------------------------------------------------------------------"
echo -e "\n\nGenerating and splitting $((8*$GPG_PASSLENGTH))-bit passphrase, this takes a while:"
passphrase=$(openssl rand -base64 $GPG_PASSLENGTH)
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
    cp BCT-${BCT_MEMBERS[$i]}-sharedsecret-$sharedsuffix $GPG_KEY_DIR_SEC2
    echo "$pwd1" | gpg $GPG_ARGS --encrypt --armor --recipient ${BCT_MEMBERS[$i]} > BCT-${BCT_MEMBERS[$i]}-password-$sharedsuffix
    cp BCT-${BCT_MEMBERS[$i]}-password-$sharedsuffix $GPG_KEY_DIR_PUB
    cp BCT-${BCT_MEMBERS[$i]}-password-$sharedsuffix $GPG_KEY_DIR_SEC1
    cp BCT-${BCT_MEMBERS[$i]}-password-$sharedsuffix $GPG_KEY_DIR_SEC2
done

echo "--------------------------------------------------------------------"
echo -e "\n\nGenerating GPG escrow key, this takes a while:"
gpg $GPG_ARGS --gen-key <<EOF
    Key-Type: RSA
    Key-Length: $GPG_KEYLENGTH
    Key-Usage: encrypt
    Passphrase: $passphrase
    Name-Real: $GPG_KEY
    Expire-Date: $GPG_VALIDITY
    Keyserver: $KEYSERVER
    %commit
    %echo Done.
EOF

gpg $GPG_ARGS --armor --output BCT-escrow-secretkey.gpg --export-secret-keys "$GPG_KEY"
cp BCT-escrow-secretkey.gpg $GPG_KEY_DIR_SEC1
cp BCT-escrow-secretkey.gpg $GPG_KEY_DIR_SEC2
gpg $GPG_ARGS --armor --output BCT-escrow-publickey.gpg --export "$GPG_KEY"
cp BCT-escrow-publickey.gpg $GPG_KEY_DIR_PUB
cp BCT-escrow-publickey.gpg $GPG_KEY_DIR_SEC1
cp BCT-escrow-publickey.gpg $GPG_KEY_DIR_SEC2
gpg $GPG_ARGS --list-secret-keys --fingerprint
read -p ">>>>> Please Write down the fingerprint and press ENTER when done. <<<<<"

echo "--------------------------------------------------------------------"
echo -e "\n\nGenerating revocation certificate:"
while [ ! -e BCT-escrow-revocation.gpg ]
do
    echo ">>>>> It will ask confirmation to generate a revocation certificate. Please say yes. <<<<<"
    gpg $GPG_ARGS_NOBATCH --passphrase $passphrase --output BCT-escrow-revocation.gpg --gen-revoke "$GPG_KEY"
done
cp BCT-escrow-revocation.gpg $GPG_KEY_DIR_PUB
cp BCT-escrow-revocation.gpg $GPG_KEY_DIR_SEC1
cp BCT-escrow-revocation.gpg $GPG_KEY_DIR_SEC2

