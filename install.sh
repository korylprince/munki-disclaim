#!/bin/bash

if [ ! -f "munkitools-6.2.0.4541.pkg" ]; then
    curl -LO "https://github.com/munki/munki/releases/download/v6.2.0/munkitools-6.2.0.4541.pkg"
fi

installer -target / -pkg munkitools-6.2.0.4541.pkg

cp build/munkishim /usr/local/munki/munkishim

# pkg.py from munkitools-6.1.0.4533.pkg from https://groups.google.com/g/munki-dev/c/hFy4y4g4okc
cp pkg.py /usr/local/munki/munkilib/installer/pkg.py

mv /usr/local/munki/managedsoftwareupdate /usr/local/munki/managedsoftwareupdate.py
ln -s /usr/local/munki/munkishim /usr/local/munki/managedsoftwareupdate

mv /usr/local/munki/supervisor /usr/local/munki/supervisor.py
ln -s /usr/local/munki/munkishim /usr/local/munki/supervisor
