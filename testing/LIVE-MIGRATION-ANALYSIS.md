# Live Migration Analysis - PowerStore Cluster

**Date**: 2025-10-28
**Cluster**: kubernetes-admin@kubernetes (kubevirt-vanilla)
**Issue**: Live migration fails - "PVC is not shared, requires ReadWriteMany access mode"

---

## Root Cause Analysis

### Current Configuration

**Storage Class**: `powerstore-ext4`
```yaml
provisioner: csi-powerstore.dellemc.com
parameters:
  arrayID: PS03455f439da7
  csi.storage.k8s.io/fstype: ext4
volumeBindingMode: Immediate
```

**Access Mode**: ReadWriteOnce (RWO) only
- iSCSI block storage
- Can only attach to one node at a time
- **Cannot support live migration**

**CSI Driver**: csi-powerstore v2.15.0
```yaml
fsGroupPolicy: ReadWriteOnceWithFSType  # Confirms RWO limitation
```

**StorageProfile**:
```yaml
spec:
  claimPropertySets:
  - accessModes:
    - ReadWriteOnce  # Only RWO supported
    volumeMode: Filesystem
```

### Why Live Migration Fails

**Live migration requires**:
1. PVC must be accessible from both source and target nodes simultaneously
2. Access mode must be ReadWriteMany (RWX)
3. Storage backend must support shared/concurrent access

**Current limitation**:
- iSCSI block storage = exclusive lock to one node
- During migration: source node has PVC attached → target node cannot attach
- Result: Migration blocked

---

## Solution: Enable NFS Storage Class

### Discovery: NFS is Available!

**PowerStore driver configuration**:
```yaml
arrays:
  - endpoint: "https://10.247.27.44/api/rest"
    globalID: "PS03455f439da7"
    blockProtocol: "ISCSI"       # Current: iSCSI (RWO)
    nasName: "nas1"               # ✅ NFS available!
    nfsAcls: "0777"               # ✅ NFS configured!
```

**PowerStore supports both protocols**:
- **iSCSI** (block): RWO only - no migration
- **NFS** (file): RWX capable - **migration supported**

---

## Implementation Steps

### Step 1: Create NFS Storage Class

Create file: `powerstore-nfs-storageclass.yaml`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: powerstore-nfs
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
parameters:
  arrayID: "PS03455f439da7"
  nasName: "nas1"
  csi.storage.k8s.io/fstype: "nfs"
provisioner: csi-powerstore.dellemc.com
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
mountOptions:
  - nfsvers=4.1
```

**Apply**:
```bash
kubectl apply -f powerstore-nfs-storageclass.yaml
```

**Verify**:
```bash
kubectl get storageclass powerstore-nfs
```

### Step 2: Update StorageProfile (Automatic)

CDI will automatically create a StorageProfile for the new storage class with RWX support.

**Verify**:
```bash
kubectl get storageprofile powerstore-nfs -o yaml
```

**Expected**:
```yaml
spec:
  claimPropertySets:
  - accessModes:
    - ReadWriteMany  # ✅ RWX support
    volumeMode: Filesystem
```

### Step 3: Create NFS-based Golden Image

**Option A: Clone existing golden image to NFS**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: centos-stream-nfs
  namespace: kubevirt-os-images
spec:
  source:
    pvc:
      namespace: kubevirt-os-images
      name: centos-stream-image-2813c95491d8  # Existing iSCSI image
  storage:
    accessModes:
      - ReadWriteMany
    resources:
      requests:
        storage: 30Gi
    storageClassName: powerstore-nfs
EOF
```

**Option B: Import directly to NFS**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataImportCron
metadata:
  name: centos-stream-nfs-cron
  namespace: kubevirt-os-images
spec:
  schedule: "0 2 * * 0"
  managedDataSource: centos-stream9-nfs
  template:
    spec:
      source:
        registry:
          url: docker://quay.io/containerdisks/centos-stream:9
      storage:
        accessModes:
          - ReadWriteMany
        resources:
          requests:
            storage: 30Gi
        storageClassName: powerstore-nfs
EOF
```

### Step 4: Test Live Migration with NFS Storage

**Update checkup ConfigMap**:
```bash
kubectl patch configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  --type merge \
  -p '{"data":{"spec.param.storageClass":"powerstore-nfs"}}'
