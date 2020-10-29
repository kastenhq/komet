#!/usr/bin/env bash

# COLOR CONSTANTS
GREEN='\033[0;32m'
LIGHT_BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

readonly -a REQUIRED_TOOLS=(
    kubectl
)

DEFAULT_IMAGE_TAG="latest"
DEFAULT_JOB_NAME="kubestr"

helpFunction()
{
   echo ""
   echo "This scripts runs Kubestr as a Job in a cluster"
   echo "Usage: $0 -i image -n namespace"
   echo -e "\t-i The Kubestr image"
   echo -e "\t-n The kubernetes namespace where the job will run"
   echo -e "\t-s The storageclass to run the fio test against"
   echo -e "\t-z The size of volume to run the fio test against"
   echo -e "\t-f An FIO file to run the fio test against"
   exit 1 # Exit script after printing help
}

while getopts "i:n:s:z:f:" opt
do
   case "$opt" in
      i ) image="$OPTARG" ;;
      n ) namespace="$OPTARG" ;;
      s ) storageclass="$OPTARG" ;;
      z ) size="$OPTARG" ;;
      f ) file="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

if [ -z "$namespace" ]
then
   echo "Namespace option not provided, using default namespace";
   namespace="default"
fi

if [ -z "$storageclass" ]
then
    echo "storageclass is needed"
    exit 1
fi

print_heading() {
    printf "${LIGHT_BLUE}$1${NC}\n"
}

print_error(){
    printf "${RED}$1${NC}\n"
}

print_success(){
    printf "${GREEN}$1${NC}\n"
}

check_tools() {
  print_heading "Checking for tools"
  for tool in "${REQUIRED_TOOLS[@]}"
  do
    if ! command -v "${tool}" > /dev/null 2>&1
    then
      print_error " --> Unable to find ${tool}"
      failed=1
    else
      print_success " --> Found ${tool}"
    fi
  done
}

check_kubectl_access() {
  print_heading "Checking access to the Kubernetes context $(kubectl config current-context)"
  if [[ $(kubectl get ns ${namespace}) ]]; then
    print_success " --> Able to access the ${namespace} Kubernetes namespace"
  else
    print_error " --> Unable to access the ${namespace} Kubernetes namespace"
    failed=1
  fi
}

check_image() {
  print_heading "Kubestr image"
  if [ -z "$image" ]
  then
      # need to change this to public dockerhub
      image=ghcr.io/kastenhq/kubestr:${DEFAULT_IMAGE_TAG}
  fi
  print_success " --> ${image}"
}

failed=0
check_tools && check_image && check_kubectl_access
if [[ ${failed} != 0 ]]; then
    print_error "Pre-checks failed"
    exit 1
fi

additional_cm_cmd=""
if [ -n "$file" ]
then
  additional_cm_cmd="${additional_cm_cmd} --from-file=${file}"
fi

if [ -n "$size" ]
then
  additional_cm_cmd="${additional_cm_cmd} --from-literal=pvcsize=${size}"
fi

if [ -n "$storageclass" ]
then
  additional_cm_cmd="${additional_cm_cmd} --from-literal=storageclass=${storageclass}"
fi


kubectl create configmap --namespace ${namespace} fio-config ${additional_cm_cmd}
kubectl label  configmap --namespace ${namespace} fio-config createdbyfio=true

printf "\n"
print_heading "Running Kubestr Job in ${namespace} namspace"
cat > kubestr.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${DEFAULT_JOB_NAME}
  namespace: ${namespace}
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: ${DEFAULT_JOB_NAME}
subjects:
  - kind: ServiceAccount
    name: ${DEFAULT_JOB_NAME}
    namespace: ${namespace}
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: batch/v1
kind: Job
metadata:
  name: ${DEFAULT_JOB_NAME}
  namespace: ${namespace}
spec:
  template:
    spec:
      containers:
      - image: ${image}
        imagePullPolicy: Always
        name: ${DEFAULT_JOB_NAME}
        command: [ "/kubestr" ]
        args: ["fio", "-c", "fio-config"]
        env:
          - name: POD_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
      restartPolicy: Never
      serviceAccount: ${DEFAULT_JOB_NAME}
  backoffLimit: 4
EOF

kubectl apply -f kubestr.yaml

trap "kubectl delete -f kubestr.yaml" EXIT

while [[ $(kubectl -n ${namespace} get pods --selector=job-name=${DEFAULT_JOB_NAME} -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" && $(kubectl -n ${namespace} get pods --selector=job-name=${DEFAULT_JOB_NAME} -o 'jsonpath={..phase}') != "Succeeded" ]];
do echo "Waiting for pod $(kubectl -n ${namespace} get pods --selector=job-name=${DEFAULT_JOB_NAME} --output=jsonpath='{.items[*].metadata.name}') to be ready - $(kubectl -n ${namespace} get pods --selector=job-name=${DEFAULT_JOB_NAME} -o 'jsonpath={..status.containerStatuses[0].state.waiting.reason}')" && sleep 1;
done
echo "Pod Ready!"
echo ""
pod=$(kubectl -n ${namespace} get pods --selector=job-name=${DEFAULT_JOB_NAME} --output=jsonpath='{.items[*].metadata.name}')
kubectl logs -n ${namespace} ${pod} -f
echo ""
