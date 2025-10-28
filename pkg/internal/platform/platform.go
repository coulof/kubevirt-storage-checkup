package platform

import (
	"context"
	"fmt"

	configv1 "github.com/openshift/api/config/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Type represents the Kubernetes platform flavor
type Type string

const (
	OpenShift  Type = "openshift"
	VanillaK8s Type = "vanilla-k8s"
	Unknown    Type = "unknown"
)

// String returns the string representation of the platform type
func (t Type) String() string {
	return string(t)
}

// Client interface for platform detection
// This matches the GetClusterVersion method in pkg/internal/client/client.go
type Client interface {
	GetClusterVersion(ctx context.Context, name string) (*configv1.ClusterVersion, error)
}

// Detector detects the current platform
type Detector struct {
	client Client
}

// NewDetector creates a new platform detector
func NewDetector(client Client) *Detector {
	return &Detector{client: client}
}

// Detect attempts to determine the platform by probing for OpenShift APIs
// Returns:
//   - OpenShift if ClusterVersion resource is accessible
//   - VanillaK8s if ClusterVersion is not found (NotFound error or no such resource)
//   - Unknown with error for other failure cases
func (d *Detector) Detect(ctx context.Context) (Type, error) {
	_, err := d.client.GetClusterVersion(ctx, "version")

	if err == nil {
		// Successfully retrieved ClusterVersion - this is OpenShift
		return OpenShift, nil
	}

	// Check if error is "not found" - indicates vanilla K8s
	if errors.IsNotFound(err) {
		return VanillaK8s, nil
	}

	// Check if error is "resource not found" (API doesn't exist)
	if isResourceNotFoundError(err) {
		return VanillaK8s, nil
	}

	// Some other error occurred - can't determine platform
	return Unknown, fmt.Errorf("failed to detect platform: %w", err)
}

// isResourceNotFoundError checks if the error is a "no matches for kind" error
// This occurs when the ClusterVersion CRD doesn't exist (vanilla K8s)
func isResourceNotFoundError(err error) bool {
	if err == nil {
		return false
	}

	// Check for NoResourceMatchError
	if errors.IsNotFound(err) {
		return true
	}

	// Check for GroupDiscoveryFailedError or similar
	statusErr, ok := err.(*errors.StatusError)
	if !ok {
		return false
	}

	// Check if it's a NotFound for the clusterversions resource
	if statusErr.ErrStatus.Reason == metav1.StatusReasonNotFound {
		return true
	}

	// Check the group/resource in details
	if statusErr.ErrStatus.Details != nil {
		if statusErr.ErrStatus.Details.Group == "config.openshift.io" &&
			statusErr.ErrStatus.Details.Kind == "clusterversions" {
			return true
		}
	}

	return false
}

// ParseType converts a string to a platform Type
func ParseType(s string) (Type, error) {
	switch s {
	case string(OpenShift):
		return OpenShift, nil
	case string(VanillaK8s):
		return VanillaK8s, nil
	case "":
		return Unknown, nil
	default:
		return Unknown, fmt.Errorf("invalid platform type: %q (must be %q or %q)",
			s, OpenShift, VanillaK8s)
	}
}
