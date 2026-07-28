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
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    delivery_module.url = "github:logos-co/logos-delivery-module/v0.1.3";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
