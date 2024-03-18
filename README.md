# OpenShift Cluster Creation Scripts 

This repo contains bash scripts to help automate creation of OpenShift clusters across cloud providers. (Note: it has functionality very similar to that of [Cluster Bot](https://github.com/openshift/ci-chat-bot) except it can just run out of the box to help create [IPI (installer-provisioned-infrastructure) clusters](https://docs.openshift.com/container-platform/4.13/installing/installing-preparing.html)).

**Pre-requisites**:
- `oc` cli installed and available in `$PATH`
- `podman`
- `ccoctl` binary available in current directory (this is only needed if you plan to use `*-sts.sh` scripts)
- cloud provider cli setup with necessary authentication for eg. AWS credentials available to be inferred from current environment or GCP credentials gcloud default auth setup
- necessary cloud provider quota required for spinning up cluster resources for OpenShift
- `~/.docker/config.json` file on your system to contain the necessary pull secrets required for cluster creation
- either `~/.ssh/google_compute_engine.pub` (for GCP) or `~/.ssh/id_rsa.pub` (for AWS, Azure) to be present on your system

You can download all these binaries either from: https://console.redhat.com/openshift/downloads or from our CI: https://amd64.ocp.releases.ci.openshift.org/

Before running each of the `.sh` scripts consider taking a look over the initial block of code in the script which contains values for certain environment variables. They have been filled with default values (yet wont work out of the box), but you would need to change them on the basis of your cloud provider resource names eg. cloud project, cloud region, base domain, etc.

# Amazon Web Services (AWS)

- `./create-cluster-aws.sh`: create an IPI provisioned OpenShift cluster on AWS
- `./create-cluster-aws-sts.sh`: create an IPI provisioned OpenShift cluster on [AWS with STS authentication through Manual mode cloud credentials](https://docs.openshift.com/container-platform/latest/authentication/managing_cloud_provider_credentials/cco-mode-sts.html).

# Google Cloud Platform (GCP)

- `./create-cluster-gcp.sh`: create an IPI provisioned OpenShift cluster on GCP
- `./create-cluster-gcp-sts.sh`: create an IPI provisioned OpenShift cluster on [GCP with Google Workload Identity through Manual mode cloud credentials](https://docs.openshift.com/container-platform/latest/authentication/managing_cloud_provider_credentials/cco-mode-gcp-workload-identity.html#cco-ccoctl-upgrading_wif-mode-upgrading)

# Microsoft Azure

- `./create-cluster-az.sh`: create an IPI provisioned OpenShift cluster on Azure public cloud
- `./create-cluster-az-sts.sh`: create an IPI provisioned OpenShift cluster on [Azure with short-term credentials with Active Directory (AD) Workload Identity](https://docs.openshift.com/container-platform/4.15/installing/installing_azure/installing-azure-customizations.html#installing-azure-with-short-term-creds_installing-azure-customizations)

# Cleanup

All the clusters created using this script will have a prefix that is determined by running `whoami` from the shell. At the time of destroying the clusters, be mindful to use the same username or the cleanup won't work the way as desired. `./destroy-clusters.sh N` will attempt cleanup (a.k.a `openshift-install destroy cluster`) of all but the last `N` clusters. If the value of `N` is omitted, the script will attempt to cleanup all the clusters from the directories that can it can find.

**Additional references**:

1. https://docs.openshift.com/container-platform/latest/installing/index.html
2. https://github.com/openshift/installer/blob/master/docs/user/overview.md
3. https://github.com/openshift/cloud-credential-operator/blob/master/docs/ccoctl.md
