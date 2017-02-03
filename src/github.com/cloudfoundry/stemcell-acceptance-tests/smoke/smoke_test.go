package smoke_test

import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/cloudfoundry/bosh-utils/system"
	boshlog "github.com/cloudfoundry/bosh-utils/logger"
	"os"
	"fmt"
	"path/filepath"
	"io/ioutil"
	"text/template"
	"encoding/json"
)

const BOSH_BINARY string = "gobosh"

var _ = Describe("Stemcell", func() {
	BeforeEach(func() {
		assertRequiredParams()
		login()
		uploadRelease()

		switch iaas := os.Getenv("IAAS"); iaas {
		case "vbox":
			uploadStemcell(iaas)
			updateVboxCloudConfig()
		default:
			uploadStemcell(iaas)
			updateVsphereCloudConfig()
		}

		deploy()
	})

	AfterSuite(func() {
		stdOut, stdErr, exitStatus, err := system.NewExecCmdRunner(boshlog.NewLogger(boshlog.LevelNone)).RunCommand(BOSH_BINARY, "-n", "clean-up")
		Expect(err).ToNot(HaveOccurred())
		Expect(exitStatus).To(Equal(0), fmt.Sprintf("stdOut: %s \n stdErr: %s", stdOut, stdErr))
	})

	Context("When syslog release has been deployed", func() {
		It("hello", func() {
			Expect(true).To(BeTrue())
		})
		//BeforeEach(func() {
		//	system.NewExecCmdRunner(nil).RunCommand()
		//
		//})
		//It("Should trigger auditd event", func() {
		//
		//	system.NewExecCmdRunner(nil).RunCommand()
		//})
	})
})

func login() {
	stdOut, stdErr, exitStatus, err := system.NewExecCmdRunner(boshlog.NewLogger(boshlog.LevelNone)).RunCommand(BOSH_BINARY, "login")
	Expect(err).ToNot(HaveOccurred())
	Expect(exitStatus).To(Equal(0), fmt.Sprintf("stdOut: %s \n stdErr: %s", stdOut, stdErr))
}

func deploy() {
	syslogReleaseVersion, err := ioutil.ReadFile("../syslog-release/version")
	Expect(err).ToNot(HaveOccurred())
	stemcellVersion, err := ioutil.ReadFile("../stemcell/version")
	Expect(err).ToNot(HaveOccurred())
	tempFile, err := ioutil.TempFile(os.TempDir(), "manifest")
	Expect(err).ToNot(HaveOccurred())
	contents, err := ioutil.ReadFile("../assets/manifest.yml")
	Expect(err).ToNot(HaveOccurred())
	template, err := template.New("syslog-release").Parse(string(contents))
	Expect(err).ToNot(HaveOccurred())
	err = template.Execute(tempFile, struct {
		SyslogReleaseVersion string
		StemcellVersion      string
	}{
		SyslogReleaseVersion: string(syslogReleaseVersion),
		StemcellVersion:      string(stemcellVersion),
	})
	Expect(err).ToNot(HaveOccurred())
	manifestPath, err := filepath.Abs(tempFile.Name())
	Expect(err).ToNot(HaveOccurred())
	stdOut, stdErr, exitStatus, err := system.NewExecCmdRunner(boshlog.NewLogger(boshlog.LevelNone)).RunCommand(BOSH_BINARY, "-n", "-d", "bosh-stemcell-smoke-tests", "deploy", manifestPath)
	Expect(err).ToNot(HaveOccurred())
	Expect(exitStatus).To(Equal(0), fmt.Sprintf("stdOut: %s \n stdErr: %s", stdOut, stdErr))
}

type VsphereEnvironmentResource struct {
	DNS         string `json:"DNS"`
	Description string `json:"_description"`
	DirectorIP  string `json:"directorIP"`
	Network1 struct {
		VCenterVLAN    string `json:"vCenterVLAN"`
		VCenterCIDR    string `json:"vCenterCIDR"`
		VCenterGateway string `json:"vCenterGateway"`
		StaticIP1      string `json:"staticIP-1"`
		StaticIP2      string `json:"staticIP-2"`
		ReservedRange  string `json:"reservedRange"`
		StaticRange    string `json:"staticRange"`
		DynamicRange   string `json:"_dynamicRange"`
		VCenterNetmask string `json:"vCenterNetmask"`
	} `json:"network1"`
	Network2 struct {
		VCenterVLAN    string `json:"vCenterVLAN"`
		VCenterCIDR    string `json:"vCenterCIDR"`
		VCenterGateway string `json:"vCenterGateway"`
		StaticIP1      string `json:"staticIP-1"`
		ReservedRange  string `json:"reservedRange"`
		StaticRange    string `json:"staticRange"`
		DynamicRange   string `json:"_dynamicRange"`
	} `json:"network2"`
	BoshVsphereVcenterDc      string
	BoshVsphereVcenterCluster string
}

