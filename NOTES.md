# Kubernetes Notes

## Minikube (local cluster)

| Command | What it does |
|---|---|
| `minikube start` | Start the cluster, or create it the first time. Reuses the existing cluster and keeps its data. |
| `minikube stop` | Stop the cluster to free CPU and RAM. State is kept. |
| `minikube status` | Show whether host, kubelet and apiserver are running. |
| `minikube delete` | Destroy the cluster completely. ⚠️ Everything in it is lost. |

- Minikube does **not** start again on its own after a reboot or after Docker restarts.
- The minikube "node" is really a Docker container named `minikube` (check it with `docker ps -a`).

## kubectl basics

| Command | What it does |
|---|---|
| `kubectl get nodes` | List the cluster's nodes. A good first check that the cluster is reachable. |
| `kubectl run <name> --image=<img>` | Create a single Pod from an image, e.g. `kubectl run nginx-pod --image=nginx`. |
| `kubectl get pods` | List Pods in the current namespace. |
| `kubectl get pod <name> -o wide` | Show more detail: Pod IP and the node it runs on. |
| `kubectl describe pod <name>` | Full detail plus an **Events** list at the bottom. The first place to look when a Pod isn't Running (pull errors, scheduling, crashes). |
| `kubectl logs <pod>` | Show the container's stdout/stderr. Add `--previous` for the last crashed run. |
| `kubectl rollout status deployment/<name>` | Wait for a Deployment's new Pods to become ready. |
| `kubectl wait --for=condition=Ready pod/<name> --timeout=120s` | Block until the Pod is ready. |

## Services (exposing Pods)

| Command | What it does |
|---|---|
| `kubectl expose pod <pod> --type=NodePort --port=80` | Create a Service that points at the pod. |
| `kubectl get svc` | List Services, with their type, ClusterIP and ports. |
| `kubectl get endpoints <svc>` | Show which Pod IPs a Service actually sends traffic to. `<none>` means its selector matches no pods. |
| `minikube ip` | Print the node IP (`192.168.49.2`). |
| `minikube service <svc> --url` | Print a URL you can curl from your laptop. |
| `minikube tunnel` | Run in a separate terminal so LoadBalancer services get an EXTERNAL-IP. |

**Service types and how to reach them from your laptop:**
- **ClusterIP** (e.g. `10.108.45.97`): works **only inside the cluster**. Curling it from the host hangs.
- **NodePort**: opens a port (30000–32767) on the node. Reach it at `<node-ip>:<nodePort>`, e.g. `curl 192.168.49.2:32194`. In `PORT(S)`, `80:32194/TCP` means service port 80 maps to node port 32194. If you don't set `nodePort`, Kubernetes **picks a random free one** from 30000–32767 (the default range, set by the API server flag `--service-node-port-range`). To pin it, add `nodePort: 30080` under `ports:`. It stays the same until the Service is deleted.
- **LoadBalancer**: needs a cloud provider to assign an external IP. It stays `<pending>` on minikube until you run `minikube tunnel`.

**Selectors:** a Service finds its Pods through **labels**. `kubectl run nginx-pod` labels the pod `run=nginx-pod`, so a Service with the selector `app=nginx` matches nothing. Check labels with `kubectl get pods --show-labels`.

## Running your own image

Flow: `Dockerfile` → build the image → **get it into the cluster** → Deployment (+ Service if it must be reachable).

| Command | What it does |
|---|---|
| `minikube image build -t hello:v1 .` | Build the image straight into minikube's containerd. |
| `minikube image load hello:v1` | Copy an image you built with `docker build` into minikube. |
| `minikube image ls` | List the images the cluster can see. |

- **minikube has its own image store** (containerd inside the node). An image in your host `docker images` is invisible to the cluster until you load it there or push it to a registry.
- **Use a real tag, not `latest`.** With `:latest` (or no tag) `imagePullPolicy` defaults to `Always`, so k8s ignores the local image and tries Docker Hub. Use `hello:v1`, or set `imagePullPolicy: IfNotPresent`.
- **Bump the tag on every rebuild** (`v1` → `v2`). Rebuilding the same tag leaves running Pods on the old image, and `kubectl apply` sees no change, so no rollout happens.
- **Bind to `0.0.0.0`, not `127.0.0.1`.** Flask's `app.run()` defaults to `127.0.0.1:5000`, so use `app.run(host="0.0.0.0", port=5000)`. Traffic arrives on the Pod's IP. An app listening only on localhost inside the container is unreachable from a Service.
- **Ports chain:** Service `port` (ClusterIP) → `targetPort` (the port the app listens on in the container) → `containerPort` in the Deployment (documentation, like `EXPOSE`). `nodePort` is the outer port on the node.
- **Deployments are for long-running processes.** A script that prints and exits gets restarted forever. For run-once tasks use a **Job**. For a Deployment, the app must keep running (e.g. a web server).

