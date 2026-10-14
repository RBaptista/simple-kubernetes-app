# Kubernetes Practice Scenarios

Hands-on drills that build on what you've already done (see `NOTES.md`): Pods, Deployments, NodePort Services, your own `hello` Flask image, and the image-pull and selector problems.

**How to use this file**
- Do them roughly in order. Each level assumes the previous ones.
- **Try first, then open the hints.** Hints are folded (`<details>`), so struggle a bit before peeking. The struggle is where you learn.
- Write manifests by hand, then save them under a folder per topic (`configmaps/`, `probes/`, …) so you can re-apply them.
- Every scenario has a **Done when** check. If you can't prove it works, it isn't done.
- Tick the boxes as you go. After each one, add what you learned to `NOTES.md`.

**Habits to build in every scenario**
- `kubectl describe` + `kubectl get events --sort-by=.lastTimestamp` before guessing.
- Generate YAML instead of typing from memory: `kubectl create deployment x --image=y --dry-run=client -o yaml > x.yaml`.
- Look fields up: `kubectl explain deployment.spec.strategy --recursive`.

---

## Level 0: Prove you remember (warm-up)

### [ ] 0.1 Rebuild everything from scratch, no peeking
Delete all your resources (`kubectl delete deploy,svc --all`). Then, **without opening your old YAML files**, recreate:
- the `hello` Deployment (2 replicas, `hello:v3`)
- a NodePort Service on port `30080` pointing at it

**Done when:** `curl $(minikube ip):30080` returns `Hello, World!`.

<details><summary>Hint</summary>

`kubectl create deployment hello --image=hello:v3 --replicas=2 --dry-run=client -o yaml` gives you a skeleton. Remember `imagePullPolicy` and `containerPort`. `kubectl create service nodeport --help` exists too.
</details>

### [ ] 0.2 Fix your own Dockerfile
Your current `Dockerfile` has at least **4 problems**. Find and fix them, then build as `hello:v4`.

<details><summary>Hint: what to look at</summary>

1. `EXPOSE 80`, but what port does `main.py` listen on?
2. `COPY . .` copies **everything**, including `.venv/`, the YAML files and `NOTES.md`. Look up `.dockerignore`.
3. `python:alpine` has no version pinned. Why is that a problem in 6 months?
4. Which user does the container run as? (`kubectl exec <pod> -- id`)
5. Bonus: copy `requirements.txt` and `pip install` **before** `COPY . .`. Why does that make rebuilds faster? (layer caching)
</details>

**Done when:** `minikube image ls | grep hello` shows `v4`, the image is noticeably smaller than v3 (`minikube image ls --format table`), and `kubectl exec` → `id` does **not** print `uid=0(root)`.

---

## Level 1: Deployments in depth

### [ ] 1.1 Rolling update and rollback
1. Change `main.py` to return `Hello, v5!`, build `hello:v5`.
2. Update the running Deployment **without editing the YAML**: `kubectl set image ...`.
3. While it rolls out, watch it live in a second terminal: `kubectl get pods -w`.
4. Now "deploy" a broken version: `kubectl set image deployment/hello hello=hello:doesnotexist`.
5. Observe: does the service go down? How many old pods are still running?
6. Roll back.

**Done when:** you can explain why the app **kept serving traffic** during step 4, and `kubectl rollout history deployment/hello` shows several revisions.

<details><summary>Hint</summary>

`kubectl rollout status|history|undo deployment/hello`. Look at `maxUnavailable` / `maxSurge` in `kubectl explain deployment.spec.strategy.rollingUpdate`. Add `kubectl annotate deployment/hello kubernetes.io/change-cause="v5 release"` to make the history readable.
</details>

### [ ] 1.2 Recreate vs RollingUpdate
Change the strategy to `Recreate`, deploy a new version, and run `while true; do curl -s $(minikube ip):30080; echo; sleep 0.5; done` during the rollout.

**Done when:** you've seen the downtime gap with your own eyes and can say when `Recreate` is the right choice anyway (hint: two versions that can't run at the same time, e.g. a DB schema).

### [ ] 1.3 Scaling and self-healing
1. `kubectl scale deployment hello --replicas=5`
2. Delete 3 pods at once. How fast do they come back?
3. Find the **ReplicaSet** behind the Deployment. Delete the ReplicaSet (not the Deployment). What happens?

**Done when:** you can draw the chain `Deployment → ReplicaSet → Pods` and explain who recreates what. (Look at `ownerReferences` in `kubectl get pod <x> -o yaml`.)

