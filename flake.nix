{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Pinned to logos-delivery-module PR #68 (feat: add Reliable Channels API
    # support) until it merges and a release tag includes the channel API.
    delivery_module.url = "github:logos-co/logos-delivery-module/0fb3a7427b29c98ab0fa2465bcd1e90cbfdf50a3";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
