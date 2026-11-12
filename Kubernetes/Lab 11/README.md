# Lab 11: Namespace Management and Resource Quota Enforcement

Namespace isolation and quota enforcement on the two-node cluster built in [Lab 9](../Lab%209/README.md). A dedicated **namespace** isolates the project's resources, and a **ResourceQuota** caps the number of pods that may run inside it — a fourth pod is rejected by the API server before it is ever scheduled.

The ResourceQuota manifest used in this lab is available in [`ivolve-quota.yaml`](ivolve-quota.yaml).

## Objectives

- Create a Kubernetes namespace named `ivolve` to isolate application resources
- Create a ResourceQuota named `ivolvequota` in the `ivolve` namespace with a hard limit of `pods=3`
- Verify that the ResourceQuota is applied correctly and confirm that additional pods are rejected when the limit is reached

---

## 1. Background

### 1.1 Namespaces

A **namespace** provides a logical scope inside a single cluster. Objects such as pods, services, and quotas live in a namespace, and names only have to be unique *within* that namespace. Kubernetes ships with built-in namespaces (`default`, `kube-system`, `kube-public`), and teams add their own to separate projects, environments, or tenants on the same cluster.

Namespaces are selected with the `-n` flag:

```bash
kubectl get pods -n ivolve      # pods in the ivolve namespace
kubectl get pods --all-namespaces   # pods across every namespace
```

### 1.2 ResourceQuotas

A **ResourceQuota** sets hard limits on the amount of resources a namespace may consume — for example the number of pods, total CPU/memory requests, or the number of objects of a given kind. When a quota is in place, every new object is checked against it by the API server **at creation time**:

- If the request fits within the remaining budget, the object is created.
- If it would exceed the limit, the API server returns a **`403 Forbidden`** error and the object is never created — there is nothing to schedule or clean up.

This makes quotas a *preventive* control: they stop over-provisioning before it happens instead of reacting to it afterwards.

> **Note on names:** object names must be lowercase RFC 1123 subdomains (`[a-z0-9]([-a-z0-9]*[a-z0-9])?`). The name `ivolveQuota` from the task description contains an uppercase letter and is therefore rejected by the API server — this lab uses **`ivolvequota`**. The exact error is shown in section 4.2.

---

## 2. Environment

The cluster is the one deployed in Lab 9, running on VMware Workstation (NAT network `192.168.182.0/24`):

| Node | Role | Hostname | IP address | Used in this lab |
|---|---|---|---|---|
| Node 1 | Control plane | `k8s-master` | `192.168.182.131` | Runs `kubectl` |
| Node 2 | Worker | `k8s-worker1` | `192.168.182.130` | Runs the quota-limited pods |

| Component | Version |
|---|---|
| Operating system | Ubuntu Server 26.04.1 LTS |
| Kubernetes | v1.36.6 |
| Container runtime | containerd 2.2.2 |
| CNI plugin | Calico v3.33.0 |

> **Prerequisite from Lab 10:** `k8s-worker1` carries the taint `workload=ivolveApp:NoSchedule`. The pods in this lab therefore declare a matching **toleration** (see section 4.3) so they can be scheduled on the worker instead of staying `Pending`. Without the taint the tolerations are harmless and can be omitted.

---

## 3. Prerequisites

- The two-node cluster from Lab 9 is running and both nodes report `Ready`
- `kubectl` is configured with admin credentials on the control plane
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

### 4.1 Task 1 — Create the `ivolve` namespace

```bash
kubectl create namespace ivolve
kubectl get namespace ivolve
```

```
namespace/ivolve created

NAME     STATUS   AGE
ivolve   Active   0s
```

The namespace is created and immediately `Active`. Everything that follows is scoped to it with `-n ivolve`.

### 4.2 Task 2 — Create the ResourceQuota

The task asks for a quota named `ivolveQuota`. Kubernetes rejects that name because object names must be lowercase:

```bash
kubectl create quota ivolveQuota --hard=pods=3 -n ivolve
```

```
error: failed to create quota: ResourceQuota "ivolveQuota" is invalid: metadata.name: Invalid value: "ivolveQuota": a lowercase RFC 1123 subdomain must consist of lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character (e.g. 'example.com', regex used for validation is '[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*')
```

Re-running the command with the lowercase name succeeds:

```bash
kubectl create quota ivolvequota --hard=pods=3 -n ivolve
```

```
resourcequota/ivolvequota created
```

> **Takeaway:** `ivolveQuota` → `ivolvequota`. The same RFC 1123 rule applies to every Kubernetes object name (pods, services, namespaces, …).

### 4.3  Fill the quota with three pods

Three nginx pods are created in the `ivolve` namespace, each with the toleration required by the Lab 10 taint so it can run on `k8s-worker1`:


```
pod/pod1 created
pod/pod2 created
pod/pod3 created
```

---

## 5. Verification

### 5.1 The quota starts empty: `0/3`

Immediately after creation, `describe` shows the budget is untouched:

```bash
kubectl describe resourcequota ivolvequota -n ivolve
```

```
Name:       ivolvequota
Namespace:  ivolve
Resource    Used  Hard
--------    ----  ----
pods        0     3
```

### 5.2 Three pods are Running and the quota is full: `3/3`

```bash
kubectl get pods -n ivolve -o wide
kubectl get resourcequota -n ivolve
```

```
NAME   READY   STATUS    RESTARTS   AGE   IP              NODE          NOMINATED NODE   READINESS GATES
pod1   1/1     Running   0          25s   10.244.194.70   k8s-worker1   <none>           <none>
pod2   1/1     Running   0          25s   10.244.194.71   k8s-worker1   <none>           <none>
pod3   1/1     Running   0          25s   10.244.194.72   k8s-worker1   <none>           <none>

NAME          REQUEST     LIMIT   AGE
ivolvequota   pods: 3/3           26s
```

All three pods are `Running` on `k8s-worker1`, and the quota reports **`pods: 3/3`** — the budget is fully consumed.

### 5.3 A fourth pod is rejected: `exceeded quota`

With the limit reached, any further pod creation is refused by the API server:

```bash
kubectl run extra-4 --image=nginx:alpine -n ivolve
```

```
Error from server (Forbidden): pods "extra-4" is forbidden: exceeded quota: ivolvequota, requested: pods=1, used: pods=3, limited: pods=3
```

The quota itself is unchanged — the request never got far enough to modify it:

```bash
kubectl get resourcequota -n ivolve
```

```
NAME          REQUEST     LIMIT   AGE
ivolvequota   pods: 3/3           26s
```



---

## 6. Reusable manifest

The ResourceQuota is captured in [`ivolve-quota.yaml`](ivolve-quota.yaml):

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ivolvequota
  namespace: ivolve
spec:
  hard:
    pods: "3"
```

Apply it with:

```bash
kubectl apply -f ivolve-quota.yaml
```

```
resourcequota/ivolvequota configured
```