### [ ] 1.4 Labels and selectors, the hard way
1. Pick one `hello` pod and **change its label**: `kubectl label pod <pod> app=debug --overwrite`.
2. What happens to the number of pods? To the Service endpoints?
3. The relabeled pod is still running. Who owns it now?

**Done when:** you understand that this is a real technique to **pull a misbehaving pod out of traffic for debugging** without killing it.

---

## Level 2: Namespaces and kubectl fluency

### [ ] 2.1 Namespaces
1. Create namespaces `dev` and `prod`.
2. Deploy `hello` into both (same YAML, `-n dev` / `-n prod`).
3. From a busybox pod in `dev`, curl the `hello-service` in `prod`.
4. Set your default namespace to `dev` so you stop typing `-n`.

**Done when:** `wget -qO- http://hello-service.prod.svc.cluster.local` works from a pod in `dev`.

<details><summary>Hint</summary>

`kubectl config set-context --current --namespace=dev`. Check with `kubectl config view --minify | grep namespace`. Remember to switch back.
</details>

### [ ] 2.2 Output gymnastics
Answer each with **one command**:
1. The names of all pods only, one per line.
2. The node IP each `hello` pod runs on.
3. The image used by the `hello` Deployment.
4. All pods sorted by restart count.
5. All pods across **all** namespaces whose status isn't `Running`.

<details><summary>Hint</summary>

`-o name`, `-o jsonpath='{.items[*].status.podIP}'`, `-o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image`, `--sort-by`, `--field-selector=status.phase!=Running`, `-A`.
</details>

---

## Level 3: Configuration (ConfigMaps and Secrets)

### [ ] 3.1 Make the app configurable
Change `main.py` so the greeting comes from an env var:
```python
import os
GREETING = os.environ.get("GREETING", "Hello")
```
Build `hello:v6`. Create a **ConfigMap** with `GREETING=Olá` and inject it into the Deployment as an env var.

**Done when:** curl returns `Olá, World!`, and **no** greeting is hard-coded in the image.

### [ ] 3.2 Change config. Does the app notice?
Edit the ConfigMap to `GREETING=Bom dia`. Curl again.

**Done when:** you can explain why nothing changed, and you've made it change with `kubectl rollout restart deployment/hello`.

### [ ] 3.3 Config as a file
Mount a ConfigMap as a **file** (`/etc/hello/message.txt`) and have the app read the file on every request. Now edit the ConfigMap and wait about a minute **without** restarting.

**Done when:** the response changes on its own. You now know the difference between env-var config (read once at start) and volume config (updated live, eventually).

### [ ] 3.4 Secrets
Create a Secret `hello-secret` with `API_KEY=supersecret` and expose it to the app at the `/secret` endpoint (just for the exercise; never do that for real).

**Done when:**
- it works, **and**
- you've run `kubectl get secret hello-secret -o yaml` and decoded the value with `base64 -d`. Write in your notes why "base64 ≠ encryption".

---

## Level 4: Health and resources

### [ ] 4.1 Probes
Add to the app a `/healthz` endpoint (always 200) and a `/ready` endpoint that returns 503 for the first 20 seconds after start.
Add a `readinessProbe` (→ `/ready`) and a `livenessProbe` (→ `/healthz`).

**Done when:** after a rollout, `kubectl get pods` shows `0/1` READY for about 20s, and `kubectl get endpoints hello-service` **does not** list those pods until they're ready.

### [ ] 4.2 Break the liveness probe on purpose
Point the `livenessProbe` at `/doesnotexist`.

**Done when:** you see the RESTARTS counter climbing, find the reason in `kubectl describe pod` (Events), and can explain the difference:
- **readiness fails** → removed from Service, **not** restarted
- **liveness fails** → container **killed and restarted**
- **startupProbe** → what's it for? (slow-starting apps)

### [ ] 4.3 Requests and limits: get OOMKilled
Deploy this and watch it die:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: memhog
spec:
  containers:
  - name: stress
    image: polinux/stress
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "250M", "--vm-hang", "1"]
    resources:
      requests: { memory: "50Mi" }
      limits:   { memory: "100Mi" }
