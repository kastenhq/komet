#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

CLEANSED_STR=""
cleanse_str() {
  case "$1" in
    "org.democratic-csi.[X]") CLEANSED_STR="org.democratic-csi" ;;
    "[x].ember-csi.io") CLEANSED_STR="ember-csi.io" ;;
    *) CLEANSED_STR="$1"
  esac
}

current_directory=$(dirname "$0")
curl https://raw.githubusercontent.com/kubernetes-csi/docs/master/book/src/drivers.md -o ${current_directory}/../extra/csi-drivers

cat <<EOT >> ${current_directory}/../extra/csi-drivers-temp.go
package kubestr

// THIS FILE IS AUTO_GENERATED.
// To generate file run "go generate" at the top level
// This file must be checked in.

EOT


echo "var CSIDriverList = []*CSIDriver{" >> ${current_directory}/../extra/csi-drivers-temp.go
while read p; do
  if [[ $p == [* ]]; then
    IFS='|'
    read -a fields <<< "$p"
    if [[ ${#fields[@]} -ne 8 ]]; then
      continue
    fi

    name_url=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<${fields[0]})
    driver_name=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<${fields[1]} | sed 's/`//g')
    versions=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<${fields[2]})
    description=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<${fields[3]})
    persistence=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<${fields[4]})
    access_modes=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<${fields[5]}| sed 's/"//g')
    dynamic_provisioning=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<${fields[6]})
    features=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<${fields[7]})

    cleanse_str "${driver_name}"
    driver_name="${CLEANSED_STR}"

    echo "{NameUrl: \"$name_url\", DriverName: \"$driver_name\", Versions: \"$versions\", Description: \"$description\", Persistence: \"$persistence\", AccessModes: \"$access_modes\", DynamicProvisioning: \"$dynamic_provisioning\", Features: \"$features\"}," >> ${current_directory}/../extra/csi-drivers-temp.go
  fi
done <${current_directory}/../extra/csi-drivers
echo "}" >> ${current_directory}/../extra/csi-drivers-temp.go

gofmt ${current_directory}/../extra/csi-drivers-temp.go > ${current_directory}/../pkg/kubestr/csi-drivers.go
rm ${current_directory}/../extra/csi-drivers-temp.go
