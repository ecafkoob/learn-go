#!/bin/bash -ex

apt update && apt install vim gdb binutils -y

curl -fsSL https://get.docker.com -o get-docker.sh

curl -L -o go1.17.1.linux-amd64.tar.gz https://golang.org/dl/go1.17.1.linux-amd64.tar.gz

rm -rf /usr/local/go && tar -C /usr/local -xzf go1.17.1.linux-amd64.tar.gz

echo "PATH=$PATH:/usr/local/go/bin:/home/vagrant/go/bin">/etc/environment

mkdir -p /usr/local/go/bin

export PATH=$PATH:/usr/local/go/bin:/home/vagrant/go/bin

go version

go install github.com/go-delve/delve/cmd/dlv@latest
