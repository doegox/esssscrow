#!/bin/bash

# Goal is to clean all generated data, including keys and certificates
# !!!! do it only for testing purposes, don't use it on real data      !!!!

echo "                 >>>>>          WARNING           <<<<<"
echo "This is supposed to be used only for test purpose"
echo "IT WILL DESTROY ALL DATA ON USB STICKS"
read -p "Do you really want to continue? [y/n]"

if [ "$REPLY" != "y" ]
then
    echo "Quitting..."
    exit 1
fi

read -p "Really really??? [y/n]"

if [ "$REPLY" != "y" ]
then
    echo "Quitting..."
    exit 1
fi

rm *.gpg
rm -rf USBSECURE1 USBSECURE2 bct_gnupg USBPUBLIC
mkdir USBSECURE1 USBSECURE2 USBPUBLIC