```
**Done when:** you've found `OOMKilled` in `kubectl describe pod memhog` (Last State → Reason) and fixed it **by changing only the limit**.

### [ ] 4.4 Unschedulable
Set `resources.requests.cpu: "50"` (50 whole CPUs) on a pod.

**Done when:** the pod is stuck in `Pending`, you found `Insufficient cpu` in the events, and you can explain that **requests** decide scheduling and **limits** cap usage at runtime. Bonus: check `kubectl describe node minikube` → "Allocated resources".

---

## Level 5: Other workload types

### [ ] 5.1 Job
Your original `main.py` just printed and exited, which caused a `CrashLoopBackOff` in a Deployment. Now run a one-shot script **properly** as a Job that computes something (e.g. `python -c "print(sum(range(10**7)))"`).

**Done when:** the Job shows `COMPLETIONS 1/1`, you read its output with `kubectl logs job/<name>`, and you tried `completions: 5` + `parallelism: 2`.

### [ ] 5.2 Failing Job
Make the Job `exit 1`. Watch `backoffLimit` at work.

**Done when:** you know how many times it retried and where to set the limit. Also try `activeDeadlineSeconds`.

### [ ] 5.3 CronJob
A CronJob that runs every minute and curls `http://hello-service` (a mini uptime check).

**Done when:** you see several completed Jobs. You've set `successfulJobsHistoryLimit` and can trigger it manually: `kubectl create job manual-run --from=cronjob/<name>`.

### [ ] 5.4 Init container
Add an init container to `hello` that waits until a Service called `db` exists (`until nslookup db; do sleep 2; done`).

**Done when:** the pod is stuck in `Init:0/1` until you create any Service named `db`, then starts.

### [ ] 5.5 Sidecar (multi-container pod)
Make the app also write a log line to `/var/log/hello/access.log` on a shared `emptyDir` volume. Add a second container (`busybox`, `tail -f` the file).

**Done when:** `kubectl logs <pod> -c <sidecar-name>` shows the access lines. Notice the two containers share the volume **and** `localhost`.

### [ ] 5.6 DaemonSet
Create a DaemonSet running `busybox sleep infinity`.

**Done when:** you can explain why there's exactly one pod (one node). It'll make more sense in Level 9 with multiple nodes.

---

## Level 6: Storage and stateful apps

### [ ] 6.1 Prove that containers lose data
`kubectl exec` into a pod, write a file to `/tmp/test`, delete the pod. Check the replacement.

**Done when:** the file is gone, and you know why.

### [ ] 6.2 PersistentVolumeClaim
Create a PVC (1Gi), mount it into a pod at `/data`, write a file, delete the pod, recreate it.

**Done when:** the file survives. Look at `kubectl get pv,pvc` and `kubectl get storageclass`. Who created the PV? (dynamic provisioning)

### [ ] 6.3 Redis + visit counter ⭐
Add a Redis backend:
1. Deploy Redis (`redis:7`) with a PVC and a ClusterIP Service `redis`.
2. Change the Flask app to increment a counter in Redis on every request (`pip install redis`, connect to host `redis`). Build `hello:v7`.
3. Return `Hello, World! You are visitor #N`.

**Done when:**
- the counter goes up across **different** `hello` pods (shared state), and
- the count **survives** `kubectl delete pod -l app=redis`.

### [ ] 6.4 StatefulSet
Convert Redis to a **StatefulSet** with a headless Service.

**Done when:** you can explain the differences you observe: stable pod names (`redis-0`), per-pod DNS (`redis-0.redis`), and one PVC per replica via `volumeClaimTemplates`. Scale to 3 and look at the PVCs.

---

## Level 7: Networking

### [ ] 7.1 Ingress
`minikube addons enable ingress`. Create an Ingress that routes:
- `hello.local/` → `hello-service`
- `hello.local/nginx` → `nginx-service`

**Done when:** `curl -H "Host: hello.local" http://$(minikube ip)/` works. Bonus: add `192.168.49.2 hello.local` to `/etc/hosts` and open it in a browser. Switch `hello-service` back to **ClusterIP**, since the Ingress makes the NodePort unnecessary.

### [ ] 7.2 DNS deep dive
From a busybox pod:
- `nslookup hello-service`
- `cat /etc/resolv.conf`, and explain the `search` line
- `nslookup hello-service.dev` vs `nslookup hello-service.prod`

**Done when:** you can explain why the short name `hello-service` works in your own namespace but not across namespaces.

### [ ] 7.3 NetworkPolicy
Goal: **only** `hello` pods may talk to `redis`. Everything else gets blocked.

1. First check whether your cluster even **enforces** policies: write a deny-all policy and test. If nothing gets blocked, your CNI ignores them. Then start a separate cluster: `minikube start -p netpol --cni=calico` (a separate **profile**, so your main cluster stays untouched).
2. Write a default-deny ingress policy for the namespace, then an allow rule `app=hello → app=redis:6379`.

