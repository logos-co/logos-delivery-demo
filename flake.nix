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
    # Pinned to the branch that carries per-channel encryption
    # (logos-co/logos-delivery-module#113), which this demo consumes. Repin to a
    # release tag once it lands.
    delivery_module = {
      url = "github:logos-co/logos-delivery-module/59e5a0f8d9371d291a29cbde14ff6905e1cf37ca";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.liblogos_rln_module.follows = "liblogos_rln_module";
    };
    # The demo reads RLN state itself, so it needs its own generated client:
    # the builder resolves a declared dependency only from a same-named input.
    # delivery_module follows this one — two instances would bundle twice.
    liblogos_rln_module.url = "git+https://github.com/logos-co/logos-rln-modules?ref=feat/lip-alignment&dir=logos-rln-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
