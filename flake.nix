{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  inputs = {
    # Pinned past logos-cpp-sdk#100/#102 (in this module-builder rev's
    # closure): before those, a std::vector<uint8_t> event argument was
    # serialized as a plain JSON int array with no consumer-side decode, so
    # every binary event payload (messageReceived, channelMessageReceived)
    # arrived EMPTY (cpp-sdk#99).
    logos-module-builder.url = "github:logos-co/logos-module-builder/77ac1aef56598852e431f7e8b16628a5bf070211";
    # Pinned to logos-delivery-module PR #68 (feat: add Reliable Channels API
    # support) until it merges and a release tag includes the channel API.
    # The module's own lock still carries a pre-cpp-sdk#102 builder, so force
    # it onto ours — emitter and consumer must agree on the tagged
    # {"_bytes": base64url} wire form for binary event payloads.
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
