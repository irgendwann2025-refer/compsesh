#!/bin/bash

echo "WHITELIST=("
ps -eo comm | sort -u | sed 's/^/ "/; s/$/"/'
echo ")"
