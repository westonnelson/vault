package main

import (
	"log"
	"os"

	"github.com/hashicorp/vault/api"
	"github.com/hashicorp/vault/plugins/database/mockv5"
)

func main() {
	apiClientMeta := &api.PluginAPIClientMeta{}
	flags := apiClientMeta.FlagSet()
	flags.Parse(os.Args[1:])

	err := mockv5.Run(apiClientMeta.GetTLSConfig())
	if err != nil {
		log.Println(err)
		os.Exit(1)
	}
}
