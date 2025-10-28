# PR Review Guide: Multi-Platform Support

## Overview
This PR adds vanilla Kubernetes support while maintaining full OpenShift compatibility. The checkup now auto-detects the platform and adapts its behavior accordingly.

**Total Changes**: 8 commits, 12 files modified, 3 new manifests, ~400 lines changed

---

## Commit-by-Commit Review

### 1️⃣ Platform Detection Infrastructure
**Files**: `pkg/internal/platform/`, `config.go`, `status.go`

**What**: New package to detect OpenShift vs vanilla K8s
- Auto-detection via ClusterVersion API presence
- Manual override via `platform` config parameter
- New config field: `goldenImagesNamespace`

**Review Focus**: Detection logic soundness

---

### 2️⃣ Optional OpenShift Client
**Files**: `pkg/internal/client/client.go`

**What**: Makes OpenShift APIs optional
- Graceful degradation when OpenShift APIs unavailable
- New methods: `GetKubeVirt()`, `GetKubernetesVersion()`
- Returns NotFound instead of failing on vanilla K8s

**Review Focus**: Error handling for missing APIs

---

### 3️⃣ Platform-Specific Version Detection
**Files**: `checkup.go`, `reporter.go`, `reporter_test.go`, `mainflow.go`

**What**: Split version detection by platform
- OpenShift: OCP + CNV versions
- Vanilla K8s: Kubernetes + KubeVirt versions
- Platform validation in mainflow

**Review Focus**: Version extraction logic, reporter fields

---

### 4️⃣ Golden Images Support
**Files**: `checkup/vmi.go`, `checkup/vmi/spec.go`

**What**: Platform-aware golden image namespace
- OpenShift: Default `openshift-virtualization-os-images`
- Vanilla K8s: Configurable via `goldenImagesNamespace`
- TPM device support

**Review Focus**: Namespace selection logic

---

### 5️⃣ RBAC Permissions Update
**Files**: `manifests/storage_checkup_permissions.yaml`

**What**: Add missing permissions for golden images
- `pods: get` - Golden image pod inspection
- `persistentvolumeclaims: get, list` - PVC discovery

**Review Focus**: Minimal permissions principle

---

### 6️⃣ Vanilla K8s Manifests
**Files**: `manifests/storage_checkup_*.yaml` (3 new files)

**What**: Cluster-scoped RBAC for vanilla K8s
- ClusterRole: Cluster-wide resource access
- CDI cloner: DataVolume cloning
- Golden images: Cross-namespace access

**Review Focus**: Security implications of ClusterRole

---

### 7️⃣ Test Updates
**Files**: `pkg/internal/checkup/checkup_test.go`

**What**: Add mocks for new methods
- `GetKubeVirt()` and `GetKubernetesVersion()` stubs
- Updated test expectations

**Review Focus**: Test coverage adequacy

---

### 8️⃣ Documentation & Examples
**Files**: `examples/`, `testing/`, `.gitignore`

**What**: User-facing documentation
- PowerStore examples for vanilla K8s
- Test scripts and guides
- Design documentation

**Review Focus**: Documentation clarity

---

## Key Design Decisions

1. **Auto-detection First**: Platform is detected automatically, manual override available
2. **Backward Compatible**: No breaking changes for OpenShift users
3. **Graceful Degradation**: Missing APIs don't crash the checkup
4. **Namespace Flexibility**: Vanilla K8s requires golden images namespace config

---

## Testing Checklist

- [ ] OpenShift deployment (existing behavior preserved)
- [ ] Vanilla K8s deployment (new functionality)
- [ ] Platform auto-detection works correctly
- [ ] Version reporting accurate for both platforms
- [ ] Golden images work with configured namespace
- [ ] RBAC permissions sufficient but minimal

---

## Questions for Reviewer

1. Are cluster-scoped permissions acceptable for vanilla K8s deployment?
2. Should golden images namespace be required or optional for vanilla K8s?
3. Any concerns with TPM device addition to VM spec?

---

**Estimated Review Time**: 30-45 minutes (commit-by-commit approach recommended)
