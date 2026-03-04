#!/bin/bash

# exit when any command fails
set -e

if [ $# == 0 ]; then
  CLUSTER="dev"
else
  CLUSTER="$1"
fi


# switch to correct cluster
if [ "$CLUSTER" = "resicore-ai" ]; then
  kubectl config use-context microk8s
  VALUES_FILE="values-jupyterhub-resicore-ai.yaml"
  CHART_VERSION="--version 3.3.8"
else
  kubectl config use-context incore-${CLUSTER}
  VALUES_FILE="values-jupyterhub-${CLUSTER}.yaml"
  CHART_VERSION=""
fi

# deploy
helm upgrade jupyterhub jupyterhub/jupyterhub --namespace incore -f ${VALUES_FILE} ${CHART_VERSION}
