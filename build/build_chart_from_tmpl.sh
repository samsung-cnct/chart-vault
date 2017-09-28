#!/bin/sh

echo "The following tags exist: "
git tag --list

CHART_VER=$(git describe --tags --abbrev=0 | sed 's/^v//') 
CHART_REL=$(git rev-list --count v${CHART_VER}..HEAD)

envsubst < build/Chart.yaml.in > ${chart_name}/Chart.yaml

echo "Chart.yaml is: ${chart_name}/Chart.yaml and contains:" 
cat ${chart_name}/Chart.yaml
