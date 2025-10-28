# Testing Directory

Quick reference for running kubevirt-storage-checkup tests on vanilla Kubernetes with PowerStore storage.

---

## 🚀 Quick Start

**For step-by-step deployment and testing:**
→ **[powerstore_test_guide_engg_cluster.md](powerstore_test_guide_engg_cluster.md)**

This is the tested, validated guide for running the checkup from scratch.

---

## 📂 Files in This Directory

### Essential Test Guide
- **`powerstore_test_guide_engg_cluster.md`** - Complete deployment & testing guide
  - Prerequisites verification
  - RBAC setup (4 layers)
  - ConfigMap creation
  - Job deployment
  - Results interpretation
  - Troubleshooting

### ConfigMap Variants
- **`powerstore-configmap-basic.yaml`** - Default configuration (10 VMs, 3m timeout)
- **`powerstore-configmap-performance.yaml`** - Performance testing (20 VMs, 5m timeout)
- **`powerstore-configmap-stress.yaml`** - Stress testing (50 VMs, 10m timeout)
- **`powerstore-configmap-debug.yaml`** - Debug mode (5 VMs, skip teardown on failure)

### Setup Resources
- **`golden-images-setup.yaml`** - Creates bootable OS images (Fedora, Ubuntu, CentOS, Cirros)
- **`environment-verification.sh`** - Pre-flight cluster readiness check script

### Results
- **`test-results/`** - Directory for storing test outputs and reports

---

## 🎯 Typical Workflow

```bash
# 1. Verify cluster prerequisites
./testing/environment-verification.sh

# 2. Setup golden images (if not already done)
kubectl apply -f testing/golden-images-setup.yaml

# 3. Follow the complete guide
# See: powerstore_test_guide_engg_cluster.md
```

---

## 🔗 Related Resources

- **Root Manifests**: `../manifests/` - RBAC and Job definitions
- **PowerStore Examples**: `../examples/powerstore/` - Storage class examples
- **Implementation Details**: `../kubevirt-changes/VANILLA-K8S-IMPLEMENTATION-SUMMARY.md`
- **Migration Setup**: `LIVE-MIGRATION-ANALYSIS.md` (this directory)

---

**Last Updated**: 2025-10-28
**Container Image**: `docker.io/parasarkodati/kubevirt-storage-checkup:beta`
