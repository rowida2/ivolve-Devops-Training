# Lab 10: Node Isolation Using Taints and Labels in Kubernetes

Node isolation on a two-node cluster built in [Lab 9](../Lab%209/README.md). A **taint** is applied to the worker node so that only pods carrying a matching **toleration** can be scheduled on it, and a **label** is added to the same node so it can be targeted by selectors such as `nodeSelector` and node affinity.

## Objectives

- Apply a taint to a worker node with key `workload`, value `ivolveApp`, and effect `NoSchedule`, so pods are prevented from being scheduled on the node unless they carry a matching toleration
- Label the same worker node with `project=ivolve` to identify it for targeted pod scheduling
- Verify that the taint and the label have been applied correctly using `kubectl describe node` and `kubectl get nodes --show-labels`

---

## 1. Background

### 1.1 Taints and tolerations

A **taint** is set on a **node** and repels every pod that does not carry a matching **toleration**. A **toleration** is set on a **pod** and expresses its willingness to accept a specific taint. The two sides are independent: nodes do not choose their pods, and pods do not choose their nodes — scheduling only succeeds when both agree.

A taint is written as `key=value:effect`, and the effect controls how Kubernetes reacts to a pod without a toleration:

| Effect | Behaviour |
|---|---|
| `NoSchedule` | New pods without a matching toleration are not scheduled on the node. Existing pods keep running. |
| `PreferNoSchedule` | Same as `NoSchedule`, but only a preference. The scheduler tries to avoid the node and may still use it if no other option exists. |
| `NoExecute` | Pods without a matching toleration are **evicted** from the node, and new ones are rejected. (Not used in this lab.) |

A toleration matches a taint when the `key`, `value`, and `effect` fields are equal (or when `operator: Exists` covers the key). A toleration without an `effect` tolerates the taint regardless of its effect.

### 1.2 Labels and selectors

A **label** is a `key=value` piece of metadata attached to a node (or any Kubernetes object). Labels do not restrict anything by themselves — they become powerful when used in **selectors**, for example:

- `kubectl get nodes -l project=ivolve` — select nodes carrying the label
- `nodeSelector: { project: ivolve }` in a pod spec — pin the pod to those nodes
- Node affinity rules for more expressive placement

In this lab the two mechanisms work together: the taint **repels** ordinary pods from the worker, while the label lets a specific workload **target** the worker deliberately.

> **Note:** the control-plane node already carries its own taint, `node-role.kubernetes.io/control-plane:NoSchedule`, which is why system pods need explicit tolerations for it. This is visible in the verification output below.

---

## 2. Environment

The cluster is the one deployed in Lab 9, running on VMware Workstation (NAT network `192.168.182.0/24`):

| Node | Role | Hostname | IP address | Used in this lab |
|---|---|---|---|---|
| Node 1 | Control plane | `k8s-master` | `192.168.182.131` | Runs `kubectl` |
| Node 2 | Worker | `k8s-worker1` | `192.168.182.130` | Receives the taint and the label |

| Component | Version |
|---|---|
| Operating system | Ubuntu Server 26.04.1 LTS |
| Kubernetes | v1.36.6 |
| Container runtime | containerd 2.2.2 |
| CNI plugin | Calico v3.33.0 |

---

## 3. Prerequisites

- The two-node cluster from Lab 9 is running and both nodes report `Ready`
- `kubectl` is configured with admin credentials on the control plane (Lab 9, step 4.6)
- The commands below are executed **on `k8s-master`** as the user with the admin kubeconfig

```bash
kubectl get nodes
```

```
NAME          STATUS   ROLES           AGE   VERSION
k8s-master    Ready    control-plane   29h   v1.36.6
k8s-worker1   Ready    <none>          28h   v1.36.6
```

---

## 4. Implementation

### 4.1 Inspect the worker node before the change

```bash
kubectl describe node k8s-worker1 | grep -E "Taints|Labels" -A1
```

Before the lab the worker has **no taint** of its own and carries only the default Kubernetes labels:

```
Taints:             <none>
```

### 4.2 Apply the taint to the worker node

```bash
kubectl taint nodes k8s-worker1 workload=ivolveApp:NoSchedule
```

```
node/k8s-worker1 tainted
```

The command adds the taint `workload=ivolveApp:NoSchedule` to `k8s-worker1`. From this point on, the scheduler refuses to place any new pod on that node unless the pod declares a toleration for this exact taint.

### 4.3 Label the worker node

```bash
kubectl label nodes k8s-worker1 project=ivolve
```

```
node/k8s-worker1 labeled
```

The node is now identifiable as part of the `ivolve` project and can be selected with `kubectl get nodes -l project=ivolve` or targeted from a pod spec with `nodeSelector: { project: ivolve }`.

---

## 5. Verification

### 5.1 `kubectl get nodes --show-labels`

```bash
kubectl get nodes --show-labels
```

