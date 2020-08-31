module github.com/hashicorp/vault/plugins/database/mockv5

go 1.14

replace github.com/hashicorp/vault/sdk => ../../../sdk/

require (
	github.com/hashicorp/go-hclog v0.14.1
	github.com/hashicorp/vault/api v1.0.5-0.20200519221902-385fac77e20f
	github.com/hashicorp/vault/sdk v0.1.14-0.20200519221530-14615acda45f
	github.com/ryboe/q v1.0.12
)
