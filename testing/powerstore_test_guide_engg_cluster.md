# PowerStore Storage Checkup - Engineering Test Guide

Quick guide for running kubevirt-storage-checkup on vanilla Kubernetes with PowerStore storage.

---

## Prerequisites Verification

```bash
export KUBECONFIG=~/.kube/kubevirt-vanilla

# Check cluster access
kubectl get nodes
# Expected: All nodes Ready

# Check KubeVirt
kubectl get kubevirt -n kubevirt
# Expected: Phase: Deployed

# Check CDI
kubectl get cdi -n cdi
# Expected: Phase: Deployed

# Check storage class
kubectl get storageclass
# Expected: powerstore-ext4 (default)

# Check golden images namespace
kubectl get dataimportcron -n kubevirt-os-images
# Expected: At least one DataImportCron (centos-stream-image-cron, fedora-image-cron)
```

---

## Step 1: Create Test Namespace

```bash
kubectl create namespace kubevirt-storage-checkup-test
```

**Verify:**
```bash
kubectl get namespace kubevirt-storage-checkup-test
# Expected: STATUS Active
```

---

## Step 2: Apply RBAC (4 Layers)

### Layer 1: Namespace-Scoped Permissions
```bash
kubectl apply -n kubevirt-storage-checkup-test -f manifests/storage_checkup_permissions.yaml
```

### Layer 2: Cluster-Scoped Permissions
```bash
export CHECKUP_NAMESPACE=kubevirt-storage-checkup-test
sed "s/\$CHECKUP_NAMESPACE/$CHECKUP_NAMESPACE/g" \
  manifests/storage_checkup_clusterrole.yaml | kubectl apply -f -
```

### Layer 3: Golden Images Access
```bash
export GOLDEN_IMAGES_NAMESPACE=kubevirt-os-images
sed "s/\${GOLDEN_IMAGES_NAMESPACE:-kubevirt-os-images}/$GOLDEN_IMAGES_NAMESPACE/g; \
     s/\$CHECKUP_NAMESPACE/$CHECKUP_NAMESPACE/g" \
  manifests/storage_checkup_golden_images_rbac.yaml | kubectl apply -f -
```

### Layer 4: CDI Clone Authorization
```bash
sed "s/\${GOLDEN_IMAGES_NAMESPACE:-kubevirt-os-images}/$GOLDEN_IMAGES_NAMESPACE/g; \
     s/\$CHECKUP_NAMESPACE/$CHECKUP_NAMESPACE/g" \
  manifests/storage_checkup_cdi_cloner.yaml | kubectl apply -f -
```

**Verify:**
```bash
# Check namespace RBAC
kubectl get sa,role,rolebinding -n kubevirt-storage-checkup-test
# Expected: storage-checkup-sa, storage-checkup-role, rolebinding

# Check cluster RBAC
kubectl get clusterrole,clusterrolebinding | grep kubevirt-storage-checkup
# Expected: ClusterRole and ClusterRoleBinding present
```

---

## Step 3: Create ConfigMap

```bash
kubectl apply -f testing/powerstore-configmap-basic.yaml
```

**Verify:**
```bash
kubectl get configmap storage-checkup-config -n kubevirt-storage-checkup-test
# Expected: ConfigMap exists

# View configuration
kubectl get configmap storage-checkup-config -n kubevirt-storage-checkup-test -o yaml
# Expected: spec.param.platform=vanilla-k8s, goldenImagesNamespace=kubevirt-os-images
```

---

## Step 4: Run Checkup Job

```bash
kubectl apply -f testing/checkup-job.yaml
```

**Monitor:**
```bash
# Watch Job status
kubectl get job -n kubevirt-storage-checkup-test -w

# Follow logs
POD=$(kubectl get pod -n kubevirt-storage-checkup-test -l app=kubevirt-storage-checkup -o name)
kubectl logs -f -n kubevirt-storage-checkup-test $POD
```

**Expected Log Output:**
```
kubevirt-storage-checkup starting...
checkVersions
Using configured platform: vanilla-k8s
Detected platform: vanilla-k8s
Kubernetes version: v1.34.1, KubeVirt version: v1.6.1
checkDefaultStorageClass
checkPVCCreationAndBinding
PVC "checkup-pvc" bound
checkStorageProfiles
checkVolumeSnapShotClasses
checkGoldenImages
Selected golden image PVC: kubevirt-os-images/centos-stream-image-...
checkVMIs
checkVMIBoot
VMI "vmi-under-test-xxxxx" successfully booted
checkVMILiveMigration
cannot migrate VMI: PVC is not shared (expected for RWO storage)
checkVMIHotplugVolume
VMI "vmi-under-test-xxxxx" hotplug volume ready
VMI "vmi-under-test-xxxxx" hotplug volume removed
checkConcurrentVMIBoot numOfVMs:10
Boot completed on all VMs on time
```

