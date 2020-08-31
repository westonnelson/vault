package mockv5

import (
	"context"
	"fmt"
	"time"

	"github.com/hashicorp/vault/sdk/database/newdbplugin"

	log "github.com/hashicorp/go-hclog"
	"github.com/hashicorp/vault/api"
	"github.com/ryboe/q"
)

const mockV5Type = "mockv5"

// MockDatabase is an implementation of Database interface
type MockDatabase struct {
	config map[string]interface{}
}

var _ newdbplugin.Database = &MockDatabase{}

// New returns a new in-memory instance
func New() (interface{}, error) {
	db := new()
	// Add error sanitization if any values shouldn't be included in error messages
	// dbType := newdbplugin.NewDatabaseErrorSanitizerMiddleware(db, db.secretValues)
	return db, nil
}

func new() *MockDatabase {
	return &MockDatabase{}
}

// Run instantiates a MongoDB object, and runs the RPC server for the plugin
func Run(apiTLSConfig *api.TLSConfig) error {
	dbType, err := New()
	if err != nil {
		return err
	}

	newdbplugin.Serve(dbType.(newdbplugin.Database), api.VaultPluginTLSProvider(apiTLSConfig))

	return nil
}

func (m MockDatabase) Initialize(ctx context.Context, req newdbplugin.InitializeRequest) (newdbplugin.InitializeResponse, error) {
	log.Default().Info("Initialize called",
		"req", req)
	q.Q("Initialize", req)

	config := req.Config
	config["from-plugin"] = "this value is from the plugin itself"

	resp := newdbplugin.InitializeResponse{
		Config: req.Config,
	}
	return resp, nil
}

func (m MockDatabase) NewUser(ctx context.Context, req newdbplugin.NewUserRequest) (newdbplugin.NewUserResponse, error) {
	log.Default().Info("NewUser called",
		"req", req)
	q.Q("NewUser", req)

	now := time.Now()
	user := fmt.Sprintf("user_%s", now.Format(time.RFC3339))
	q.Q("CreateUser returning", user)
	resp := newdbplugin.NewUserResponse{
		Username: user,
	}
	return resp, nil
}

func (m MockDatabase) UpdateUser(ctx context.Context, req newdbplugin.UpdateUserRequest) (newdbplugin.UpdateUserResponse, error) {
	log.Default().Info("UpdateUser called",
		"req", req)
	q.Q("UpdateUser", req)
	return newdbplugin.UpdateUserResponse{}, nil
}

func (m MockDatabase) DeleteUser(ctx context.Context, req newdbplugin.DeleteUserRequest) (newdbplugin.DeleteUserResponse, error) {
	log.Default().Info("DeleteUser called",
		"req", req)
	q.Q("DeleteUser", req)
	return newdbplugin.DeleteUserResponse{}, nil
}

func (m MockDatabase) Type() (string, error) {
	log.Default().Info("Type called")
	q.Q("Type called")
	return mockV5Type, nil
}

func (m MockDatabase) Close() error {
	log.Default().Info("Close called")
	q.Q("Close called")
	return nil
}
