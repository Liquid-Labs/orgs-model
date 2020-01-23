#!/usr/bin/env bash

VERSION=1.2.2
curl -L https://github.com/noqcks/gucci/releases/download/${VERSION}/gucci-v${VERSION}-darwin-amd64 -o ./bin/gucci
chmod a+x ./bin/gucci