func updateVboxCloudConfig() {
	stdOut, stdErr, exitStatus, err := system.NewExecCmdRunner(boshlog.NewLogger(boshlog.LevelNone)).RunCommand(
		BOSH_BINARY,
		"-n",
		"update-cloud-config",
		"../assets/vbox/cloud-config.yml",
	)

	Expect(err).ToNot(HaveOccurred())
	Expect(exitStatus).To(Equal(0), fmt.Sprintf("stdOut: %s \n stdErr: %s", stdOut, stdErr))
}

func updateVsphereCloudConfig() {
	environmentResource := &VsphereEnvironmentResource{}
	metadataContents, err := ioutil.ReadFile("../environment/metadata")

	err = json.Unmarshal(metadataContents, environmentResource)
	Expect(err).ToNot(HaveOccurred())
	environmentResource.BoshVsphereVcenterDc = os.Getenv("BOSH_VSPHERE_VCENTER_DC")
	environmentResource.BoshVsphereVcenterCluster = os.Getenv("BOSH_VSPHERE_VCENTER_CLUSTER")

	stdOut, stdErr, exitStatus, err := system.NewExecCmdRunner(boshlog.NewLogger(boshlog.LevelNone)).RunCommand(
		BOSH_BINARY,
		"-n",
		"update-cloud-config",
		"../assets/vsphere/cloud-config.yml",
		"-v", "vcenter_dc="+environmentResource.BoshVsphereVcenterDc,
		"-v", "vcenter_cluster="+environmentResource.BoshVsphereVcenterCluster,
		"-v", "internal_cidr="+environmentResource.Network1.VCenterCIDR,
		"-v", "internal_reserved=["+environmentResource.Network1.ReservedRange+"]",
		"-v", "internal_gw="+environmentResource.Network1.VCenterGateway,
		"-v", "internal_vcenter_vlan="+environmentResource.Network1.VCenterVLAN,
	)
	Expect(err).ToNot(HaveOccurred())
	Expect(exitStatus).To(Equal(0), fmt.Sprintf("stdOut: %s \n stdErr: %s", stdOut, stdErr))
}

func uploadRelease() {
	releasePaths, err := filepath.Glob(filepath.Join("..", "syslog-release", "*.tgz"))
	Expect(err).ToNot(HaveOccurred())
	Expect(releasePaths).To(HaveLen(1))
	stdOut, stdErr, exitStatus, err := system.NewExecCmdRunner(boshlog.NewLogger(boshlog.LevelNone)).RunCommand(BOSH_BINARY, "upload-release", releasePaths[0])
	Expect(err).ToNot(HaveOccurred())
	Expect(exitStatus).To(Equal(0), fmt.Sprintf("stdOut: %s \n stdErr: %s", stdOut, stdErr))
}

func assertRequiredParams() {
	_, ok := os.LookupEnv("BOSH_ENVIRONMENT")
	Expect(ok).To(BeTrue(), "BOSH_ENVIRONMENT was not set")
	_, ok = os.LookupEnv("BOSH_CLIENT")
	Expect(ok).To(BeTrue(), "BOSH_CLIENT was not set")
	_, ok = os.LookupEnv("BOSH_CLIENT_SECRET")
	Expect(ok).To(BeTrue(), "BOSH_CLIENT_SECRET was not set")
	_, ok = os.LookupEnv("BOSH_CA_CERT")
	Expect(ok).To(BeTrue(), "BOSH_CA_CERT was not set")
	_, ok = os.LookupEnv("BOSH_VSPHERE_VCENTER_DC")
	Expect(ok).To(BeTrue(), "BOSH_VSPHERE_VCENTER_DC was not set")
	_, ok = os.LookupEnv("BOSH_VSPHERE_VCENTER_CLUSTER")
	Expect(ok).To(BeTrue(), "BOSH_VSPHERE_VCENTER_CLUSTER was not set")
}

func uploadStemcell(iaas string) {
	stemcellPaths, err := filepath.Glob(filepath.Join("..", "stemcell", iaas, "*.tgz"))
	Expect(err).ToNot(HaveOccurred())
	Expect(stemcellPaths).To(HaveLen(1))
	stdOut, stdErr, exitStatus, err := system.NewExecCmdRunner(boshlog.NewLogger(boshlog.LevelNone)).RunCommand(BOSH_BINARY, "upload-stemcell", stemcellPaths[0])
	Expect(err).ToNot(HaveOccurred())
	Expect(exitStatus).To(Equal(0), fmt.Sprintf("stdOut: %s \n stdErr: %s", stdOut, stdErr))
}