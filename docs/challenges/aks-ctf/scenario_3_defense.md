# The calls are coming from inside the container! Scenario 3 Defense

We've gotten paged.  AGAIN!  Let's check the cluster.

Any unwanted open ports?  
```console
kubectl get service -A
``` 

Any unwanted pods? 
```console
kubectl get pods -A
```

Where's the spike coming from? 
```console
kubectl top node
```

What pods?  
```console
kubectl top pod -A
```

Wait...what is this `bitcoin-injector`?  It's showing as completed, so it's not running anymore, so it can't be causing the problem. Did the hackers get sloppy and leave something behind?  We'll check this out later because we need to stop the bleeding.

Why is our app running so hot?
```
kubectl get pods -n dev
POD=$(kubectl get pod -n dev -l=app=insecure-app -o json | jq '.items[0].metadata.name' -r)
echo $POD
kubectl exec -it $POD -n dev -- ps -ef
```

There's a foreign workload `moneymoneymoney` running in our app!  How did this get in here?!

Let's delete the pod: 
```console
kubectl delete pod -n dev --force --grace-period=0 $POD
```

But just to be sure, let's verify that process is gone.

```
POD=$(kubectl get pod -n dev -l=app=insecure-app -o json | jq '.items[0].metadata.name' -r)
kubectl exec -it $POD -n dev -- ps -ef
```

This...is not good.  The miner is running inside the app and restarting the app also restarted the miner.  Is our app infected?!  How could this have happened?!

Let's go re-investigate that `bitcoin-injector` pod:
```
kubectl describe pods -n dev -l job-name=bitcoin-injector
```

Looks like it was started as Job/bitcoin-injector.

```console
kubectl logs -n dev -l job-name=bitcoin-injector
```

Looks like the output of a Docker build command...

It seems like they got our container registry credentials and then used that to push a new one with the exact same name!  But how did they get that?

Let's look at the Log Analytics Audit Logs:
```kql
AKSAuditAdmin
| where RequestUri startswith "/apis/batch"
    and Verb == "create" 
| project ObjectRef, User, SourceIps, UserAgent, TimeGenerated
```

It appears that the request came from `insecure-app`.  But how?

Looking at the source code, it appears there's an `/admin` page which Frank added this to the code years ago and was fired after that "inappropriate use of company resources" issue.

And the attackers were able to use this really permissive Service Account role binding to get escalated privledges to the cluster.

We need a plan of defense:

* Remove the infected image
* Stop using container registry admin credentials
* Enable Defender for Containers 
* Downgrade/remove SA permissions (change verbs from * to GET)
* Open Issue to tell developer to remove /admin page
* Re-build and deploy image

## Remove the infected image

Let's start by reverting the app deployment to the last known good image. Start by inspecting the image reference in the deployment manifest:
```console
kubectl get deployment insecure-app -n dev -o=jsonpath='{.spec.template.spec.containers[*].image}'
```

The app team deployed by referencing the `latest` tag for their container image. This exposes their deployment to exploits like the one we just discovered. Let's update their deployment to reference a more specific tag ('1.0'):
```
kubectl set image deployment/insecure-app -n dev insecure-app=$ACR_NAME.azurecr.io/insecure-app:1.0
```

Updating the image on the deployment also has the side-effect of killing all pods currently running the infected image and relaunching them using the updated image tag.

Now let's remove the infected image from the registry:
```
az acr repository delete -n $ACR_NAME -t insecure-app:latest -y
```

Finally, since the infected insecure-app and bitcoinero images are still cached locally on the node, we need to make sure those are removed to prevent another container from starting up with the old images. Let's install the [AKS Image Cleaner](https://learn.microsoft.com/en-us/azure/aks/image-cleaner).  This will ensure that unused images (such as the infected insecure-app and bitcoinero) are cleared from the node.
```
az aks update --name $AKS_NAME --resource-group $RESOURCE_GROUP  --enable-image-cleaner
```

## Stop using container registry admin credentials

Instead of providing the ACR admin credentials, let's [Attach the ACR to the cluster](https://learn.microsoft.com/en-us/azure/aks/cluster-container-registry-integration?tabs=azure-cli#attach-an-acr-to-an-existing-aks-cluster).

```
kubectl delete -n dev secrets/acr-secret
az aks update --name $AKS_NAME --resource-group $RESOURCE_GROUP --attach-acr $ACR_NAME
```

## Enable Defender for Containers

Now that you've fixed the permissions on pulling images from ACR, you want to get alerted in case anything else gets added to our registry or the cluster.  

For this, we could enable [Azure Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-enable)

The image injection would have been detected with [Binary drift detection](https://learn.microsoft.com/en-us/azure/defender-for-cloud/binary-drift-detection).  

The binary drift detection feature alerts you when there's a difference between the workload that came from the image, and the workload running in the container. It alerts you about potential security threats by detecting unauthorized external processes within containers.

## Fix container permissions

Let's look at the problematic cluster role:

```console
kubectl describe clusterroles insecure-app-role
```

This shows that that this role was able to perform all "verbs" on all "resources" inside the cluster.  That is WAY too permissive!

We got confirmation from the developer that the app needs to be able to see (but not modify) other pods in the namespace.  

Instead of a "clusterrole" (which has access to the entire cluster), we should use a "role" (which has access to the specific namespace).

Let's delete the clusterrole and clusterolebinding and update the role to be less permissive:

```console
kubectl delete clusterrolebinding insecure-app-binding
kubectl delete clusterrole insecure-app-role
kubectl create role pod-reader --verb=get --verb=list --verb=watch --resource=pods
kubectl create rolebinding pod-reader-binding --role=pod-reader --serviceaccount=dev:insecure-app-sa
```

And with that, we can now rest.

Hopefully...