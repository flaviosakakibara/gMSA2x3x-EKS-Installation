#!/bin/bash

# set -x
test_command(){

    $@ > /dev/null 2>&1
    if [ $? == '127' ]
    then
        echo "Command $1 not installed"
        return 1
    else
        echo "Command $1 installed"
        return 0
    fi
}

install_aws_cli() {
    echo "Installing AWS CLI"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
}
install_docker() {
    echo "Installing Docker"

}
install_cfssl() {
    echo "Installing CFSSL"

}
install_cfssljson() {
    echo "Installing CFSSLJSON"

}
install_kustomize() {
    echo "Installing Kustomize"

}
install_git() {
    echo "Installing Git"

}
install_kubectl() {
    echo "Installing Kubectl"

}
install_realpath() {
    echo "Installing realpath"

}

#PERFORMING CHECKS
AWS_CLI="aws --version"
if  ! test_command $AWS_CLI;
then
    echo "AWS binary not installed. Installing it."
    install_aws_cli
fi
DOCKER="docker version"
if ! test_command $DOCKER;
then
    echo "Docker binary not installed. Installing it."
    install_docker
fi
CFSSL="cfssl version"
if ! test_command $CFSSL;
then
    echo "cfssl binary not installed. Installing it."
    install_cfssl
fi
CFSSLJSON="cfssljson -version"
if ! test_command $CFSSLJSON;
then
    echo "cfssljson binary not installed. Installing it."
    install_cfssljson
fi
KUSTOMIZE="kustomize version"
if ! test_command $KUSTOMIZE;
then
    echo "kustomize binary not installed. Installing it."
    install_kustomize
fi
GIT="git version"
if ! test_command $GIT;
then
    echo "git binary not installed. Installing it."
    install_git
fi
KUBECTL="kubectl version"
if ! test_command $KUBECTL;
then
    echo "kubectl binary not installed. Installing it."
    install_kubectl
fi
REALPATH="realpath --version"
if ! test_command $REALPATH;
then
    echo "realpath binary not installed. Installing it."
    install_realpath
fi