```
NAME          STATUS   ROLES           AGE   VERSION   LABELS
k8s-master    Ready    control-plane   29h   v1.36.6   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=k8s-master,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=,node.kubernetes.io/exclude-from-external-load-balancers=
k8s-worker1   Ready    <none>          28h   v1.36.6   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=k8s-worker1,kubernetes.io/os=linux,project=ivolve
```

The label **`project=ivolve`** appears on `k8s-worker1` and is absent from `k8s-master` — exactly one node is identified for the project.

### 5.2 `kubectl describe node k8s-worker1`

```bash
kubectl describe node k8s-worker1
```

Relevant excerpt:

```
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=k8s-worker1
                    kubernetes.io/os=linux
                    project=ivolve
Annotations:        csi.volume.kubernetes.io/nodeid: {"csi.tigera.io":"k8s-worker1"}
...
Taints:             workload=ivolveApp:NoSchedule
Unschedulable:      false
```

Both changes are confirmed:

| Check | Expected | Observed |
|---|---|---|
| Taint on `k8s-worker1` | `workload=ivolveApp:NoSchedule` | ✅ `Taints: workload=ivolveApp:NoSchedule` |
| Label on `k8s-worker1` | `project=ivolve` | ✅ present under `Labels:` |
| Control plane untouched | no `workload` taint/label | ✅ only `node-role.kubernetes.io/control-plane:NoSchedule` |

---

## 6. Proof: the taint really isolates the node

The verification commands confirm the configuration exists; this section proves it changes scheduling behaviour. Two identical nginx deployments are created — one without a toleration, one with it.

### 6.1 Pod without a toleration stays `Pending`

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-no-toleration
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-no-toleration
  template:
    metadata:
      labels:
        app: web-no-toleration
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
EOF

kubectl get pods -l app=web-no-toleration -o wide
```

```
NAME                                READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE   READINESS GATES
web-no-toleration-9cdb69d8f-qd7rh   0/1     Pending   0          10s   <none>   <none>   <none>           <none>
```

The pod is assigned to **no node**. The scheduler explains why:

```bash
kubectl describe pod -l app=web-no-toleration | grep -A5 Events
```

```
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  10s   default-scheduler  0/2 nodes are available: 2 node(s) had untolerated taint(s). no new claims to deallocate, preemption: 0/2 nodes are available: 2 Preemption is not helpful for scheduling.
```

Both nodes are rejected: the worker carries `workload=ivolveApp:NoSchedule` and the control plane carries `node-role.kubernetes.io/control-plane:NoSchedule`. This is node isolation working as intended.

### 6.2 Pod with a matching toleration runs on the worker

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-with-toleration
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-with-toleration
  template:
    metadata:
      labels:
        app: web-with-toleration
    spec:
      tolerations:
        - key: workload
          operator: Equal
          value: ivolveApp
          effect: NoSchedule
      containers:
        - name: nginx
          image: nginx:alpine
EOF

kubectl get pods -l app=web-with-toleration -o wide
```

```
NAME                                  READY   STATUS              RESTARTS   AGE   IP              NODE
web-with-toleration-c87f6cb54-d9ks4   1/1     Running             0          96s   10.244.194.69   k8s-worker1
```

The toleration `key: workload / value: ivolveApp / effect: NoSchedule` matches the taint exactly, so the scheduler is free to place the pod — and it lands on `k8s-worker1`, the isolated node.

### 6.3 Clean up the demo workloads

```bash
kubectl delete deployment web-no-toleration web-with-toleration
```

```
deployment.apps "web-no-toleration" deleted from default namespace
deployment.apps "web-with-toleration" deleted from default namespace
```

---

## 7. Removing the taint and the label

To return the node to its original state, use a `-` suffix on the key:

```bash
# remove the taint
kubectl taint nodes k8s-worker1 workload-

# remove the label
kubectl label nodes k8s-worker1 project-

# confirm both are gone
kubectl describe node k8s-worker1 | grep -E "Taints|Labels" -A1
kubectl get nodes --show-labels
```

---

## 8. Key takeaways

- **Taints repel, tolerations allow.** A taint on a node affects only pods *without* a matching toleration; it never blocks pods that carry one.
- **`NoSchedule` does not evict.** Pods already running on the node keep running — only new scheduling decisions are blocked. Use `NoExecute` when existing pods must be removed.
- **Labels do not enforce anything by themselves.** They are metadata for selectors (`-l`, `nodeSelector`, affinity); enforcement in this lab comes from the taint.
- **Taints and labels are complementary:** the taint isolates the node from unwanted workloads, while the label lets the right workloads target it on purpose.
- **Both changes are live objects** stored in the cluster state — they survive pod restarts but not a `kubeadm reset`. Re-apply them after rebuilding a node.

---

## 9. References

- [Taints and tolerations (Kubernetes docs)](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Labels and selectors (Kubernetes docs)](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Node affinity vs node selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity)
- [kubectl taint](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_taint/)
- [kubectl label](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_label/)