**Completion Time:** ~5-6 minutes

---

## Step 5: View Results

### Check Overall Status
```bash
kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o jsonpath='{.data.status\.succeeded}'
# Expected: true
```

### View All Results
```bash
kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o jsonpath='{.data}' | jq -r 'to_entries[] | select(.key | startswith("status.")) | "\(.key): \(.value)"'
```

### Key Result Fields
```bash
# Platform detection
kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o jsonpath='{.data.status\.result\.platform}'
# Expected: vanilla-k8s

# Versions
kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o jsonpath='{.data.status\.result\.k8sVersion}'
# Expected: v1.34.1

kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o jsonpath='{.data.status\.result\.kubevirtVersion}'
# Expected: v1.6.1

# Storage class
kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o jsonpath='{.data.status\.result\.defaultStorageClass}'
# Expected: powerstore-ext4

# VM boot
kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o jsonpath='{.data.status\.result\.vmBootFromGoldenImage}'
# Expected: VMI "vmi-under-test-xxxxx" successfully booted

# Concurrent boot
kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o jsonpath='{.data.status\.result\.concurrentVMBoot}'
# Expected: Boot completed on all VMs on time
```

---

## Cleanup

```bash
# Delete Job (keeps ConfigMap with results)
kubectl delete job kubevirt-storage-checkup -n kubevirt-storage-checkup-test

# Delete ConfigMap
kubectl delete configmap storage-checkup-config -n kubevirt-storage-checkup-test

# Delete namespace (removes all resources)
kubectl delete namespace kubevirt-storage-checkup-test

# Delete cluster RBAC
kubectl delete clusterrolebinding kubevirt-storage-checkup-$CHECKUP_NAMESPACE
kubectl delete clusterrole kubevirt-storage-checkup kubevirt-storage-checkup-cdi-cloner

# Delete golden images RBAC
kubectl delete rolebinding kubevirt-storage-checkup-golden-images \
  kubevirt-storage-checkup-cdi-cloner default-cdi-cloner \
  -n kubevirt-os-images
kubectl delete role kubevirt-storage-checkup-golden-images -n kubevirt-os-images
```

---

## Expected Results (All Pass)

| Check | Result | Notes |
|-------|--------|-------|
| Platform Detection | vanilla-k8s | Auto-detected |
| Kubernetes Version | v1.34.1 | From Discovery API |
| KubeVirt Version | v1.6.1 | From KubeVirt CR |
| Default Storage Class | powerstore-ext4 | PowerStore iSCSI |
| PVC Binding | ~15 seconds | Fast provisioning |
| Storage Profiles | powerstore-ext4 | Spec-based |
| Golden Images | Available | CentOS/Fedora |
| VM Boot | ~1-2 minutes | Host-assisted clone |
| Live Migration | RWO limitation reported | Expected for block storage |
| Hotplug | Attach + Detach success | Feature gate required |
| Concurrent Boot (10 VMs) | ~2-3 minutes | All VMs boot successfully |

**Overall Duration:** 5-6 minutes

---

## Troubleshooting

### Job Fails with RBAC Error
```bash
# Check service account permissions
kubectl auth can-i get storageclasses \
  --as=system:serviceaccount:kubevirt-storage-checkup-test:storage-checkup-sa

# Expected: yes
```

### Cross-Namespace Clone Fails
```bash
# Verify CDI cloner role
kubectl get rolebinding kubevirt-storage-checkup-cdi-cloner -n kubevirt-os-images
# Expected: RoleBinding exists
```

### Hotplug Test Fails
```bash
# Check feature gate
kubectl get kubevirt kubevirt -n kubevirt \
  -o jsonpath='{.spec.configuration.developerConfiguration.featureGates}'
# Expected: ["HotplugVolumes"]

# Enable if missing
kubectl patch kubevirt kubevirt -n kubevirt --type='json' -p='[
  {"op": "add", "path": "/spec/configuration/developerConfiguration",
   "value": {"featureGates": ["HotplugVolumes"]}}
]'
```

---

## Container Image

```
Image: docker.io/parasarkodati/kubevirt-storage-checkup:beta
Pull Policy: Always
```

---

## Files Used

- `manifests/storage_checkup_permissions.yaml` - Namespace RBAC
- `manifests/storage_checkup_clusterrole.yaml` - Cluster RBAC
- `manifests/storage_checkup_golden_images_rbac.yaml` - Golden images access
- `manifests/storage_checkup_cdi_cloner.yaml` - CDI clone authorization
- `testing/powerstore-configmap-basic.yaml` - Configuration
- `testing/checkup-job.yaml` - Job definition
