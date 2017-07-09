#!/bin/bash

set -ev

mkdir -p out
mdbook build --dest-dir out/1

redirect='<meta http-equiv="refresh" content="0; url=1/index.html" />'
echo $redirect > out/index.html