## Cleaning up

| Command | What it does |
|---|---|
| `kubectl get all` | List pods, services, deployments, replicasets and HPAs in the namespace. |
| `kubectl delete pod <name>` | Delete one pod. Add `--now` to skip most of the 30s graceful shutdown. |
| `kubectl delete svc <a> <b>` | Delete several resources of the same type in one command. |
| `kubectl delete pods,svc,deployments,hpa --all` | Delete everything of those types in the current namespace. |
| `minikube delete && minikube start` | Wipe the whole cluster and start fresh. |

- **Deleting a pod owned by a Deployment doesn't work.** The Deployment recreates the pod right away, so delete the **Deployment** instead. A pod from `kubectl run` is standalone and stays deleted.
- `service/kubernetes` in `default` is built in (it's the API server). It's recreated automatically if deleted.

## Concepts

- **Pod**: the smallest deployable unit in Kubernetes. It holds one or more containers that share a network IP and storage. Each Pod gets its own cluster-internal IP (e.g. `10.244.0.3`).
- **Node**: a machine (VM or container) that runs Pods. Minikube runs a single node that is also the control plane.
- **Run vs. reach:** a **Pod** runs the image, a **Deployment** keeps N Pods alive (recreates and updates them), and a **Service** gives them a stable IP/DNS name and load-balances across them. Pod IPs change every time a Pod is recreated, so don't rely on them.
- **Ways to reach a Pod:** Service (the normal way), `kubectl port-forward pod/<name> 8080:80` (quick debugging from your laptop, no Service needed), or the Pod IP directly from inside the cluster (temporary).
- **Test from inside the cluster** with a throwaway pod: `kubectl run tmp --rm -i --restart=Never --image=busybox -- wget -qO- http://hello-service`. `--rm` deletes it afterwards.
- **Service DNS:** inside the cluster, a Service is reachable by name, e.g. `curl http://nginx-service` (or `nginx-service.default.svc.cluster.local`).
- **`apiVersion` = `<group>/<version>`.** The API is split into **groups**. The original **core** group has no name, so its kinds are just `v1` (Pod, Service, ConfigMap, Secret, Namespace). Kinds added later live in named groups: `apps/v1` (Deployment, ReplicaSet), `batch/v1` (Job, CronJob), `autoscaling/v2` (HPA), `networking.k8s.io/v1` (Ingress). Versions mature `v1alpha1` → `v1beta1` → `v1`. Look one up with `kubectl api-resources` (APIVERSION column), or `kubectl explain <kind>`.
- **Control plane / API server**: the "brain" of the cluster. `kubectl` sends every command to the API server, which here is `https://192.168.49.2:8443`.

## Troubleshooting

### `dial tcp 192.168.49.2:8443: connect: no route to host`
- **Cause:** the cluster is stopped, so nothing is listening at the API server address.
- **Fix:** run `minikube status` to confirm it's stopped, then `minikube start`.

### `curl <CLUSTER-IP>` hangs forever
- **Cause:** a ClusterIP is a virtual IP that's only routable inside the cluster.
- **Fix:** use the NodePort with the node IP (`curl $(minikube ip):<nodePort>`), or `minikube service <svc> --url`.
- **Or:** run `minikube tunnel`. It adds a host route `10.96.0.0/12 -> 192.168.49.2`, so ClusterIPs become reachable from your laptop (check with `ip route | grep 10.96`).
- **Gotcha — match IP and port:** `80:30878/TCP` means ClusterIP listens on **80**, node listens on **30878**. So `curl <node-ip>:30878` or `curl <cluster-ip>:80`. Never `curl <cluster-ip>:30878`.

### `curl <node-ip>` → `Failed to connect to 192.168.49.2:80`
- **Cause:** nothing listens on port 80 of the node. Only a NodePort Service opens a port there (30000–32767), and `EXPOSE` in a Dockerfile opens nothing.
- **Fix:** create a Service, then curl `<node-ip>:<nodePort>`. The app also has to actually listen on a port.

### LoadBalancer EXTERNAL-IP stuck at `<pending>`
- **Cause:** minikube has no cloud load balancer.
- **Fix:** run `minikube tunnel` in another terminal and keep it open.

### Service has no endpoints (`kubectl get endpoints` shows `<none>`)
- **Cause:** the Service's selector doesn't match any pod's labels.
- **Fix:** compare `kubectl get svc <svc> -o yaml` (the selector) with `kubectl get pods --show-labels`.

### Pod in `ErrImagePull` / `ImagePullBackOff` for a local image
- **Cause:** the image isn't in minikube's store, or its tag is `latest` so k8s tries to pull it from Docker Hub.
- **Fix:** `minikube image load <img>:<tag>` and use a non-`latest` tag (or `imagePullPolicy: IfNotPresent`).
- **Spot it:** `kubectl describe pod` shows `failed to pull ... "docker.io/library/hello:latest"`. The `:latest` in that message means the manifest had no tag. Building `hello:v1` but writing `image: hello` is enough to cause this.

### Still `ImagePullBackOff` after fixing the tag, though `minikube image ls` shows the image
- **Cause:** the Deployment was first created with `image: hello` (= `latest`), so Kubernetes **stored** `imagePullPolicy: Always` in it. Changing the image to `hello:v2` later doesn't reset it, because `apply` only changes fields you write. Kubernetes keeps going to Docker Hub.
- **Spot it:** `kubectl get deploy <name> -o yaml | grep -i pullpolicy`.
- **Fix:** write `imagePullPolicy: IfNotPresent` explicitly in the container spec, or delete and recreate the Deployment.

### `no matches for kind "Service" in version "apps/v1"`
- **Cause:** wrong `apiVersion`. Each kind belongs to an API group: Deployment → `apps/v1`, Service/Pod/ConfigMap → `v1`.
- **Fix:** `apiVersion: v1`. Look one up with `kubectl api-resources | grep -i <kind>`.

### Pod in `CrashLoopBackOff` but the logs look fine
- **Cause:** the container exits (even successfully), and a Deployment always restarts it, backing off longer each time.
- **Fix:** check `kubectl logs <pod>`. If it's a one-shot script, run it as a Job. Otherwise, make the process keep running.

## Session log

- **2026-10-14**: Started minikube again after it had been stopped for 3 weeks. Created the first Pod, `nginx-pod`, with `kubectl run`.
- **2026-10-14**: Exposed `nginx-pod` as a NodePort Service. Learned why curling a ClusterIP hangs, plus the NodePort, LoadBalancer and `minikube tunnel` basics, and how selectors and endpoints link a Service to its Pods.
- **2026-10-14**: Learned how to clean up resources with `kubectl delete`, `--all` and `minikube delete`, and that a pod owned by a Deployment gets recreated when deleted.
- **2026-10-14**: Applied `deployment.yaml` + `service.yaml` (3 nginx replicas, NodePort). Learned why ClusterIP needs `minikube tunnel` (host route) and not to mix ClusterIP with the nodePort.
- **2026-10-14**: Pod vs Deployment vs Service: what runs the image vs. what makes it reachable; `kubectl port-forward` as a no-Service shortcut.
- **2026-10-14**: Running your own Python image: load it into minikube, avoid the `latest` tag, and use a Job (not a Deployment) for scripts that exit.
- **2026-10-14**: Deployed own image `hello:v1` → `ImagePullBackOff` because the manifest said `image: hello` (= `:latest`, pulled from Docker Hub). Learned `kubectl describe pod` and that `EXPOSE` doesn't publish anything.
- **2026-10-14**: Steps to make `hello` reachable: stdlib HTTP server bound to 0.0.0.0:8000, rebuild as `hello:v2`, Deployment with `containerPort`, NodePort Service (port 80 → targetPort 8000).
- **2026-10-14**: Switched `hello` to Flask. Fixed the Service (`apiVersion: v1`, `ports` under `spec`, targetPort = the app's port) and learned that `imagePullPolicy: Always` stays stuck on a Deployment first created with `:latest`.
- **2026-10-14**: `hello` (Flask, `hello:v3`) working. Reached it via NodePort (`curl $(minikube ip):31498`), `minikube service --url`, `port-forward`, and from inside the cluster with a throwaway busybox pod.
- **2026-10-14**: Learned why the NodePort was 31498 (randomly assigned from 30000–32767) and how to pin it with `nodePort:`.
- **2026-10-14**: API groups: why Service is `v1` (core group) and Deployment is `apps/v1`; `kubectl api-resources` / `api-versions` / `explain`.
- **2026-10-14**: Reviewed progress so far and created `PRACTICE.md`: 12 levels of hands-on scenarios (config, probes, storage, networking, HPA, scheduling, RBAC, Kustomize/Helm), break-and-fix drills, a capstone and speed drills.
