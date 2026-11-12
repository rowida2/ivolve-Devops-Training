# Lab 12: Managing Configuration and Sensitive Data with ConfigMaps and Secrets

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?logo=mysql&logoColor=white)
![Status](https://img.shields.io/badge/Status-Completed-success)




- [Implementation](#implementation)
  - [1. Verify the Namespace](#1-verify-the-namespace)
  - [2. Create the ConfigMap](#2-create-the-configmap)
  - [3. Encode Secret Values with Base64](#3-encode-secret-values-with-base64)
  - [4. Create the Secret](#4-create-the-secret)
  - [5. Prepare Persistent Storage on the Worker](#5-prepare-persistent-storage-on-the-worker)
  - [6. Deploy MySQL](#6-deploy-mysql)
  - [7. Wait for MySQL to Start](#7-wait-for-mysql-to-start)
  - [8. Verify the MySQL Service](#8-verify-the-mysql-service)
  - [9. Verify the Database and Users](#9-verify-the-database-and-users)
  - [10. Final Verification](#10-final-verification)


---

## Overview

This lab demonstrates how to **decouple configuration from application code** in Kubernetes. Non-sensitive settings are stored in a **ConfigMap**, credentials are stored in a **Secret**, and both are injected into a **MySQL StatefulSet** at runtime. Data is persisted using a **PersistentVolume** and **PersistentVolumeClaim**, and the database is exposed internally through a **headless Service**.

## Objectives

- Create a ConfigMap (`ivolvecm`) for non-sensitive MySQL configuration.
- Create a Secret (`ivolvesecret`) for MySQL credentials.
- Understand Base64 encoding for Kubernetes Secret values.
- Deploy MySQL using a StatefulSet with persistent storage.
- Inject configuration using `configMapKeyRef` and `secretKeyRef`.
- Verify the database, Service, storage, and resources in the `ivolve` namespace.

## Architecture

```
                 ┌─────────────────────── namespace: ivolve ───────────────────────┐
                 │                                                                 │
                 │   ┌────────────┐     ┌──────────────┐                           │
                 │   │ ConfigMap  │     │   Secret     │                           │
                 │   │ ivolvecm   │     │ ivolvesecret │                           │
                 │   │ DB_HOST    │     │ ROOT_PASS    │                           │
                 │   │ DB_USER    │     │ DB_PASSWORD  │                           │
                 │   └─────┬──────┘     └──────┬───────┘                           │
                 │         │  env vars         │                                   │
                 │         ▼                   ▼                                   │
                 │   ┌─────────────────────────────────┐    ┌──────────────────┐   │
                 │   │  StatefulSet: mysql  (mysql-0)  │───▶│ PVC: mysql-pvc   │   │
                 │   └────────────────┬────────────────┘    └────────┬─────────┘   │
                 │                    │                              │             │
                 │   ┌────────────────▼────────────────┐    ┌────────▼─────────┐   │
                 │   │ Headless Service: mysql-headless│    │ PV: mysql-pv     │   │
                 │   └─────────────────────────────────┘    │ hostPath on      │   │
                 │                                          │ k8s-worker1      │   │
                 │                                          └──────────────────┘   │
                 └─────────────────────────────────────────────────────────────────┘
```

## Environment

| Component      | Details                         |
|----------------|---------------------------------|
| Cluster type   | kubeadm, local virtual machines |
| Control plane  | `k8s-master` (192.168.182.131)  |
| Worker node    | `k8s-worker1` (192.168.182.130) |
| Namespace      | `ivolve`                        |
| MySQL image    | `mysql:8.0`                     |
| Storage        | `hostPath` PersistentVolume     |


---

## Implementation

### 1. Verify the Namespace

```bash
kubectl get namespace ivolve
kubectl get statefulsets,services -n ivolve
kubectl get configmaps,secrets -n ivolve
```

### 2. Create the ConfigMap

`ivolveCM.yaml` stores the non-sensitive configuration.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ivolvecm
  namespace: ivolve
data:
  DB_HOST: "mysql-headless"
  DB_USER: "ivolve_user"
```

| Key       | Description                                    |
|-----------|------------------------------------------------|
| `DB_HOST` | Hostname of the MySQL headless Service         |
| `DB_USER` | Application user for the `ivolve` database     |

```bash
kubectl apply -f ivolveCM.yaml
kubectl get configmap ivolvecm -n ivolve
kubectl describe configmap ivolvecm -n ivolve
```

> **Note:** Kubernetes resource names must be lowercase, so `ivolveCM` is defined as `ivolvecm`. The `mysql-headless` Service is created later in this lab.

### 3. Encode Secret Values with Base64

Kubernetes Secrets in YAML manifests expect Base64-encoded values.

```bash
printf '%s' 'YOUR_ROOT_PASSWORD' | base64
printf '%s' 'YOUR_DB_PASSWORD' | base64
```

> Use `printf '%s'` (or `echo -n`) so that no trailing newline is included in the encoded value.

### 4. Create the Secret

`ivolvesecret.yaml` (replace the placeholders locally with your Base64 values):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ivolvesecret
  namespace: ivolve
type: Opaque
data:
  MYSQL_ROOT_PASSWORD: "REPLACE_WITH_ROOT_PASSWORD_BASE64"
  DB_PASSWORD: "REPLACE_WITH_DB_PASSWORD_BASE64"
```

| Key                   | Description                           |
|-----------------------|---------------------------------------|
| `MYSQL_ROOT_PASSWORD` | Password of the MySQL `root` account  |
| `DB_PASSWORD`         | Password of the application user      |

```bash
kubectl apply -f ivolvesecret.yaml
kubectl get secret ivolvesecret -n ivolve
kubectl describe secret ivolvesecret -n ivolve
```

`describe` shows only the keys and their sizes, never the values.

### 5. Prepare Persistent Storage on the Worker

The PersistentVolume uses a `hostPath` directory, so the directory must exist **on the Worker node** (not the Master).

```bash
ssh <user>@192.168.182.130

sudo mkdir -p /mnt/data/mysql
sudo chmod 777 /mnt/data/mysql
ls -ld /mnt/data/mysql
```

Expected: `drwxrwxrwx` on `/mnt/data/mysql`.

### 6. Deploy MySQL

Check the current state first:

```bash
kubectl get pods -n ivolve
kubectl describe resourcequota ivolvequota -n ivolve
```

`mysql-resources.yaml` defines four resources:

| Resource                            | Purpose                                              |
|-------------------------------------|------------------------------------------------------|
| PersistentVolume `mysql-pv`         | 1Gi of local storage on the Worker                   |
| PersistentVolumeClaim `mysql-pvc`   | Requests the storage used by MySQL                   |
| Headless Service `mysql-headless`   | Stable DNS identity for the StatefulSet              |
| StatefulSet `mysql`                 | Runs MySQL with config from the ConfigMap and Secret |

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/data/mysql
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - k8s-worker1
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  namespace: ivolve
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
  namespace: ivolve
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
    - name: mysql
      port: 3306
      targetPort: 3306
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: ivolve
spec:
  serviceName: mysql-headless
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      nodeSelector:
        kubernetes.io/hostname: k8s-worker1
      tolerations:
        - key: workload
          operator: Equal
          value: ivolveApp
          effect: NoSchedule
      containers:
        - name: mysql
          image: mysql:8.0
          ports:
            - containerPort: 3306
          env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ivolvesecret
                  key: MYSQL_ROOT_PASSWORD
            - name: MYSQL_DATABASE
              value: ivolve
            - name: MYSQL_USER
              valueFrom:
                configMapKeyRef:
                  name: ivolvecm
                  key: DB_USER
            - name: MYSQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ivolvesecret
                  key: DB_PASSWORD
          resources:
            requests:
              cpu: 250m
              memory: 384Mi
            limits:
              cpu: "1"
              memory: 650Mi
          volumeMounts:
            - name: mysql-storage
              mountPath: /var/lib/mysql
      volumes:
        - name: mysql-storage
          persistentVolumeClaim:
            claimName: mysql-pvc
```

Apply and inspect:

```bash
# Remove leftover Lab 11 test Pods (if any)
kubectl delete pod quota-pod-1 quota-pod-2 quota-pod-3 -n ivolve --ignore-not-found=true

kubectl apply -f mysql-resources.yaml

kubectl get pv mysql-pv
kubectl get pvc -n ivolve
kubectl get statefulsets,services -n ivolve
kubectl get pods -n ivolve -o wide
```

### 7. Wait for MySQL to Start

```bash
kubectl rollout status statefulset/mysql -n ivolve --timeout=180s
kubectl get pod mysql-0 -n ivolve -o wide
kubectl describe pod mysql-0 -n ivolve
```

`mysql-0` is `Running` with `1/1` containers ready.

### 8. Verify the MySQL Service

```bash
kubectl exec mysql-0 -n ivolve -- \
  sh -c 'mysqladmin ping -uroot -p"$MYSQL_ROOT_PASSWORD"'
```


```
mysqld is alive
```

### 10. Final Verification

```bash
kubectl get configmap ivolvecm -n ivolve -o yaml
kubectl get statefulset,services,pods -n ivolve -o wide
kubectl get pv,pvc
kubectl get endpointslice -n ivolve
kubectl describe resourcequota ivolvequota -n ivolve
```

Checklist:

- [x] StatefulSet `mysql` is ready (`1/1`).
- [x] Pod `mysql-0` is `Running`.
- [x] PVC `mysql-pvc` is `Bound` to `mysql-pv`.
- [x] Headless Service has an endpoint for the MySQL Pod.
- [x] ResourceQuota usage is within limits.

---


## Security Notes

- **Base64 is encoding, not encryption.** Anyone with the encoded value can decode it.
- Never commit real passwords or their Base64 representations to a public repository. Keep placeholders in documented manifests.
- `chmod 777` is used for simplicity in this lab. In production, use restrictive ownership and permissions suited to the MySQL container user.
- A `hostPath` volume ties data to a single node and is not replicated or portable. Use a proper storage backend in production.
- Consider enabling encryption at rest for Secrets and restricting access with RBAC.

## Key Takeaways

| Concept            | Purpose                                                       |
|--------------------|---------------------------------------------------------------|
| ConfigMap          | Stores non-sensitive configuration separate from the image    |
| Secret             | Stores sensitive data such as passwords                       |
| `configMapKeyRef`  | Injects a single ConfigMap key as an environment variable     |
| `secretKeyRef`     | Injects a single Secret key as an environment variable        |
| PV / PVC           | Decouple storage provisioning from storage consumption        |
| Headless Service   | Provides stable DNS for StatefulSet Pods                      |
| StatefulSet        | Manages stateful workloads with stable identity and storage   |

## Cleanup

```bash
kubectl delete -f mysql-resources.yaml
kubectl delete -f ivolvesecret.yaml
kubectl delete -f ivolveCM.yaml
kubectl delete pv mysql-pv --ignore-not-found=true

# On the Worker (optional)
sudo rm -rf /mnt/data/mysql
```


## Resulف

MySQL was deployed in the `ivolve` namespace using a ConfigMap for non-sensitive settings and a Secret for credentials, backed by a PersistentVolume, PersistentVolumeClaim, and headless Service. The server responds to health checks, and database access was verified with both the root and application users.
