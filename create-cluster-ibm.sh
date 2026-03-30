#!/usr/bin/bash
set -euo pipefail

# IBM cloud credentials
export IC_API_KEY=${IC_API_KEY:-"<secret-api-key>"}

# override release image with custom release and create the cluster from supplied install-config
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:-"quay.io/openshift-release-dev/ocp-release:4.21.6-x86_64"}
# ibm cloud region
IBM_REGION=${IBM_REGION:-"us-east"}
# base domain for cluster creation
BASE_DOMAIN=${BASE_DOMAIN:-"ibm.devcluster.openshift.com"}
# path to file containing pull secrets
PULL_SECRET_PATH=${PULL_SECRET_PATH:-"$HOME/.docker/config.json"}
# whether to allow injecting custom manifests after install-config stage and before bootstrap stage
INJECT_MANIFESTS=${INJECT_MANIFESTS:-"false"}

# --------------------

# generate a cluster name with username, date and 8 random hex
CLUSTER_NAME=$(whoami)-$(date +"%Y%m%d")-$(echo $RANDOM | md5sum | head -c 8)
export CLUSTER_NAME

oc adm release extract --command='openshift-install' ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}
oc adm release extract --command='ccoctl' ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}

# create an install-config in a directory
CLUSTER_DIR="clusters/$CLUSTER_NAME"
mkdir -p "$CLUSTER_DIR"

# create directory for cloud credentials ccoctl
CCO_DIR=clusters/cco-"$CLUSTER_NAME"
mkdir "$CCO_DIR"

# extract cco manifests
oc adm release extract \
  --credentials-requests \
  --cloud=ibmcloud \
  --to="$CCO_DIR"/cred-reqs \
  "$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE" 2>&1 | tee "$CLUSTER_NAME".log

# create ibm cloud service IDs and API keys
./ccoctl ibmcloud create-service-id \
  --credentials-requests-dir="$CCO_DIR"/cred-reqs \
  --name="$CLUSTER_NAME" \
  --output-dir="$CCO_DIR"/output 2>&1 | tee -a "$CLUSTER_NAME".log

# get pull secrets
PULL_SECRET=$(python3 json-minify.py "$PULL_SECRET_PATH")

# install-config
cat << EOF > "$CLUSTER_DIR"/install-config.yaml
additionalTrustBundlePolicy: Proxyonly
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
credentialsMode: Manual
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
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
  ibmcloud:
    region: ${IBM_REGION}
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
  $(cat ~/.ssh/id_ed25519.pub)
EOF

./openshift-install create manifests --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log

if [ "$INJECT_MANIFESTS" = true ]; then
  read -r -n 1 -p "Manifests have been created, press any key to continue to cluster creation step... "
fi

# copy ccoctl generated manifests
cp -v "$CCO_DIR"/output/manifests/* "$CLUSTER_DIR"/manifests/

./openshift-install create cluster --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log

# after cluster creation succeeds copy kubeconfig to ~/.kube/config
cp -f "$CLUSTER_DIR"/auth/kubeconfig ~/.kube/config
