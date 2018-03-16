#! /bin/sh -ex

# output any helm test logs if present
kubectl get pod -o "custom-columns=NAME:.metadata.name" \
  --show-all \
  -l "release=${RELEASE},app=smoke-test" \
  -n ${NAMESPACE} \
  --no-headers | while read pod; do echo "${pod} Test Logs:"; echo; kubectl logs ${pod} -n ${NAMESPACE}; echo; done

# clean up
echo "Cleaning up"
helm delete --purge ${RELEASE} || true
kubectl delete namespace ${NAMESPACE} || true