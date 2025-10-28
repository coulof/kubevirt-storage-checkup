# PowerStore Examples for kubevirt-storage-checkup

This directory contains example configurations for running kubevirt-storage-checkup on vanilla Kubernetes with Dell PowerStore storage.

## Contents

- `powerstore-storageclass.yaml` - Storage class for PowerStore iSCSI volumes
- `powerstore-volumesnapshotclass.yaml` - Volume snapshot class for efficient VM cloning
- `powerstore-checkup-configmap.yaml` - Complete checkup configuration for PowerStore
- `fedora-golden-image.yaml` - Example golden image using PowerStore storage
- `test-pvc.yaml` - Example PVC for testing PowerStore provisioning

## Prerequisites

Before using these examples, ensure you have:

1. **Dell PowerStore CSI Driver** installed and configured
2. **PowerStore credentials** configured as a Kubernetes secret
3. **KubeVirt and CDI** installed on your cluster
4. **iSCSI tools** installed on all worker nodes
5. **Network connectivity** from nodes to PowerStore array

## Quick Start

### 1. Create CSI Driver Secret

```bash
kubectl create namespace csi-powerstore

kubectl create secret generic powerstore-creds \
  --from-literal=username='admin' \
  --from-literal=password='Password123!' \
  --namespace=csi-powerstore
```

### 2. Deploy Storage Class

```bash
# Edit powerstore-storageclass.yaml to set your PowerStore globalID
# Replace "PSd0f53d7a1828" with your array's globalID

kubectl apply -f powerstore-storageclass.yaml

# Verify
kubectl get storageclass powerstore-iscsi
```

### 3. Deploy Volume Snapshot Class

```bash
# Edit powerstore-volumesnapshotclass.yaml to set your PowerStore globalID

kubectl apply -f powerstore-volumesnapshotclass.yaml

# Verify
kubectl get volumesnapshotclass powerstore-snapshot-class
```

### 4. Test Storage Provisioning

```bash
# Create a test PVC
kubectl apply -f test-pvc.yaml

# Wait for PVC to bind
kubectl wait --for=condition=Bound pvc/test-powerstore-pvc --timeout=60s

# Verify on PowerStore
# - Log into PowerStore GUI
# - Navigate to Block Storage > Volumes
# - Look for volume with name matching PVC UID

# Cleanup
kubectl delete -f test-pvc.yaml
```

### 5. Create Golden Images

```bash
# Create namespace for golden images
kubectl create namespace kubevirt-os-images

# Deploy golden image
kubectl apply -f fedora-golden-image.yaml

# Trigger immediate import
kubectl annotate dataimportcron fedora-image-cron \
  -n kubevirt-os-images \
  cdi.kubevirt.io/immediateimport="true"

# Wait for import (5-15 minutes)
kubectl get datavolume -n kubevirt-os-images -w

# Verify DataSource created
kubectl get datasource -n kubevirt-os-images
```

### 6. Run Storage Checkup

```bash
# Create test namespace
kubectl create namespace kubevirt-storage-checkup-test

# Apply RBAC
kubectl apply -f ../../manifests/storage_checkup_permissions.yaml \
  -n kubevirt-storage-checkup-test

# Deploy checkup configuration
kubectl apply -f powerstore-checkup-configmap.yaml

# Run checkup
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: storage-checkup
  namespace: kubevirt-storage-checkup-test
spec:
  backoffLimit: 0
  template:
    spec:
      serviceAccount: storage-checkup-sa
      restartPolicy: Never
      containers:
        - name: storage-checkup
          image: quay.io/kiagnose/kubevirt-storage-checkup:main
          imagePullPolicy: Always
          env:
            - name: CONFIGMAP_NAMESPACE
              value: kubevirt-storage-checkup-test
            - name: CONFIGMAP_NAME
              value: storage-checkup-config
EOF

# Watch progress
kubectl logs -n kubevirt-storage-checkup-test \
  -l job-name=storage-checkup -f

# Get results
kubectl get configmap storage-checkup-config \
  -n kubevirt-storage-checkup-test \
  -o yaml
```

## Customization

### Using a Different PowerStore Array

1. Edit storage class and snapshot class:
```yaml
parameters:
  arrayID: "YOUR_ARRAY_GLOBALID"  # e.g., "PSe13c8a71fcaf"
```

2. Ensure CSI driver is configured with this array
3. Update secret credentials if needed

### Adjusting Storage Class Parameters

Common customizations:

