{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  inputs = {
    # 0.2.5 — the same release logos-delivery-module pins (its #70). Carries
    # logos-cpp-sdk#100/#102: before those, a bstr event argument was
    # serialized as an empty tagged value, so every binary event payload
    # (messageReceived, channelMessageReceived) arrived EMPTY (cpp-sdk#99).
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.2.5";
    # Pinned to logos-delivery-module PR #68 (feat: add Reliable Channels API
    # support) until it merges and a release tag includes the channel API.
    # That branch predates the module's own 0.2.5 bump, so force it onto ours —
    # emitter and consumer must agree on the tagged {"_bytes": base64url} wire
    # form for binary event payloads.
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
