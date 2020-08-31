package main

import (
	"log"
	"os"

	"github.com/hashicorp/vault/api"
	"github.com/hashicorp/vault/plugins/database/mockv4"
)

func main() {
	apiClientMeta := &api.PluginAPIClientMeta{}
	flags := apiClientMeta.FlagSet()
	flags.Parse(os.Args[1:])

	err := mockv4.Run(apiClientMeta.GetTLSConfig())
	if err != nil {
		log.Println(err)
		os.Exit(1)
	}
}
