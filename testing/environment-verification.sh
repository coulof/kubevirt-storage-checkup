#!/bin/bash
# Environment Verification Script for kubevirt-storage-checkup on vanilla K8s + PowerStore
# This script verifies that the cluster is ready for testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Output file
OUTPUT_FILE="testing/test-results/environment-verification-$(date +%Y%m%d-%H%M%S).log"
mkdir -p testing/test-results

# Helper functions
log() {
    echo -e "$1" | tee -a "$OUTPUT_FILE"
}

check_pass() {
    log "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
}

check_fail() {
    log "${RED}✗ FAIL${NC}: $1"
    ((FAILED++))
}

check_warn() {
    log "${YELLOW}⚠ WARN${NC}: $1"
    ((WARNINGS++))
}

section_header() {
    log "\n=========================================="
    log "$1"
    log "==========================================\n"
}

# Start verification
log "Environment Verification for kubevirt-storage-checkup"
log "Date: $(date)"
log "Cluster: $(kubectl config current-context)\n"

# Section 1: Kubernetes Version
section_header "1. Kubernetes Version"
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}' || echo "Unable to get version")
log "Kubernetes Version: $K8S_VERSION"
if [[ ! -z "$K8S_VERSION" ]] && [[ "$K8S_VERSION" != "Unable to get version" ]]; then
    check_pass "Kubernetes API is accessible"
else
    check_fail "Unable to access Kubernetes API"
fi

