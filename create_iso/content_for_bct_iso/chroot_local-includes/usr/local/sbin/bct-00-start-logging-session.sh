#!/bin/bash

LOG=BCT-logfile-$(date +'%Y%m%d-%H%M%S').txt
echo ">>>>> Session recorded into $LOG <<<<<"
echo ">>>>> Press ctrl-D to stop recording, then save the file to a USB stick <<<<<"
script -f $LOG

for USB in USBPUBLIC USBSECURE1 USBSECURE2
do
    if grep -q $USB /etc/mtab
    then
        mkdir -p $USB/logs
        cp $LOG $USB/logs/ && echo ">>>>> Logfile $LOG saved on $USB <<<<<"
    fi
done
