#!/bin/bash

# It will generate an escrowed test data

# Requirements:
# We expect escrow material on USBSECURE1

# Mount points of the USB stick:
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
ESCROWSECKEY=""
for file in $(ls -1 $USBSECURE1/*/BCT-escrow-secretkey.gpg|sort -r -n)
do
    read -p "Using $(dirname $file)? [y/n]: "
    if [ "$REPLY" == "y" ]
    then
        ESCROWSECKEY=$file
        break
    fi
done
if [ "$ESCROWSECKEY" == "" ]
then
    echo "Error, no more key found"
    echo "Abort."
    exit 1
fi

# Escrow key name
GPG_KEY=$(basename $(dirname $ESCROWSECKEY))
GPG_KEY_DIR_SEC1=$USBSECURE1/$GPG_KEY

# Common gpg arguments
GPG_ARGS_NOBATCH="--no-default-recipient --trust-model always"
GPG_ARGS="$GPG_ARGS_NOBATCH --batch"
export GNUPGHOME=$(pwd)/bct_gnupg
mkdir -p $GNUPGHOME
chmod 700 $GNUPGHOME

echo "--------------------------------------------------------------------"
echo -e "\n\nImporting Escrow key $GPG_KEY:"
gpg $GPG_ARGS --import $GPG_KEY_DIR_SEC1/BCT-escrow-secretkey.gpg

echo "--------------------------------------------------------------------"
echo -e "\n\nEscrowing \"hello world\" in test-hw-$GPG_KEY.gpg"
echo "hello world" | gpg $GPG_ARGS --encrypt --armor --recipient "$GPG_KEY" --output "test-hw-$GPG_KEY.gpg"
echo "Done."
