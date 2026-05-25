{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    delivery_module.url = "github:logos-co/logos-delivery-module/master";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