**Done when:** `redis-cli -h redis ping` works from a `hello` pod and **times out** from a random busybox pod.

---

## Level 8: Autoscaling

### [ ] 8.1 HPA
1. `minikube addons enable metrics-server`, then check that `kubectl top pods` works.
2. Make sure `hello` has CPU **requests** (the HPA needs them, so why?).
3. `kubectl autoscale deployment hello --cpu-percent=50 --min=2 --max=8`
4. Generate load: `kubectl run load --rm -it --image=busybox -- sh -c "while true; do wget -qO- http://hello-service >/dev/null; done"`
5. Watch: `kubectl get hpa -w`

**Done when:** you see replicas go up under load, and back down a few minutes after you stop. (Why so slow going down? Look up "stabilization window".) Then rewrite the HPA as YAML (`autoscaling/v2`).

---

## Level 9: Scheduling (multi-node)

Use a **separate profile** so you don't mess up your main cluster:
`minikube start -p multi --nodes 3` (slow because of `preload=false`; be patient). Remember `minikube -p multi image load hello:v7`.

### [ ] 9.1 Where do pods land?
Deploy `hello` with 6 replicas. `kubectl get pods -o wide`.

**Done when:** you see them spread across nodes. Revisit your DaemonSet from 5.6: now 3 pods.

### [ ] 9.2 nodeSelector and affinity
Label one node `disk=ssd`. Pin Redis there with `nodeSelector`. Then do it again with `nodeAffinity` (preferred, not required).

### [ ] 9.3 Taints and tolerations
`kubectl taint nodes multi-m03 dedicated=gpu:NoSchedule`. Redeploy and check that nothing lands there, then add a toleration to one Deployment.

**Done when:** you can explain: affinity *attracts* pods, taints *repel* them.

### [ ] 9.4 Drain a node
`kubectl drain multi-m02 --ignore-daemonsets`. Watch the pods move. Then `uncordon`.

**Done when:** you've added a **PodDisruptionBudget** (`minAvailable: 2`) and seen `drain` respect it.

---

## Level 10: Security

### [ ] 10.1 ServiceAccount and RBAC
1. Create a ServiceAccount `pod-reader` in `dev`.
2. A Role that can only `get`/`list` pods, and a RoleBinding.
3. Run a pod with that SA and the `bitnami/kubectl` image and try `kubectl get pods` (works) and `kubectl delete pod x` (forbidden).

**Done when:** you can predict results with `kubectl auth can-i delete pods --as=system:serviceaccount:dev:pod-reader -n dev`.

### [ ] 10.2 Harden the hello pod
Add a `securityContext`: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, drop all capabilities.

**Done when:** the app still works. If it breaks, figure out why (hint: something might want to write to disk → give it an `emptyDir` for that path).

---

## Level 11: Packaging

### [ ] 11.1 Kustomize
Reorganize your `hello` + `redis` manifests into:
```
kustomize/
  base/            # deployment, service, configmap, redis
  overlays/dev/    # 1 replica, GREETING=Olá dev
  overlays/prod/   # 3 replicas, resource limits, GREETING=Olá
```
**Done when:** `kubectl apply -k kustomize/overlays/dev` and `.../prod` deploy different variants into different namespaces. Preview with `kubectl kustomize ...` first.

### [ ] 11.2 Helm
1. Install a public chart: `helm install my-redis oci://registry-1.docker.io/bitnamicharts/redis` (or any chart). Look at what it created, then `helm uninstall`.
2. `helm create hello-chart` and template your own app (image tag, replicas and greeting as values).

**Done when:** `helm upgrade --set image.tag=v7 ...` rolls out a new version and `helm rollback` takes you back.

---

## 🔧 Break-and-fix drills

Real debugging practice. Apply each broken manifest, **don't read it closely first**, and diagnose only from `kubectl get/describe/logs/events`. Write each one up in `NOTES.md` → Troubleshooting as *symptom → cause → fix*.

<details><summary>Drill A: it never starts</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: drill-a }
spec:
  replicas: 1
  selector: { matchLabels: { app: drill-a } }
  template:
    metadata: { labels: { app: drill-a } }
    spec:
      containers:
      - name: web
        image: nginx:1.27
        command: ["nginx", "-g", "daemon off;", "--oops"]