# Section 2: KubeVirt Installation
section_header "2. KubeVirt Installation"
if kubectl get kubevirt -A &>/dev/null; then
    KV_NAME=$(kubectl get kubevirt -A -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    KV_NAMESPACE=$(kubectl get kubevirt -A -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
    KV_VERSION=$(kubectl get kubevirt -A -o jsonpath='{.items[0].status.observedKubeVirtVersion}' 2>/dev/null)
    log "KubeVirt CR: $KV_NAME (namespace: $KV_NAMESPACE)"
    log "KubeVirt Version: $KV_VERSION"
    check_pass "KubeVirt CR found"

    # Check KubeVirt phase
    KV_PHASE=$(kubectl get kubevirt -A -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [[ "$KV_PHASE" == "Deployed" ]]; then
        check_pass "KubeVirt is in Deployed phase"
    else
        check_warn "KubeVirt phase is $KV_PHASE (expected Deployed)"
    fi
else
    check_fail "KubeVirt CR not found"
fi

# Check KubeVirt pods
if kubectl get pods -n kubevirt -l kubevirt.io &>/dev/null; then
    KV_PODS_READY=$(kubectl get pods -n kubevirt -l kubevirt.io --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    KV_PODS_TOTAL=$(kubectl get pods -n kubevirt -l kubevirt.io --no-headers 2>/dev/null | wc -l || echo "0")
    log "KubeVirt Pods: $KV_PODS_READY/$KV_PODS_TOTAL Running"
    if [[ "$KV_PODS_READY" -eq "$KV_PODS_TOTAL" ]] && [[ "$KV_PODS_TOTAL" -gt 0 ]]; then
        check_pass "All KubeVirt pods are Running"
    else
        check_warn "Not all KubeVirt pods are Running ($KV_PODS_READY/$KV_PODS_TOTAL)"
    fi
fi

# Section 3: CDI Installation
section_header "3. CDI (Containerized Data Importer) Installation"
if kubectl get cdi -A &>/dev/null; then
    CDI_NAME=$(kubectl get cdi -A -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    CDI_VERSION=$(kubectl get cdi -A -o jsonpath='{.items[0].status.observedVersion}' 2>/dev/null || echo "N/A")
    log "CDI CR: $CDI_NAME"
    log "CDI Version: $CDI_VERSION"
    check_pass "CDI CR found"

    # Check CDI phase
    CDI_PHASE=$(kubectl get cdi -A -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [[ "$CDI_PHASE" == "Deployed" ]]; then
        check_pass "CDI is in Deployed phase"
    else
        check_warn "CDI phase is $CDI_PHASE (expected Deployed)"
    fi
else
    check_fail "CDI CR not found"
fi

# Check CDI pods
if kubectl get pods -n cdi -l cdi.kubevirt.io &>/dev/null; then
    CDI_PODS_READY=$(kubectl get pods -n cdi -l cdi.kubevirt.io --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    CDI_PODS_TOTAL=$(kubectl get pods -n cdi -l cdi.kubevirt.io --no-headers 2>/dev/null | wc -l || echo "0")
    log "CDI Pods: $CDI_PODS_READY/$CDI_PODS_TOTAL Running"
    if [[ "$CDI_PODS_READY" -eq "$CDI_PODS_TOTAL" ]] && [[ "$CDI_PODS_TOTAL" -gt 0 ]]; then
        check_pass "All CDI pods are Running"
    else
        check_warn "Not all CDI pods are Running ($CDI_PODS_READY/$CDI_PODS_TOTAL)"
    fi
fi

# Section 4: PowerStore CSI Driver
section_header "4. PowerStore CSI Driver"
if kubectl get csidriver | grep -q "csi-powerstore.dellemc.com"; then
    check_pass "PowerStore CSI Driver registered"

    # Find CSI driver namespace (common names)
    CSI_NAMESPACE=""
    for ns in csi-powerstore powerstore-csi kube-system; do
        if kubectl get pods -n $ns -l app=powerstore --no-headers 2>/dev/null | grep -q .; then
            CSI_NAMESPACE=$ns
            break
        fi
    done

    if [[ ! -z "$CSI_NAMESPACE" ]]; then
        log "CSI Driver Namespace: $CSI_NAMESPACE"
        CSI_PODS_READY=$(kubectl get pods -n $CSI_NAMESPACE -l app=powerstore --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        CSI_PODS_TOTAL=$(kubectl get pods -n $CSI_NAMESPACE -l app=powerstore --no-headers 2>/dev/null | wc -l || echo "0")
        log "CSI Driver Pods: $CSI_PODS_READY/$CSI_PODS_TOTAL Running"

        if [[ "$CSI_PODS_READY" -eq "$CSI_PODS_TOTAL" ]] && [[ "$CSI_PODS_TOTAL" -gt 0 ]]; then
            check_pass "All PowerStore CSI Driver pods are Running"
        else
            check_warn "Not all PowerStore CSI Driver pods are Running ($CSI_PODS_READY/$CSI_PODS_TOTAL)"
        fi
    else
        check_warn "Could not find PowerStore CSI Driver pods"
    fi
else
    check_fail "PowerStore CSI Driver not registered"
fi

# Section 5: Storage Classes
section_header "5. Storage Classes"
SC_COUNT=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l || echo "0")
log "Total Storage Classes: $SC_COUNT"
if [[ "$SC_COUNT" -gt 0 ]]; then
    check_pass "Storage classes found"

    # List all storage classes
    log "\nStorage Classes:"
    kubectl get storageclass --no-headers 2>/dev/null | while read line; do
        SC_NAME=$(echo $line | awk '{print $1}')
        SC_PROVISIONER=$(echo $line | awk '{print $2}')
        SC_DEFAULT=$(echo $line | grep -q "(default)" && echo "YES" || echo "NO")
        log "  - $SC_NAME (provisioner: $SC_PROVISIONER, default: $SC_DEFAULT)"
    done

    # Check for PowerStore storage class
    if kubectl get storageclass --no-headers 2>/dev/null | grep -q "csi-powerstore.dellemc.com"; then
        POWERSTORE_SC=$(kubectl get storageclass --no-headers 2>/dev/null | grep "csi-powerstore.dellemc.com" | awk '{print $1}' | head -1)
        log "\nPowerStore Storage Class: $POWERSTORE_SC"
        check_pass "PowerStore storage class found"
    else
        check_fail "No PowerStore storage class found"
    fi

    # Check for default storage class
    if kubectl get storageclass --no-headers 2>/dev/null | grep -q "(default)"; then
        DEFAULT_SC=$(kubectl get storageclass --no-headers 2>/dev/null | grep "(default)" | awk '{print $1}')
        log "Default Storage Class: $DEFAULT_SC"
        check_pass "Default storage class configured"
    else
        check_warn "No default storage class configured"
    fi
else
    check_fail "No storage classes found"
fi

# Section 6: Volume Snapshot Classes
section_header "6. Volume Snapshot Classes"
VSC_COUNT=$(kubectl get volumesnapshotclass --no-headers 2>/dev/null | wc -l || echo "0")
log "Total VolumeSnapshotClasses: $VSC_COUNT"
if [[ "$VSC_COUNT" -gt 0 ]]; then
    check_pass "VolumeSnapshotClasses found"

    # List all VolumeSnapshotClasses
    log "\nVolumeSnapshotClasses:"
    kubectl get volumesnapshotclass --no-headers 2>/dev/null | while read line; do
        VSC_NAME=$(echo $line | awk '{print $1}')
        VSC_DRIVER=$(echo $line | awk '{print $2}')
        log "  - $VSC_NAME (driver: $VSC_DRIVER)"
    done

    # Check for PowerStore VolumeSnapshotClass
    if kubectl get volumesnapshotclass --no-headers 2>/dev/null | grep -q "csi-powerstore.dellemc.com"; then
        POWERSTORE_VSC=$(kubectl get volumesnapshotclass --no-headers 2>/dev/null | grep "csi-powerstore.dellemc.com" | awk '{print $1}' | head -1)
        log "\nPowerStore VolumeSnapshotClass: $POWERSTORE_VSC"
        check_pass "PowerStore VolumeSnapshotClass found"
    else
        check_warn "No PowerStore VolumeSnapshotClass found (snapshots may not work)"
    fi
else
    check_warn "No VolumeSnapshotClasses found (snapshots will not work)"
fi

# Section 7: Storage Profiles
section_header "7. Storage Profiles"
if kubectl get storageprofile &>/dev/null; then
    SP_COUNT=$(kubectl get storageprofile --no-headers 2>/dev/null | wc -l || echo "0")
    log "Total StorageProfiles: $SP_COUNT"
    if [[ "$SP_COUNT" -gt 0 ]]; then
        check_pass "StorageProfiles found"

        # Check if PowerStore storage class has a profile
        if [[ ! -z "$POWERSTORE_SC" ]]; then
            if kubectl get storageprofile "$POWERSTORE_SC" &>/dev/null; then
                check_pass "StorageProfile exists for PowerStore storage class"

                # Check for smart clone capability
                if kubectl get storageprofile "$POWERSTORE_SC" -o jsonpath='{.status.cloneStrategy}' 2>/dev/null | grep -q "snapshot\|csi-clone"; then
                    CLONE_STRATEGY=$(kubectl get storageprofile "$POWERSTORE_SC" -o jsonpath='{.status.cloneStrategy}' 2>/dev/null)
                    log "Clone Strategy: $CLONE_STRATEGY"
                    check_pass "Smart clone capability detected"
                else
                    check_warn "No smart clone capability (will use host-assisted clone)"
                fi
            else
                check_warn "No StorageProfile for PowerStore storage class"
            fi
        fi
    else
        check_warn "No StorageProfiles found"
    fi
else
    check_warn "StorageProfile CRD not available (CDI may not be fully installed)"
fi

# Section 8: Golden Images
section_header "8. Golden Images (DataImportCrons)"
DIC_COUNT=$(kubectl get dataimportcron -A --no-headers 2>/dev/null | wc -l || echo "0")
log "Total DataImportCrons: $DIC_COUNT"
if [[ "$DIC_COUNT" -gt 0 ]]; then
    check_pass "DataImportCrons found"

    log "\nDataImportCrons:"
    kubectl get dataimportcron -A --no-headers 2>/dev/null | while read line; do
        DIC_NAMESPACE=$(echo $line | awk '{print $1}')
        DIC_NAME=$(echo $line | awk '{print $2}')
        log "  - $DIC_NAMESPACE/$DIC_NAME"
    done

    # Check for DataSources
    DS_COUNT=$(kubectl get datasource -A --no-headers 2>/dev/null | wc -l || echo "0")
    log "\nTotal DataSources: $DS_COUNT"
    if [[ "$DS_COUNT" -gt 0 ]]; then
        check_pass "DataSources found"
    else
        check_warn "No DataSources found (images may not be imported yet)"
    fi
else
    check_warn "No DataImportCrons found (need to create golden images for testing)"
fi

# Section 9: Nodes
section_header "9. Cluster Nodes"
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
log "Total Nodes: $NODE_COUNT"
log "Ready Nodes: $READY_NODES"
if [[ "$READY_NODES" -eq "$NODE_COUNT" ]] && [[ "$NODE_COUNT" -gt 0 ]]; then
    check_pass "All nodes are Ready"
else
    check_warn "Not all nodes are Ready ($READY_NODES/$NODE_COUNT)"
fi

# Check if single-node or multi-node
if [[ "$NODE_COUNT" -eq 1 ]]; then
    check_warn "Single-node cluster detected (live migration test will be skipped)"
else
    check_pass "Multi-node cluster detected (live migration test will run)"
fi

# List nodes
log "\nNodes:"
kubectl get nodes -o wide --no-headers 2>/dev/null | while read line; do
    NODE_NAME=$(echo $line | awk '{print $1}')
    NODE_STATUS=$(echo $line | awk '{print $2}')
    NODE_VERSION=$(echo $line | awk '{print $5}')
    log "  - $NODE_NAME ($NODE_STATUS, $NODE_VERSION)"
done

# Section 10: Test Namespace
section_header "10. Test Namespace"
TEST_NS="kubevirt-storage-checkup-test"
if kubectl get namespace "$TEST_NS" &>/dev/null; then
    check_pass "Test namespace $TEST_NS exists"
else
    check_warn "Test namespace $TEST_NS does not exist (will be created)"
fi

# Summary
section_header "VERIFICATION SUMMARY"
log "Passed:   $PASSED"
log "Failed:   $FAILED"
log "Warnings: $WARNINGS"
log "\nResults saved to: $OUTPUT_FILE"

if [[ "$FAILED" -eq 0 ]]; then
    log "${GREEN}✓ Environment verification completed successfully${NC}"
    log "The cluster is ready for testing"
    exit 0
else
    log "${RED}✗ Environment verification found issues${NC}"
    log "Please address the failed checks before proceeding"
    exit 1
fi
