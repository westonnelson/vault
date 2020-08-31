package mockv4

import (
	"context"
	"fmt"
	"time"

	log "github.com/hashicorp/go-hclog"
	"github.com/hashicorp/vault/api"
	"github.com/hashicorp/vault/sdk/database/dbplugin"
	"github.com/ryboe/q"
)

const mockV4Type = "mockv4"

// MockDatabase is an implementation of Database interface
type MockDatabase struct {
	config map[string]interface{}
}

var _ dbplugin.Database = &MockDatabase{}

// New returns a new in-memory instance
func New() (interface{}, error) {
	db := new()
	// Add error sanitization if any values shouldn't be included in error messages
	// dbType := dbplugin.NewDatabaseErrorSanitizerMiddleware(db, db.secretValues)
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

	dbplugin.Serve(dbType.(dbplugin.Database), api.VaultPluginTLSProvider(apiTLSConfig))

	return nil
}

func (m MockDatabase) Init(ctx context.Context, config map[string]interface{}, verifyConnection bool) (saveConfig map[string]interface{}, err error) {
	log.Default().Info("Init called",
		"config", config,
		"verifyConnection", verifyConnection)
	q.Q("Init", config, verifyConnection)

	return config, nil
}

func (m MockDatabase) Initialize(ctx context.Context, config map[string]interface{}, verifyConnection bool) (err error) {
	_, err = m.Init(ctx, config, verifyConnection)
	return err
}

func (m MockDatabase) CreateUser(ctx context.Context, statements dbplugin.Statements, usernameConfig dbplugin.UsernameConfig, expiration time.Time) (username string, password string, err error) {
	log.Default().Info("CreateUser called",
		"statements", statements,
		"usernameConfig", usernameConfig,
		"expiration", expiration)
	q.Q("CreateUser", statements, usernameConfig, expiration)

	now := time.Now()
	user := fmt.Sprintf("user_%s", now.Format(time.RFC3339))
	pass, err := m.GenerateCredentials(ctx)
	if err != nil {
		return "", "", fmt.Errorf("failed to generate credentials: %w", err)
	}
	q.Q("CreateUser returning", user, pass)
	return user, pass, nil
}

func (m MockDatabase) RenewUser(ctx context.Context, statements dbplugin.Statements, username string, expiration time.Time) error {
	log.Default().Info("RenewUser called",
		"statements", statements,
		"username", username,
		"expiration", expiration)
	q.Q("RenewUser", statements, username, expiration)

	return nil
}

func (m MockDatabase) RevokeUser(ctx context.Context, statements dbplugin.Statements, username string) error {
	log.Default().Info("RevokeUser called",
		"statements", statements,
		"username", username)
	q.Q("RevokeUser", statements, username)

	return nil
}

func (m MockDatabase) RotateRootCredentials(ctx context.Context, statements []string) (config map[string]interface{}, err error) {
	log.Default().Info("RotateRootCredentials called",
		"statements", statements)
	q.Q("RotateRootCredentials", statements)

	newPassword, err := m.GenerateCredentials(ctx)
	if err != nil {
		return config, fmt.Errorf("failed to generate credentials: %w", err)
	}
	config["password"] = newPassword

	return m.config, nil
}

func (m MockDatabase) SetCredentials(ctx context.Context, statements dbplugin.Statements, staticConfig dbplugin.StaticUserConfig) (username string, password string, err error) {
	log.Default().Info("SetCredentials called",
		"statements", statements,
		"staticConfig", staticConfig)
	q.Q("SetCredentials", statements, staticConfig)
	return "", "", nil
}

func (m MockDatabase) GenerateCredentials(ctx context.Context) (password string, err error) {
	q.Q("GenerateCredentials")
	now := time.Now()
	pass := fmt.Sprintf("password_%s", now.Format(time.RFC3339))
	return pass, nil
}

func (m MockDatabase) Type() (string, error) {
	q.Q("Type")
	return mockV4Type, nil
}

func (m MockDatabase) Close() error {
	log.Default().Info("Close called")
	q.Q("Close")
	return nil
}