```
</details>

<details><summary>Drill B: the Service returns nothing</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: drill-b }
spec:
  replicas: 2
  selector: { matchLabels: { app: drill-b } }
  template:
    metadata: { labels: { app: drill-b, tier: web } }
    spec:
      containers:
      - name: web
        image: nginx:1.27
---
apiVersion: v1
kind: Service
metadata: { name: drill-b }
spec:
  selector: { app: drill-b, tier: frontend }
  ports: [{ port: 80, targetPort: 8080 }]
```
(There are **two** bugs.)
</details>

<details><summary>Drill C: stuck in Pending</summary>

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: drill-c }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: super-fast-ssd
  resources: { requests: { storage: 1Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: drill-c }
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts: [{ name: data, mountPath: /data }]
  volumes:
  - name: data
    persistentVolumeClaim: { claimName: drill-c }
```
</details>

<details><summary>Drill D: CreateContainerConfigError</summary>

```yaml
apiVersion: v1
kind: Pod
metadata: { name: drill-d }
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo $DB_PASSWORD; sleep 3600"]
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef: { name: db-creds, key: password }
```
</details>

<details><summary>Drill E: restarts every ~30 seconds</summary>

```yaml
apiVersion: v1
kind: Pod
metadata: { name: drill-e }
spec:
  containers:
  - name: web
    image: nginx:1.27
    livenessProbe:
      httpGet: { path: /, port: 8080 }
      initialDelaySeconds: 5
      periodSeconds: 5
```
</details>

<details><summary>Drill F: the app works, but the ConfigMap is ignored</summary>

```yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: drill-f }
data:
  greeting: "Olá"
---
apiVersion: v1
kind: Pod
metadata: { name: drill-f }
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo GREETING=$GREETING; sleep 3600"]
    envFrom:
    - configMapRef: { name: drill-f }
```
(Look closely at what the variable is called inside the container: `kubectl exec drill-f -- env`.)
</details>

**Bonus drill (ask Claude):** "Break my cluster in a way I have to debug, and don't tell me what you did." Then fix it using only `kubectl`.

---

## 🏁 Capstone: put it all together

Build a "production-like" deployment of your app, using only manifests (or Kustomize) that you can `apply` onto a **fresh** cluster (`minikube delete && minikube start`) in a single command:

- [ ] Namespace `hello-prod`
- [ ] `hello` Deployment, 3 replicas, non-root, pinned image tag, requests + limits
- [ ] readiness + liveness probes
- [ ] greeting from a ConfigMap, a fake API key from a Secret
- [ ] Redis StatefulSet + PVC with the visit counter
- [ ] NetworkPolicy: only `hello` → `redis`
- [ ] Ingress at `hello.local`, no NodePorts
- [ ] HPA 3–10 replicas on CPU
- [ ] PodDisruptionBudget
- [ ] A CronJob that pings the app every 5 min
- [ ] Zero-downtime rollout to a new version proven with a curl loop, then a rollback

**Done when:** a friend could clone the folder, run one command, and get a working app.

---

## ⏱️ Speed drills (CKAD-style)

When the levels above feel comfortable, time yourself. Imperative commands + `--dry-run=client -o yaml` only. Target: **under 3 min each**.

1. Pod `nginx` in namespace `speed`, image `nginx:1.27`, label `tier=web`, port 80.
2. Deployment `api`, 4 replicas, `httpd:2.4`. Scale to 6, then update the image to `httpd:2.4-alpine`, then roll back.
3. Expose `api` as ClusterIP port 8080 → 80. Prove it works from a temp pod.
4. ConfigMap from literals `A=1,B=2`, mounted as env in a pod that prints them.
5. Job that runs `date` 3 times, 2 in parallel.
6. Pod with a liveness `exec` probe `cat /tmp/healthy`, where the container creates and later deletes the file.
7. Find which pod in the cluster uses the most memory (`kubectl top`).
8. Get the names of all images running in the cluster, deduplicated (one pipeline).

---

## Topics to read about afterwards

Not easy to practice locally, but good to know they exist:
- **Gateway API**, the successor to Ingress
- **Operators and CRDs** (how things like cert-manager or Prometheus extend k8s)
- **GitOps**: Argo CD / Flux
- **Observability**: Prometheus + Grafana (`kube-prometheus-stack` Helm chart works on minikube with ~4GB RAM)
- **Pod Security Admission** (`pod-security.kubernetes.io/enforce: restricted` label on a namespace)
- **etcd**, the scheduler and the controller manager: what the control plane actually does (`kubectl get pods -n kube-system`)
- Certifications: **CKAD** (developer) is the natural next step from this list; **CKA** (admin) after that.
