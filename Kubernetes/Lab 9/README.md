# Lab 9: Deploying a Kubernetes Cluster with kubeadm

A two-node Kubernetes cluster built from scratch with **kubeadm** on Ubuntu Server virtual machines, using **containerd** as the container runtime and **Calico** as the CNI plugin for pod networking.

## Objectives

- Install and configure **containerd** as the container runtime on all nodes
- Install **kubeadm**, **kubelet**, and **kubectl** on the control plane and worker nodes
- Initialize the control plane with `kubeadm init`
- Configure **kubectl** to communicate with the cluster
- Install the **Calico** CNI plugin to enable pod networking across the cluster
- Join the worker node with `kubeadm join`
- Verify that all nodes are `Ready` and that the cluster components are running correctly

---

## 1. Architecture

```
                 VMware Workstation  (NAT network 192.168.182.0/24)
  ┌──────────────────────────────────────────────────────────────────┐
  │                                                                  │
  │   ┌─────────────────────────┐      ┌─────────────────────────┐   │
  │   │  k8s-master             │      │  k8s-worker1            │   │
  │   │  Control Plane          │◄────►│  Worker Node            │   │
  │   │  192.168.182.131        │ 6443 │  192.168.182.130        │   │
  │   │                         │      │                         │   │
  │   │  kube-apiserver         │      │  kubelet                │   │
  │   │  etcd                   │      │  kube-proxy             │   │
  │   │  kube-scheduler         │      │  calico-node            │   │
  │   │  kube-controller-mgr    │      │  containerd             │   │
  │   │  kubelet, kube-proxy    │      └─────────────────────────┘   │
  │   │  calico-node            │                                    │
  │   │  containerd             │      Pod network: 10.244.0.0/16    │
  │   └─────────────────────────┘                                    │
  └──────────────────────────────────────────────────────────────────┘
```

| Node | Role | Hostname | IP address | vCPU | RAM | Disk |
|---|---|---|---|---|---|---|
| Node 1 | Control plane | `k8s-master` | `192.168.182.131` | 2 | `TODO` | `TODO` |
| Node 2 | Worker | `k8s-worker1` | `192.168.182.130` | `TODO` | `TODO` | `TODO` |

> The worker node was created as a full clone of the first VM after the common setup (OS preparation, containerd, and the Kubernetes tools). The machine ID was cleared before cloning so that each node gets a unique identity.

---

## 2. Environment and versions

| Component | Version |
|---|---|
| Hypervisor | VMware Workstation |
| Operating system | Ubuntu Server 26.04.1 LTS |
| Container runtime | containerd 2.2.2 |
| Kubernetes (kubeadm, kubelet, kubectl) | v1.36.6 |
| CNI plugin | Calico v3.33.0 (installed with the Tigera Operator) |
| Pod network CIDR | `10.244.0.0/16` |

**Why `10.244.0.0/16` for the pod network?** The Calico default (`192.168.0.0/16`) overlaps with the VM network (`192.168.182.0/24`), which would cause routing conflicts. The same CIDR is therefore passed to `kubeadm init` and set in the Calico `custom-resources.yaml`.

---

## 3. Prerequisites

- Two VMs on the same network, each with a **unique hostname**, a **unique IP address**, and internet access
- At least **2 vCPUs** on the control plane node (a `kubeadm init` pre-flight requirement)
- At least 2 GB of RAM per node
- A user with `sudo` privileges

---

## 4. Implementation

Steps 4.1 to 4.3 were done once on the first VM, which was then cloned to create the worker node. Steps 4.4 onward are split by node.

### 4.1 Prepare the operating system (all nodes)

Update the system so every node starts from the same patched baseline, then reboot to load the new kernel.

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot
```

**Disable swap.** The kubelet does not run with swap enabled by default, and Kubernetes relies on accurate memory accounting. The second command comments out the swap entry in `/etc/fstab` so the change survives a reboot.

```bash
sudo swapoff -a
sudo sed -i '/swap.img/ s/^/#/' /etc/fstab
free -h
grep swap /etc/fstab
```

Swap disabled
<img width="941" height="200" alt="Screenshot 2026-11-08 201355" src="https://github.com/user-attachments/assets/1f3ef7d1-55f1-4bd9-a354-66c4b67f3b12" />


**Load the required kernel modules.** `overlay` is used by containerd for layered container filesystems. `br_netfilter` lets iptables see bridged pod traffic.

```bash
sudo modprobe overlay
sudo modprobe br_netfilter
printf "overlay\nbr_netfilter\n" | sudo tee /etc/modules-load.d/k8s.conf
lsmod | grep -E "overlay|br_netfilter"
```

Kernel modules
<img width="933" height="220" alt="image" src="https://github.com/user-attachments/assets/c9db4974-1e91-403a-936d-d232a8f315c3" />


**Set the networking sysctl parameters.** These let bridged traffic pass through iptables and allow the node to forward packets between pod networks.

```bash
printf "net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\n" | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system
```

![sysctl settings](screenshots/03-sysctl-settings.png)

### 4.2 Install and configure containerd (all nodes)

```bash
sudo apt-get install -y containerd
containerd --version
```

containerd installed
<img width="907" height="127" alt="Screenshot 2026-11-08 201506" src="https://github.com/user-attachments/assets/0fff1fc5-62f1-463d-8754-951122b14a78" />


Generate the default configuration and switch containerd to the **systemd cgroup driver**. The kubelet and the OS both use systemd to manage cgroups, and a mismatch with the runtime leads to an unstable cluster.

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep SystemdCgroup /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
systemctl is-active containerd
```

