#!/bin/bash

# set -x
export GOPROXY='direct'

ACCOUNT=$1
REGION=$2
CLUSTER=$3
SIGNER_NAME=${4:-'my-private-signer.com/my-signer'}
AL2=$5
ESCAPED_SIGNER_NAME=${SIGNER_NAME/\//\\\/}

ACCOUNT_REGEX='^[0-9]{12}$'
REGION_REGEX='^[a-zA-Z0-9-]{1,128}$'
test_command(){

    $@ > /dev/null 2>&1
    if [ $? == '127' ]
    then
        return 1
    else
        return 0
    fi
}

run_al2_prereq_installation(){

    if [[ $1 ]]
    then
        echo "Installing Amazon Linux 2 dependencies"
        bash ./AL2-dependency-installation.sh
    fi
}

validate_regex(){
    PARAMETER=$1
    REGEX=$2
    [[ $PARAMETER =~ $REGEX ]] && return 0 || return 1
    return $?
}
validate_account(){
    ACCOUNT=$1
    validate_regex $ACCOUNT $ACCOUNT_REGEX
    return $?
}
validate_region(){
    REGION=$1
    validate_regex $REGION $REGION_REGEX
    return $?
}
validate_AL2(){
    [[ '$1' != 'AL2' ]] && return 0 || return 1
}
validate_parameters(){

    validate_account $ACCOUNT
    if [[ $? -eq 0 ]]
    then 
        echo "Valid Account. Proceeding"
    else
        echo "Invalid Account. Aborting"
        exit 1
    fi
    validate_region $REGION
    if [[ $? -eq 0 ]]
    then
        echo "Valid region. Proceeding"
    else
        echo "Invalid region. Aborting"
        exit 1
    fi
    if [ -n $AL2 ]
    then
        validate_AL2 $AL2
        if [[ $? -eq 0 ]]
        then
            echo "Valid OS parameter. Proceeding"
        else
            echo "Invalid OS parameter. Aborting"
            exit 1
        fi
    fi
    
}

#CHECKING PARAMETERS
validate_parameters
run_al2_prereq_installation $AL2

#PERFORMING CHECKS
AWS_CLI="aws --version"
if  ! test_command $AWS_CLI;
then
    echo "AWS binary not installed. Please install it before running this script."
    exit 1
fi
DOCKER="docker version"
if ! test_command $DOCKER;
then
    echo "Docker binary not installed. Please install it before running this script."
    exit 1
fi
CFSSL="cfssl version"
if ! test_command $CFSSL;
then
    echo "cfssl binary not installed. Please install it before running this script."
    exit 1
fi
CFSSLJSON="cfssljson -version"
if ! test_command $CFSSLJSON;
then
    echo "cfssljson binary not installed. Please install it before running this script."
    exit 1
fi
KUSTOMIZE="kustomize version"
if ! test_command $KUSTOMIZE;
then
    echo "kustomize binary not installed. Please install it before running this script."
    exit 1
fi
GIT="git version"
if ! test_command $GIT;
then
    echo "git binary not installed. Please install it before running this script."
    exit 1
fi
KUBECTL="kubectl version"
if ! test_command $KUBECTL;
then
    echo "kubectl binary not installed. Please install it before running this script."
    exit 1
fi
REALPATH="realpath --version"
if ! test_command $REALPATH;
then
    echo "realpath binary not installed. Please install it before running this script."
    exit 1
fi
#END OF CHECKS

#CONFIGURING KUBECTL
aws eks update-kubeconfig --name $CLUSTER --region $REGION
#END OF KUBECTL CONFIGURATION

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
sed -i.back "s/  - example.com\/foo/  - ${ESCAPED_SIGNER_NAME}/g" config/e2e/rbac.yaml

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
sed -i.back "s/signerName: kubernetes.io\/kubelet-serving/signerName: $ESCAPED_SIGNER_NAME/g" create-signed-cert.sh

#GETTING THE CREATED CA CERTIFICATE AND UPDATING IT IN THE DEPLOYMENT FILE
SECRET=$(kubectl get secrets --sort-by {.metadata.creationTimestamp} | grep signer-ca | tail -1 | awk '{print $1}')
CA=$(kubectl get secrets $SECRET -o jsonpath='{.data.tls\.crt}')
sed -i.back "s/.*CA_BUNDLE=.*/        CA_BUNDLE=$CA \\\/g" deploy-gmsa-webhook.sh

#FIXING FILE FOR MACOS USERS
MACOS=$(sw_vers)
if [[ $MACOS ]]
then
    sed -i.back2 "s/-w 0/-b 0/g" deploy-gmsa-webhook.sh
    sed -i.back2 "s/-w 0/-b 0/g" create-signed-cert.sh
fi

#RUNNING THE INSTALLATION
K8S_GMSA_DEPLOY_DOWNLOAD_REV='v0.3.0' ./deploy-gmsa-webhook.sh --file ./gmsa-manifests --image sigwindowstools/k8s-gmsa-webhook:v0.3.0 --overwrite
#END OF gMSA INSTALLATION

#END OF SCRIPT