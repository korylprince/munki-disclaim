#!/bin/bash

adhoc=""    
if [ "$1" == "adhoc" ]; then    
    adhoc="-Wl,-adhoc_codesign"    
fi    

mkdir -p build    

clang++ munkishim.mm -o build/munkishim.x86_64 -target x86_64-apple-macos10.12 "$adhoc"    
clang++ munkishim.mm -o build/munkishim.arm -target arm64-apple-macos11 "$adhoc"    
lipo -create -output build/munkishim build/munkishim.x86_64 build/munkishim.arm
