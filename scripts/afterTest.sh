#! /usr/local/bin/bash -ex
# clean up the namespace
echo "Cleaning up namespace ${PIPELINE_TEST_NAMESPACE}"
kubectl delete namespace ${PIPELINE_TEST_NAMESPACE} || true