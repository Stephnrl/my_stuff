kubectl get pod -n <test-namespace> <test-pod-name> -o jsonpath='hostNetwork={.spec.hostNetwork} dnsPolicy={.spec.dnsPolicy} node={.spec.nodeName} serviceAccount={.spec.serviceAccountName}{"\n"}'
