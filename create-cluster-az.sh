#!/usr/bin/bash
set -euo pipefail

# override release image with custom release and create the cluster from supplied install-config
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:-"quay.io/openshift-release-dev/ocp-release:4.15.3-x86_64"}
AZ_REGION=${AZ_REGION:-"centralus"}
# base domain for cluster creation, must be Azure DNS zone
BASE_DOMAIN=${BASE_DOMAIN:-"openshift.codecrafts.cf"}
AZ_DNS_RESOURCE_GROUP=${AZ_DNS_RESOURCE_GROUP:-"dns-rg"}
# path to file containing pull secrets
PULL_SECRET_PATH=${PULL_SECRET_PATH:-"$HOME/.docker/config.json"}
# azure subscription id, required!
az_subscription_id=${az_subscription_id:-"invalid-subscription-id"}
# whether to az login, default is true
az_login=${az_login:-"1"}

# --------------------

# azure credentials pre-init
# run this every few days or so,
# the following az commands are not required if you already 
# have a valid ~/.azure/osServicePrincipal.json present
if [ "${az_login}" -eq "1" ]; then
  az login
  az ad sp create-for-rbac --role Owner --name "$(whoami)"-installer --scopes "/subscriptions/${az_subscription_id}"
fi

# generate a cluster name with username, date and 8 random hex
CLUSTER_NAME=$(whoami)-$(date +"%Y%m%d")-$(echo $RANDOM | md5sum | head -c 8)
export CLUSTER_NAME

# create an install-config in a directory
CLUSTER_DIR="clusters/$CLUSTER_NAME"
mkdir -p "$CLUSTER_DIR"

# get pull secrets
PULL_SECRET=$(python3 json-minify.py "$PULL_SECRET_PATH")

oc adm release extract --command='openshift-install' ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}

# create an install-config in a directory
cat << EOF > "$CLUSTER_DIR"/install-config.yaml
additionalTrustBundlePolicy: Proxyonly
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 1
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  creationTimestamp: null
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  azure:
    baseDomainResourceGroupName: ${AZ_DNS_RESOURCE_GROUP}
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: ${AZ_REGION}
publish: External
pullSecret: '${PULL_SECRET}'
# optional - add ssh key for VMs
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

./openshift-install create manifests --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee "$CLUSTER_NAME".log
read -r -n 1 -p "Manifests have been created, press any key to continue to cluster creation step... "
./openshift-install create cluster --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log

# after cluster creation succeeds copy kubeconfig to ~/.kube/config
cp -f "${CLUSTER_DIR}"/auth/kubeconfig ~/.kube/config
