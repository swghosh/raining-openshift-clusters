#!/usr/bin/bash


# override release image with custom release and create the cluster from supplied install-config
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:-"quay.io/openshift-release-dev/ocp-release:4.15.3-x86_64"}
AZ_REGION=${AZ_REGION:-"centralus"}
# base domain for cluster creation, must be Azure DNS zone
BASE_DOMAIN=${BASE_DOMAIN:-"openshift.codecrafts.cf"}
AZ_DNS_RESOURCE_GROUP=${AZ_DNS_RESOURCE_GROUP:-"dns-rg"}
# path to file containing pull secrets
PULL_SECRET_PATH=${PULL_SECRET_PATH:-"$HOME/.docker/config.json"}
# azure subscription id, required!
AZ_SUBSCRIPTION_ID=${AZ_SUBSCRIPTION_ID:-"invalid-subscription-id"}
# whether to az login, default is true
AZ_LOGIN=${AZ_LOGIN:-"1"}

# --------------------

# azure credentials pre-init
# run this every few days or so,
# the following az commands are not required if you already 
# have a valid ~/.azure/osServicePrincipal.json present
if [ "${AZ_LOGIN}" -eq "1" ]; then
  az_client_cred_tmp_dir="$(mktemp -d)"
  
  az login
  az ad sp create-for-rbac --role Owner --name "$(whoami)"-installer --scopes "/subscriptions/${AZ_SUBSCRIPTION_ID}" > "$az_client_cred_tmp_dir"/az_credentials.json

  # IMPORTANT: Please ensure ~/.azure/osServicePrincipal.json contains a valid token!
  # Else, azure cannot authenticate. To avoid problems, rm ~/.azure/osServicePrincipal.json and 
  # fill subscription id, tenant id, client app id and client secret manually from output of above command.

  python3 - << EOF
import json, os
with open('${az_client_cred_tmp_dir}/az_credentials.json', 'r') as src_f:
  az_creds = json.load(src_f)

os_creds = {
  "subscriptionId": "${AZ_SUBSCRIPTION_ID}",
  "clientId": f"{az_creds['appId']}",
  "clientSecret": f"{az_creds['password']}",
  "tenantId": f"{az_creds['tenant']}"
}

os.makedirs("${HOME}/.azure", exist_ok=True)
with open('${HOME}/.azure/osServicePrincipal.json', 'w') as dst_f:
  json.dump(os_creds, dst_f)
EOF

fi

AZ_TENANT_ID=$(python3 - << EOF
import json

with open('${HOME}/.azure/osServicePrincipal.json') as os_creds_f:
  os_creds = json.load(os_creds_f)
  print(os_creds['tenantId'])
EOF
)

# generate a cluster name with username, date and 8 random hex
CLUSTER_NAME=$(whoami)$(date +"%Y%m%d")$(echo $RANDOM | md5sum | head -c 8)
export CLUSTER_NAME

# create an install-config in a directory
CLUSTER_DIR="clusters/$CLUSTER_NAME"
mkdir -p "$CLUSTER_DIR"

# create directory for cloud credentials ccoctl
CCO_DIR=clusters/cco-"$CLUSTER_NAME"
mkdir "$CCO_DIR"

# extract cco manifests
oc adm release extract \
  --credentials-requests \
  --cloud=azure \
  --to="$CCO_DIR"/cred-reqs \
  "$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE" 2>&1 | tee "$CLUSTER_NAME".log

oc adm release extract --command='openshift-install' ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}
oc adm release extract --command='ccoctl' ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}

# create cloud accounts and secrets
./ccoctl azure create-all \
    --name "$CLUSTER_NAME" \
    --region "${AZ_REGION}" \
    --subscription-id "${AZ_SUBSCRIPTION_ID}" \
    --tenant-id "${AZ_TENANT_ID}" \
    --credentials-requests-dir "$CCO_DIR"/cred-reqs \
    --output-dir="$CCO_DIR"/output \
    --dnszone-resource-group-name "${AZ_DNS_RESOURCE_GROUP}"

# get pull secrets
PULL_SECRET=$(python3 json-minify.py "$PULL_SECRET_PATH")

# create an install-config in a directory
cat << EOF > "${CLUSTER_DIR}"/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
credentialsMode: Manual
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  replicas: 1
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
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
    resourceGroupName: ${CLUSTER_NAME}
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

./openshift-install create manifests --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee "$CLUSTER_NAME".log
read -r -n 1 -p "Manifests have been created, press any key to continue to cluster creation step... "

# copy ccoctl generated manifests and tls certs
cp -v "$CCO_DIR"/output/manifests/* "${CLUSTER_DIR}"/manifests/
cp -av "$CCO_DIR"/output/tls "${CLUSTER_DIR}"

./openshift-install create cluster --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log

# after cluster creation succeeds copy kubeconfig to ~/.kube/config
cp -f "${CLUSTER_DIR}"/auth/kubeconfig ~/.kube/config
