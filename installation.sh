#!/bin/bash

set -x
export GOPROXY='direct'

ACCOUNT=$1
REGION=$2
SIGNER_NAME=$3

#PERFORMING CHECKS
DOCKER_RUNNING=$(docker ps)
if [[ ! $DOCKER_RUNNING ]]
then
    echo "Not able to access the Docker Daemon. Kindly check if it's running before running this script"
    exit 1
fi
CFSSL=$(cfssl version)
if [[ ! $CFSSL ]]
then
    echo "cfssl binary not installed. Kindly check if it's installed before running this script"
    exit 1
fi
KUSTOMIZE=$(kustomize version)
if [[ ! $KUSTOMIZE ]]
then
    echo "kustomize binary not installed. Kindly check if it's installed before running this script"
    exit 1
fi
GIT=$(git version)
if [[ ! $GIT ]]
then
    echo "git binary not installed. Kindly check if it's installed before running this script"
    exit 1
fi
KUBECTL=$(kubectl version)
if [[ ! $KUBECTL ]]
then
    echo "kubectl binary not installed. Kindly check if it's installed before running this script"
    exit 1
fi
REALPATH=$(realpath --version)
if [[ ! $REALPATH ]]
then
    echo "realpath binary not installed. Kindly check if it's installed before running this script"
    exit 1
fi
#END OF CHECKS

#CREATING ECR REPOSITORY
ECR_URL=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
REPOSITORY_NAME=certmanager-ca-controller
DOCKER_PREFIX=$ECR_URL/certmanager-ca-

REPOSITORY_EXISTS=$(aws ecr describe-images --repository-name $REPOSITORY_NAME --region $REGION)

if [[ ! $REPOSITORY_EXISTS ]]
then
    REPOSITORY_CREATION=$(aws ecr create-repository --repository-name $REPOSITORY_NAME --region $REGION)
else
    echo "Repository already created"
fi
#END OF REPOSITORY CREATION

#INITIATING BUILD AND INSTALLATION OF CA
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL

if [[ -d "signer-ca" ]]
then
    rm -rf signer-ca
    git clone https://github.com/cert-manager/signer-ca.git
else
    git clone https://github.com/cert-manager/signer-ca.git
fi
cd signer-ca

#ADDING HOST NETWORK TO MAKEFILE
sed -i.back 's/docker build . -t \${DOCKER_IMAGE}/docker build . -t \${DOCKER_IMAGE} --network=host/g' Makefile

#UPDATING GO PROXY IN DOCKERFILE
sed -i.back "s/RUN go mod download/RUN export GOPROXY='direct' \&\& go mod download/g" Dockerfile

#ADDING CUSTOM SIGNER NAME TO KUSTOMIZATION FILE
echo '        - "--signer-name='$SIGNER_NAME'"' >> config/default/manager_auth_proxy_patch.yaml
sed -i.back "s/  - example.com\/foo/  - ${SIGNER_NAME/\//\\\/}/g" config/e2e/rbac.yaml

#ADDING CUSTOM NAME TO SIGNER
make docker-build docker-push deploy-e2e DOCKER_PREFIX=$DOCKER_PREFIX

cd ..

#END OF CA BUILD AND INSTALLATION

#CONFIGURATION OF gMSA INSTALLATION SCRIPT TO USE ISNTALLED CA
if [[ -d "windows-gmsa" ]]
then
    rm -rf windows-gmsa
    git clone https://github.com/kubernetes-sigs/windows-gmsa.git
else
    git clone https://github.com/kubernetes-sigs/windows-gmsa.git
fi

cd windows-gmsa/admission-webhook/deploy

#CHANGE THE SIGNER NAME FOR THE ONE WE CONFIGURED PREVIOUSLY IN THE CA
sed -i.back "s/signerName: kubernetes.io\/kubelet-serving/signerName: ${SIGNER_NAME/\//\\\/}/g" create-signed-cert.sh

#GETTING THE CREATED CA CERTIFICATE AND UPDATING IT IN THE DEPLOYMENT FILE
SECRET=$(kubectl get secrets --sort-by {.metadata.creationTimestamp} | grep signer-ca | tail -1 | awk '{print $1}')
CA=$(kubectl get secrets $SECRET -o jsonpath='{.data.tls\.crt}')
sed -i.back "s/.*CA_BUNDLE=.*/        CA_BUNDLE=$CA \\\/g" deploy-gmsa-webhook.sh

#FIXING FILE FOR MACOS USERS
MACOS=$(sw_vers)
if [[ sw_vers ]]
then
    sed -i.back2 "s/-w 0/-b 0/g" deploy-gmsa-webhook.sh
    sed -i.back2 "s/-w 0/-b 0/g" create-signed-cert.sh
fi

#RUNNING THE INSTALLATION
K8S_GMSA_DEPLOY_DOWNLOAD_REV='v0.3.0' ./deploy-gmsa-webhook.sh --file ./gmsa-manifests --image sigwindowstools/k8s-gmsa-webhook:v0.3.0 --overwrite
#END OF gMSA INSTALLATION

#END OF SCRIPT