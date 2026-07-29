{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  inputs = {
    # Same release logos-delivery-module pins. Below 0.2.5 binary event
    # payloads arrive empty (logos-cpp-sdk#99).
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.2.5";
    # Pinned to logos-delivery-module PR #68 until the channel API lands in a
    # release tag. That branch predates the module's own 0.2.5 bump, so force
    # it onto ours — emitter and consumer must agree on the wire form.
    delivery_module = {
      url = "github:logos-co/logos-delivery-module/0fb3a7427b29c98ab0fa2465bcd1e90cbfdf50a3";
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