```yaml
# Change filesystem type
parameters:
  csi.storage.k8s.io/fstype: "xfs"  # Instead of ext4

# Change volume binding mode
volumeBindingMode: Immediate  # Instead of WaitForFirstConsumer

# Change reclaim policy
reclaimPolicy: Retain  # Instead of Delete
```

### Customizing Checkup Configuration

Common adjustments:

```yaml
data:
  # Longer timeout for large-scale testing
  spec.param.vmiTimeout: "5m"

  # More VMs for stress testing
  spec.param.numOfVMs: "20"

  # Keep resources on failure for debugging
  spec.param.skipTeardown: "onfailure"
```

## Validation

### Verify Storage Class

```bash
# Check storage class
kubectl describe storageclass powerstore-iscsi

# Test provisioning
kubectl apply -f test-pvc.yaml
kubectl get pvc test-powerstore-pvc -w

# Check PowerStore GUI for created volume
```

### Verify Snapshot Functionality

```bash
# Create test PVC and snapshot
kubectl apply -f test-pvc.yaml
kubectl wait --for=condition=Bound pvc/test-powerstore-pvc --timeout=60s

kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
spec:
  volumeSnapshotClassName: powerstore-snapshot-class
  source:
    persistentVolumeClaimName: test-powerstore-pvc
EOF

# Check snapshot
kubectl get volumesnapshot test-snapshot
# Should show: ReadyToUse=true

# Check PowerStore GUI for snapshot

# Cleanup
kubectl delete volumesnapshot test-snapshot
kubectl delete pvc test-powerstore-pvc
```

### Verify Golden Images

```bash
# Check DataImportCron
kubectl get dataimportcron -n kubevirt-os-images

# Check DataSource
kubectl get datasource -n kubevirt-os-images

# Verify PVC using PowerStore storage
kubectl get pvc -n kubevirt-os-images -o yaml | \
  grep storageClassName
# Should show: storageClassName: powerstore-iscsi
```

## Troubleshooting

### PVC Not Binding

```bash
# Check events
kubectl describe pvc <pvc-name>

# Check CSI driver pods
kubectl get pods -n csi-powerstore

# Check CSI driver logs
kubectl logs -n csi-powerstore powerstore-controller-0 -c driver
```

Common issues:
- Secret not found or incorrect
- PowerStore not reachable
- Insufficient capacity
- Array ID mismatch

### Snapshots Not Working

```bash
# Check VolumeSnapshotClass
kubectl get volumesnapshotclass

# Check CSI snapshotter logs
kubectl logs -n csi-powerstore powerstore-controller-0 -c external-snapshotter
```

Common issues:
- Snapshot CRDs not installed
- VolumeSnapshotClass not found
- Array ID mismatch
- Source PVC not bound

### Golden Images Not Importing

```bash
# Check DataVolume status
kubectl get datavolume -n kubevirt-os-images

# Check importer pod
kubectl get pods -n kubevirt-os-images

# Check importer logs
kubectl logs -n kubevirt-os-images <importer-pod>
```

Common issues:
- Network connectivity to image source
- Storage provisioning failed
- Insufficient space
- Invalid image URL

## Performance Tips

1. **Use VolumeSnapshotClass**: Essential for fast VM cloning
2. **Enable WaitForFirstConsumer**: Better pod-to-storage affinity
3. **Configure Multipath**: Improves reliability and performance
4. **Use Jumbo Frames**: MTU 9000 on iSCSI network
5. **Separate Network**: Dedicated VLAN for storage traffic

## Best Practices

1. **Set Default Classes**: Simplifies PVC creation
2. **Monitor Capacity**: Watch PowerStore capacity usage
3. **Regular Backups**: Backup storage class and snapshot class configs
4. **Test Failover**: Verify multipath and HA work correctly
5. **Document Settings**: Keep record of array IPs, credentials, settings

## Additional Resources

- PowerStore Configuration Guide: `../../testing/powerstore-configuration-guide.md`
- Golden Images Setup: `../../testing/golden-images-setup-guide.md`
- Full Test Plan: `../../testing/powerstore-test-plan.md`
- Dell PowerStore CSI Driver: https://dell.github.io/csm-docs/docs/csidriver/installation/helm/powerstore/

## Support

For issues with:
- **PowerStore CSI Driver**: Dell support or GitHub issues
- **KubeVirt/CDI**: KubeVirt community or GitHub issues
- **Storage Checkup**: This repository's issues

---

**Last Updated**: 2025-10-22
