{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  # Pull the pre-built delivery module (and its liblogosdelivery chain) from
  # the self-hosted Logos Attic cache, for local builds too — CI configures its
  # substituters itself. Read-only and public; see infra-ci#263. Only the
  # public (default-branch-built) cache belongs here; ci is CI-only by design.
  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    # Same release logos-delivery-module pins. Below 0.2.5 binary event
    # payloads arrive empty (logos-cpp-sdk#99).
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.2.5";
    # follows keeps the module on our builder: emitter and consumer must agree
    # on the binary event wire form.
    delivery_module = {
      url = "github:logos-co/logos-delivery-module/v0.2.1";
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
