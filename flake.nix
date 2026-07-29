{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  inputs = {
    # Same release logos-delivery-module pins. Below 0.2.5 binary event
    # payloads arrive empty (logos-cpp-sdk#99).
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.2.5";
    # follows keeps the module on our builder: emitter and consumer must agree
    # on the binary event wire form.
    delivery_module = {
      url = "github:logos-co/logos-delivery-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
