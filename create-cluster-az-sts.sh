#!/usr/bin/bash

subscription_id="<REDACTED>" # add your Azure subscription id
tenant_id="<REDACTED>" # add your Azure tenant id
dns_resource_group="<REDACTED>" # add the rg where dns zone for baseDomain is present

az_region="centralus"

# azure pre-init
# run this every week or so
az login
az ad sp create-for-rbac --role Owner --name "$(whoami)"-installer --scopes "/subscriptions/${subscription_id}"
# IMPORTANT: Please ensure ~/.azure/osServicePrincipal.json contains a valid token!
# Else, azure cannot authenticate. To avoid problems, rm ~/.azure/osServicePrincipal.json and 
# fill subscription id, tenant id, client app id and client secret manually.

# override release image with custom release and create the cluster from supplied install-config
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/openshift-release-dev/ocp-release:4.16.0-ec.3-x86_64

# generate a cluster name with username, date and 8 random hex
CLUSTER_NAME=$(whoami)$(date +"%Y%m%d")$(echo $RANDOM | md5sum | head -c 8)
export CLUSTER_NAME
CLUSTER_DIR="clusters/${CLUSTER_NAME}"

# get pull secrets
PULL_SECRET_PATH=~/.docker/config.json
PULL_SECRET=$(python3 json-minify.py $PULL_SECRET_PATH)

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
    --region "$az_region" \
    --subscription-id "$subscription_id" \
    --tenant-id "$tenant_id" \
    --credentials-requests-dir "$CCO_DIR"/cred-reqs \
    --output-dir="$CCO_DIR"/output \
    --dnszone-resource-group-name "$dns_resource_group"

# create an install-config in a directory
mkdir "${CLUSTER_DIR}"
cat << EOF > "${CLUSTER_DIR}"/install-config.yaml
apiVersion: v1
baseDomain: catchall.azure.devcluster.openshift.com
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
    baseDomainResourceGroupName: $dns_resource_group
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: $az_region
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
