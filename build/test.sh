#!/bin/sh

cat $APP_NAME/Chart.yaml
echo "namespace for this build is: $NAMESPACE"
helm lint ${APP_NAME} || exit $?
helm install --name ${RELEASE} --namespace ${NAMESPACE} ${APP_NAME}
kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE}
helm delete --purge ${RELEASE}
kubectl delete namespace ${NAMESPACE}

