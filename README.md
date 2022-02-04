# gMSA2x3x-EKS-Installation

As, currently, EKS do not support "kubernetes.io/kubelet-serving" certificates for non-node objects the gMSA deploy [scripts](https://github.com/kubernetes-sigs/windows-gmsa/blob/master/admission-webhook/deploy/create-signed-cert.sh#L120_) are not suitable for deploy in EKS.

Thinking on an alternative, I developed this project which has two major objectives:

1. Install [certmanager-CA](https://github.com/cert-manager/signer-ca);
2. Use it to sign the CSRs for gMSA instead of the default controller.

## Utilization

First, ensure that all the prerequisites are in place. You’d need, in the computer that is running the script:

1. A docker daemon (to build the needed images);
    1. Centos: https://docs.docker.com/engine/install/centos/
    2. Debian: https://docs.docker.com/engine/install/debian/
2. The following binaries:
    1. [cfssl](https://computingforgeeks.com/how-to-install-cloudflare-cfssl-on-linux-macos/) 

    ```shell
    VERSION=$(curl --silent "https://api.github.com/repos/cloudflare/cfssl/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    VNUMBER=${VERSION#"v"}
    wget https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssl_${VNUMBER}_linux_amd64 -O cfssl
    chmod +x cfssl
    sudo mv cfssl /usr/local/bin
    ```

    2. [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/binaries/)
    ```shell
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    ```
    3. git
        1. Debian: sudo apt-get install git
        2. Centos: sudo yum install git
    4. realpath
        1. Debian: sudo apt-get install coreutils
        2. Centos: sudo yum install coreutils

3. The kubectl binary (https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-binary-with-curl-on-linux) with the current context pointing to the cluster you’d like to perform the installation;

    ```shell
        $ curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        $ sudo chmod +x kubectl
        $ sudo chmod install kubectl /usr/local/bin
    ```

4. An ‘aws’ cli v2 (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)installed and configured with needed credentials. The credentials could be provided from anywhere in the default credential chain (environment variables, files, instance profiles, etc).

    ```shell
        $ curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        $ unzip awscliv2.zip
        $ sudo ./aws/install
    ```

Once all the above is set, run the following commands:

```
$ git clone https://github.com/flaviosakakibara/gMSA2x3x-EKS-Installation.git
$ cd gMSA2x3x-EKS-Installation/
$ bash installation.sh <account> <region> <my-private-signer.com/my-signer>
```

Kindly note that <my-private-signer.com/my-signer> is the parameter for the name of the signer to be used in the CSR and could be any value in the "domain.com/name" format.

## Known issues

If you’ve already installed gMSA, you could see the following errors, after executing the “installation.sh” script:

```log
2022/01/31 17:24:56 http: TLS handshake error from 192.168.142.58:52218: remote error: tls: bad certificate
```

If so, kindly remove gMSA by running the following command:

```shell
$ kubectl delete -f windows-gmsa/admission-webhook/deploy/gmsa-manifests
```

And the installation script again:

```shell
$ bash installation.sh 765427072911 eu-west-1 my-private-signer.com/my-signer
```

## Permissions needed
ecr:GetAuthorizationToken
ecr:CreateRepository
ecr:DescribeImages
eks:DescribeCluster

Example:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "ecr:CreateRepository",
                "ecr:DescribeImages",
                "ecr:GetAuthorizationToken"
            ],
            "Resource": [
                "arn:aws:ecr:*:*:repository/certmanager-ca-controller"
            ]
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "arn:aws:eks:*:765427072911:cluster/*"
        },
        {
            "Sid": "VisualEditor3",
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```