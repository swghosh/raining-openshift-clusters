#!/usr/bin/bash

# override release image with custom release and create the cluster from supplied install-config
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:-"quay.io/openshift-release-dev/ocp-release:4.15.3-x86_64"}
AWS_REGION=${AWS_REGION:-"ap-south-1"}
# base domain for cluster creation, must be route53 dns zone
BASE_DOMAIN=${BASE_DOMAIN:-"openshift.codecrafts.cf"}
# path to file containing pull secrets
PULL_SECRET_PATH=${PULL_SECRET_PATH:-"$HOME/.docker/config.json"}

# --------------------

# generate a cluster name with username, date and 8 random hex
CLUSTER_NAME=$(whoami)-$(date +"%Y%m%d")-$(echo $RANDOM | md5sum | head -c 8)
export CLUSTER_NAME

# get pull secrets
PULL_SECRET=$(python3 json-minify.py "$PULL_SECRET_PATH")

# create an install-config in a directory
CLUSTER_DIR="clusters/$CLUSTER_NAME"
mkdir -p "$CLUSTER_DIR"

oc adm release extract --command='openshift-install' ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}

cat << EOF > "$CLUSTER_DIR"/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
# featureSet: "TechPreviewNoUpgrade"
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
  # networkType: OpenShiftSDN
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ${AWS_REGION}
publish: External
pullSecret: '${PULL_SECRET}'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

./openshift-install create manifests --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee "$CLUSTER_NAME".log
read -r -n 1 -p "Manifests have been created, press any key to continue to cluster creation step... "
./openshift-install create cluster --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log

# after cluster creation succeeds copy kubeconfig to ~/.kube/config
cp -f "$CLUSTER_DIR"/auth/kubeconfig ~/.kube/config
