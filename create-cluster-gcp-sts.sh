#!/usr/bin/bash
set -euo pipefail

export GOOGLE_APPLICATION_CREDENTIALS=~/serviceaccount.json

# override release image with custom release and create the cluster from supplied install-config
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/openshift-release-dev/ocp-release:4.13.0-x86_64

GCP_PROJECT=openshift-gce-devel
GCP_REGION=asia-south1

# base domain for cluster creation, must be Google Cloud DNS zone
BASE_DOMAIN="gcp.devcluster.openshift.com"

# get pull secrets
PULL_SECRET_PATH=~/.docker/config.json
PULL_SECRET=$(python3 json-minify.py $PULL_SECRET_PATH)

# generate a cluster name with username, date and 8 random hex
CLUSTER_NAME=$(whoami)-$(date +"%Y%m%d")-$(echo $RANDOM | md5sum | head -c 8)
export CLUSTER_NAME

# create an install-config in a directory
mkdir "$CLUSTER_NAME"

# create directory for cloud credentials ccoctl
CCO_DIR=cco-"$CLUSTER_NAME"
mkdir "$CCO_DIR"

# extract cco manifests
oc adm release extract \
  --credentials-requests \
  --cloud=gcp \
  --to="$CCO_DIR"/cred-reqs \
  "$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE" 2>&1 | tee "$CLUSTER_NAME".log

# create cloud accounts and secrets
./ccoctl gcp create-all \
  --name="$CLUSTER_NAME" \
  --region="$GCP_REGION" \
  --project="$GCP_PROJECT" \
  --credentials-requests-dir="$CCO_DIR"/cred-reqs \
  --output-dir="$CCO_DIR"/output 2>&1 | tee -a "$CLUSTER_NAME".log

# install-config
cat << EOF > "$CLUSTER_NAME"/install-config.yaml
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
  gcp:
    projectID: ${GCP_PROJECT}
    region: ${GCP_REGION}
publish: External
pullSecret: '${PULL_SECRET}'
# optional - add ssh key for VMs
sshKey: |
  $(cat ~/.ssh/google_compute_engine.pub)
EOF

./openshift-install create manifests --dir "$CLUSTER_NAME" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log
read -r -n 1 -p "Manifests have been created, press any key to continue to cluster creation step... "

# copy ccoctl generated manifests and tls certs
cp -v "$CCO_DIR"/output/manifests/* "$CLUSTER_NAME"/manifests/
cp -av "$CCO_DIR"/output/tls "$CLUSTER_NAME"

./openshift-install create cluster --dir "$CLUSTER_NAME" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log

# after cluster creation succeeds copy kubeconfig to ~/.kube/config
cp -f "$CLUSTER_NAME"/auth/kubeconfig ~/.kube/config
