package platform_test

import (
	"context"
	"fmt"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	configv1 "github.com/openshift/api/config/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"

	"github.com/kiagnose/kubevirt-storage-checkup/pkg/internal/platform"
)

// Mock client for testing
type mockClient struct {
	clusterVersion *configv1.ClusterVersion
	err            error
}

func (m *mockClient) GetClusterVersion(ctx context.Context, name string) (*configv1.ClusterVersion, error) {
	return m.clusterVersion, m.err
}

func TestPlatform(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Platform Suite")
}

var _ = Describe("Platform Detection", func() {
	var (
		ctx      context.Context
		detector *platform.Detector
	)

	BeforeEach(func() {
		ctx = context.Background()
	})

	Context("When ClusterVersion exists", func() {
		It("should detect OpenShift", func() {
			client := &mockClient{
				clusterVersion: &configv1.ClusterVersion{
					ObjectMeta: metav1.ObjectMeta{Name: "version"},
				},
			}
			detector = platform.NewDetector(client)

			platformType, err := detector.Detect(ctx)
			Expect(err).ToNot(HaveOccurred())
			Expect(platformType).To(Equal(platform.OpenShift))
		})
	})

	Context("When ClusterVersion does not exist", func() {
		It("should detect VanillaK8s with NotFound error", func() {
			client := &mockClient{
				err: errors.NewNotFound(
					schema.GroupResource{Group: "config.openshift.io", Resource: "clusterversions"},
					"version",
				),
			}
			detector = platform.NewDetector(client)

			platformType, err := detector.Detect(ctx)
			Expect(err).ToNot(HaveOccurred())
			Expect(platformType).To(Equal(platform.VanillaK8s))
		})
	})

	Context("When ClusterVersion API doesn't exist", func() {
		It("should detect VanillaK8s with resource not found error", func() {
			client := &mockClient{
				err: &errors.StatusError{
					ErrStatus: metav1.Status{
						Reason: metav1.StatusReasonNotFound,
						Details: &metav1.StatusDetails{
							Group: "config.openshift.io",
							Kind:  "clusterversions",
						},
					},
				},
			}
			detector = platform.NewDetector(client)

			platformType, err := detector.Detect(ctx)
			Expect(err).ToNot(HaveOccurred())
			Expect(platformType).To(Equal(platform.VanillaK8s))
		})
	})

	Context("When detection fails with unexpected error", func() {
		It("should return Unknown with error", func() {
			expectedErr := errors.NewInternalError(fmt.Errorf("connection refused"))
			client := &mockClient{err: expectedErr}
			detector = platform.NewDetector(client)

			platformType, err := detector.Detect(ctx)
			Expect(err).To(HaveOccurred())
			Expect(platformType).To(Equal(platform.Unknown))
			Expect(err.Error()).To(ContainSubstring("failed to detect platform"))
		})
	})
})

var _ = Describe("ParseType", func() {
	It("should parse valid platform types", func() {
		platformType, err := platform.ParseType("openshift")
		Expect(err).ToNot(HaveOccurred())
		Expect(platformType).To(Equal(platform.OpenShift))

		platformType, err = platform.ParseType("vanilla-k8s")
		Expect(err).ToNot(HaveOccurred())
		Expect(platformType).To(Equal(platform.VanillaK8s))

		platformType, err = platform.ParseType("")
		Expect(err).ToNot(HaveOccurred())
		Expect(platformType).To(Equal(platform.Unknown))
	})

	It("should return error for invalid platform type", func() {
		_, err := platform.ParseType("invalid")
		Expect(err).To(HaveOccurred())
		Expect(err.Error()).To(ContainSubstring("invalid platform type"))
	})
})

var _ = Describe("Type.String", func() {
	It("should return correct string representation", func() {
		Expect(platform.OpenShift.String()).To(Equal("openshift"))
		Expect(platform.VanillaK8s.String()).To(Equal("vanilla-k8s"))
		Expect(platform.Unknown.String()).To(Equal("unknown"))
	})
})
