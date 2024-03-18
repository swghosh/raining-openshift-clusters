#!/usr/bin/bash
set -euo pipefail

# override release image with custom release and create the cluster from supplied install-config
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:-"quay.io/openshift-release-dev/ocp-release:4.15.3-x86_64"}
# gcp project and region
GCP_PROJECT=${GCP_PROJECT:-"devel"}
GCP_REGION=${GCP_REGION:-"asia-south1"}
# base domain with public zone in Google Cloud DNS
BASE_DOMAIN=${BASE_DOMAIN:-"openshift.codecrafts.cf"}
# path to file containing pull secrets
PULL_SECRET_PATH=${PULL_SECRET_PATH:-"$HOME/.docker/config.json"}

# --------------------

# generate a cluster name with username, date and 8 random hex
CLUSTER_NAME=$(whoami)-$(date +"%Y%m%d")-$(echo $RANDOM | md5sum | head -c 8)
export CLUSTER_NAME

# create an install-config in a directory
CLUSTER_DIR="clusters/$CLUSTER_NAME"
mkdir -p "$CLUSTER_DIR"

# create directory for cloud credentials ccoctl
CCO_DIR=clusters/cco-"$CLUSTER_NAME"
mkdir "$CCO_DIR"

# create a gcp service account for use by ccoctl and assign necessary roles
gcloud iam service-accounts create "${CLUSTER_NAME}" --display-name="${CLUSTER_NAME}" --project "${GCP_PROJECT}"

SA_EMAIL="${CLUSTER_NAME}""@""${GCP_PROJECT}"".iam.gserviceaccount.com"

while IFS= read -r ROLE_TO_ADD ; do
   gcloud projects add-iam-policy-binding "${GCP_PROJECT}" --member="serviceAccount:${SA_EMAIL}" --role="$ROLE_TO_ADD"
done << END_OF_ROLES
roles/owner
END_OF_ROLES

gcloud iam service-accounts keys create "serviceaccount-${CLUSTER_NAME}.json" --iam-account="${SA_EMAIL}"

# provide path to gcloud service account file
GOOGLE_APPLICATION_CREDENTIALS=$(pwd)"/serviceaccount-${CLUSTER_NAME}.json"
export GOOGLE_APPLICATION_CREDENTIALS

oc adm release extract --command='openshift-install' ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}
oc adm release extract --command='ccoctl' ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}

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

# get pull secrets
PULL_SECRET=$(python3 json-minify.py "$PULL_SECRET_PATH")

# install-config
cat << EOF > "${CLUSTER_DIR}"/install-config.yaml
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

./openshift-install create manifests --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log
read -r -n 1 -p "Manifests have been created, press any key to continue to cluster creation step... "

# copy ccoctl generated manifests and tls certs
cp -v "$CCO_DIR"/output/manifests/* "${CLUSTER_DIR}"/manifests/
cp -av "$CCO_DIR"/output/tls "${CLUSTER_DIR}"

./openshift-install create cluster --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log

# after cluster creation succeeds copy kubeconfig to ~/.kube/config
cp -f "${CLUSTER_DIR}"/auth/kubeconfig ~/.kube/config
