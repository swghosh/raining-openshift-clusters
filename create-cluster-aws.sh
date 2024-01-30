#!/usr/bin/bash

# override release image with custom release and create the cluster from supplied install-config
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/openshift-release-dev/ocp-release:4.16.0-ec.1-x86_64

# generate a cluster name with username, date and 8 random hex
CLUSTER_NAME=$(whoami)-$(date +"%Y%m%d")-$(echo $RANDOM | md5sum | head -c 8)
export CLUSTER_NAME

AWS_REGION=ap-south-1

# get pull secrets
PULL_SECRET_PATH=~/.docker/config.json
PULL_SECRET=$(python3 json-minify.py $PULL_SECRET_PATH)

# create an install-config in a directory
CLUSTER_DIR="clusters/$CLUSTER_NAME"
mkdir -p "$CLUSTER_DIR"

cat << EOF > "$CLUSTER_DIR"/install-config.yaml
apiVersion: v1
baseDomain: devcluster.openshift.com
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

# openshift-install
installer_image="$(podman run --rm "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}" image installer)"
tmp_dir=$(mktemp -d)
podman run --entrypoint sh -u root --rm -v "${tmp_dir}:/workdir:Z" "${installer_image}" -c "cp -rvf /bin/openshift-install /workdir"

"${tmp_dir}/openshift-install" create manifests --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee "$CLUSTER_NAME".log
read -r -n 1 -p "Manifests have been created, press any key to continue to cluster creation step... "
"${tmp_dir}/openshift-install" create cluster --dir "${CLUSTER_DIR}" --log-level debug 2>&1 | tee -a "$CLUSTER_NAME".log

# after cluster creation succeeds copy kubeconfig to ~/.kube/config
cp -f "$CLUSTER_DIR"/auth/kubeconfig ~/.kube/config
