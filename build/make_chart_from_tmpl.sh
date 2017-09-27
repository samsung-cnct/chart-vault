#!/bin/sh


CHART_VER="$(git describe --tags --abbrev=0 | sed 's/^v//')"
CHART_REL="$(git rev-list --count v${CHART_VER}..HEAD)"

envsubst < build/Chart.yaml.in > Chart.yaml