containerd systemd cgroup
<img width="926" height="128" alt="Screenshot 2026-11-08 201558" src="https://github.com/user-attachments/assets/2acc0d5a-d434-4c94-96be-217253d2c948" />



### 4.3 Install kubeadm, kubelet, and kubectl (all nodes)

Add the official Kubernetes package repository for the v1.36 release line.

```bash
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
```

Hold the three packages so a routine `apt upgrade` cannot move them to mismatched versions.

```bash
sudo apt-mark hold kubelet kubeadm kubectl
kubeadm version -o short
kubectl version --client
```

Kubernetes tools installed
<img width="842" height="191" alt="Screenshot 2026-11-08 201808" src="https://github.com/user-attachments/assets/d1f9cbbd-7232-4506-9999-531d4b088332" />


### 4.4 Clone the VM and set unique identities

Before cloning, the machine ID was cleared so that each clone generates its own on first boot (duplicate machine IDs can cause two VMs to receive the same DHCP lease).

```bash
sudo truncate -s 0 /etc/machine-id
sudo poweroff
```

In VMware Workstation: right-click the VM, then **Manage > Clone > Create a full clone**. The control plane VM was then given 2 vCPUs.

On each node, set a unique hostname:

```bash
# on the control plane
sudo hostnamectl set-hostname k8s-master

# on the worker
sudo hostnamectl set-hostname k8s-worker1
```

Check that the two nodes have different names, machine IDs, and IP addresses, and that they can reach each other:

```bash
hostnamectl | grep -E "Static hostname|Machine ID"
ip -br a | grep ens160
ping -c 3 192.168.182.131     # from the worker
```

### 4.5 Initialize the control plane (control plane only)

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=192.168.182.131
```

- `--pod-network-cidr` sets the pod IP range and must match the CNI configuration.
- `--apiserver-advertise-address` is the address the worker uses to reach the API server.

kubeadm init
<img width="1292" height="88" alt="image" src="https://github.com/user-attachments/assets/7d5e46db-145f-4d06-bd3b-82bcd3902199" />


> The `kubeadm join` command printed at the end of the output contains a token and a CA certificate hash. It is not reproduced in this document.

### 4.6 Configure kubectl (control plane only)

Copy the admin kubeconfig into the user's home directory so `kubectl` can authenticate to the cluster without `sudo`.

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes
```

The node shows `NotReady` at this point because no CNI plugin is installed yet.

![kubectl configured](screenshots/08-kubectl-configured.png)

### 4.7 Install the Calico CNI plugin (control plane only)

Calico is installed with the Tigera Operator. The three manifests below register the Calico API types, deploy the operator, and then ask the operator to install Calico.

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/v3_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/custom-resources.yaml
```

The default IP pool in `custom-resources.yaml` is `192.168.0.0/16`. It is changed to match the pod CIDR passed to `kubeadm init`:

```bash
sed -i 's|cidr: 192.168.0.0/16|cidr: 10.244.0.0/16|' custom-resources.yaml
grep cidr custom-resources.yaml

kubectl create -f custom-resources.yaml
watch kubectl get tigerastatus
```

Once the components report `AVAILABLE: True`, the control plane node changes to `Ready`.

![Calico installed](screenshots/09-calico-installed.png)

### 4.8 Join the worker node (worker only)

Run the join command from the `kubeadm init` output on the worker. If the token has expired (tokens last 24 hours), generate a new command on the control plane with `kubeadm token create --print-join-command`.

```bash
sudo kubeadm join 192.168.182.131:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Worker joined
<img width="1031" height="143" alt="image" src="https://github.com/user-attachments/assets/16861d8a-3326-45bf-ae25-95095f6cb3c4" />


Calico runs as a DaemonSet, so it is deployed to the new node automatically. No extra installation is needed on the worker.

---

## 5. Verification

Run on the control plane:

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl get pods -n calico-system
kubectl cluster-info
```

**Expected result:** both `k8s-master` and `k8s-worker1` in `Ready` state, and every pod in `kube-system` and `calico-system` in `Running` state.

Nodes ready
<img width="806" height="110" alt="image" src="https://github.com/user-attachments/assets/971475db-362d-4fee-8ba2-b730884e29c4" />


Pods running
<img width="1461" height="608" alt="image" src="https://github.com/user-attachments/assets/f8a563de-d7d4-42a3-9c61-35cdf3736d54" />

---

## 6. References

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Container runtimes (systemd cgroup driver)](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Kubernetes package repositories (pkgs.k8s.io)](https://kubernetes.io/blog/2023/08/15/pkgs-k8s-io-introduction/)
- [Calico: install on self-managed on-premises clusters](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)