```

**Run checkup**:
```bash
kubectl delete job kubevirt-storage-checkup -n kubevirt-storage-checkup-test
kubectl apply -f testing/checkup-job.yaml
```

**Expected result**:
```
checkVMILiveMigration
VMI "vmi-under-test-xxxxx" live migration completed successfully
```

---

## Verification Commands

### Check Storage Class
```bash
kubectl get storageclass powerstore-nfs -o yaml
```

### Check StorageProfile
```bash
kubectl get storageprofile powerstore-nfs -o jsonpath='{.spec.claimPropertySets[0].accessModes}'
# Expected: ["ReadWriteMany"]
```

### Test PVC with RWX
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs-rwx
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: powerstore-nfs
EOF

kubectl get pvc test-nfs-rwx
# Expected: STATUS Bound
```

### Test VM with NFS Storage
```bash
cat <<EOF | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: test-vm-nfs
  namespace: default
spec:
  running: true
  template:
    spec:
      domain:
        devices:
          disks:
          - name: datavolumedisk
            disk:
              bus: virtio
        resources:
          requests:
            memory: 2Gi
      volumes:
      - name: datavolumedisk
        persistentVolumeClaim:
          claimName: test-nfs-rwx
EOF
```

**Test migration**:
```bash
# Create migration
cat <<EOF | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstanceMigration
metadata:
  name: test-migration
  namespace: default
spec:
  vmiName: test-vm-nfs
EOF

# Check migration status
kubectl get vmim test-migration -o jsonpath='{.status.phase}'
# Expected: Succeeded
```

---

## Performance Comparison

### iSCSI (Current - RWO)

**Pros**:
- Lower latency (block storage)
- Better for databases/transactional workloads
- Direct block access

**Cons**:
- ❌ No live migration
- ❌ Single node attachment only
- ❌ Downtime required for maintenance

**Use cases**:
- Single-node VMs
- Performance-critical workloads
- VMs that don't require high availability

### NFS (Proposed - RWX)

**Pros**:
- ✅ Live migration supported
- ✅ Multi-node attachment
- ✅ Zero-downtime maintenance
- ✅ HA-capable VMs

**Cons**:
- Slightly higher latency (network filesystem)
- Not ideal for heavy random I/O

**Use cases**:
- Production VMs requiring HA
- Multi-node workloads
- VMs needing live migration

---

## Recommendation

### Deployment Strategy

**Dual Storage Class Approach**:

1. **Keep `powerstore-ext4` (iSCSI)** for:
   - Performance-critical VMs
   - Single-node workloads
   - Database VMs

2. **Add `powerstore-nfs`** for:
   - Production VMs requiring HA
   - VMs needing live migration
   - Multi-tier applications

**Golden Images**:
- Create NFS versions of critical golden images
- Use NFS for production VM templates
- Keep iSCSI for performance testing

**Checkup Configuration**:
- Test both storage classes
- Document RWX requirement for migration

---

## Expected Checkup Results After NFS Setup

### Before (iSCSI only)
```
❌ Live Migration: cannot migrate VMI - PVC is not shared
```

### After (NFS enabled)
```
✅ Live Migration: VMI "vmi-under-test-xxxxx" live migration completed successfully
Migration time: 15-30 seconds
Migration type: Live (zero downtime)
```

---

## Alternative Solutions (Not Recommended)

### 1. Shared Block Storage (Requires Hardware)
- Use PowerStore SCSI-3 Persistent Reservations
- Complex setup, limited support
- **Not recommended**: NFS is simpler and fully supported

### 2. CephFS or GlusterFS
- Deploy separate shared filesystem
- **Not recommended**: Adds complexity, PowerStore NFS already available

### 3. Skip Migration Testing
- Modify checkup to skip migration on RWO storage
- **Not recommended**: Migration is a production requirement

---

## Summary

**Current State**: iSCSI (RWO) - no migration
**Solution**: Add NFS storage class (RWX) - migration enabled
**Effort**: ~15 minutes
**Cluster Changes**: 1 new StorageClass + updated golden images
**Result**: All 10 checkup tests pass including live migration

**Action Required**:
1. Create NFS StorageClass
2. Create/clone golden image to NFS
3. Re-run checkup with `storageClass: powerstore-nfs`
4. Verify migration test passes

---

**Status**: ✅ Solution Identified - Implementation Ready
**Impact**: Low (additive, no changes to existing resources)
**Risk**: Low (non-disruptive change)
