#!/bin/bash

# Goal is to inject data into the kernel entropy pool to fasten gpg key generation
# !!!! do it only for testing purposes, don't generate real keys with it      !!!!

echo "                 >>>>>          WARNING           <<<<<"
echo "This is supposed to be used only for test purpose through an emulator"
read -p "Do you really want to continue? [y/n]"

if [ "$REPLY" != "y" ]
then
    echo "Quitting..."
    exit 1
fi

mkdir /tmp/hackrandom || exit 1
cat > /tmp/hackrandom/arecord << EOF
#!/bin/bash
date +'%Y%m%d-%H%M%S' >> /tmp/hackrandom/hackrandom.log
cat /dev/urandom
EOF
chmod 755 /tmp/hackrandom/arecord
export PATH="/tmp/hackrandom:$PATH"
/etc/init.d/randomsound stop
randomsound -D
echo "Now entropy hack is running in background..."
echo ""
echo "Preparing dummy BCT members public keys"
cp -a USBPUBLIC-dummy/members USBPUBLIC
