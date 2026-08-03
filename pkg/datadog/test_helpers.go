package datadog

// Regenerate pkg/mocks from the ClientAPI interface in datadog.go with:
//
//	mockgen -source=pkg/datadog/datadog.go -package mock_datadog -destination pkg/mocks/datadog_mock.go
//
// Source mode parses datadog.go alone, so the import cycle between this
// package and pkg/mocks does not need to be broken by hand first.

import (
	"os"

	"go.uber.org/mock/gomock"

	mocks "github.com/fairwindsops/astro/pkg/mocks"
)

// GetMock will return a mock datadog client API
func GetMock(ctrl *gomock.Controller) *mocks.MockClientAPI {
	os.Setenv("DEFINITIONS_PATH", "../config/test_conf.yml")
	os.Setenv("DD_API_KEY", "test")
	os.Setenv("DD_APP_KEY", "test")

	ddMon := GetInstance()
	ddMock := mocks.NewMockClientAPI(ctrl)
	ddMon.Datadog = ddMock

	return ddMock
}
