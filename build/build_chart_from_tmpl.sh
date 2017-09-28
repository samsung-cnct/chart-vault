#!/bin/sh

[[ -n "$1" ]] && chart_path=$1 || \
  {
    echo >&2 "Chart path was not specified to build script. Usage: $0 directory_path"
    exit 2
  }

echo "The following tags exist: "
git tag --list

echo "Chart path is: $chart_path"

CHART_VER=$(git describe --tags --abbrev=0 | sed 's/^v//') 
CHART_REL=$(git rev-list --count v${CHART_VER}..HEAD)

envsubst < build/Chart.yaml.in > ${chart_path}/Chart.yaml

echo "Chart.yaml is: ${chart_path}/Chart.yaml and contains:" 
cat ${chart_path}/Chart.yaml
