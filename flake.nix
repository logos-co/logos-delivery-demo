{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  # Pull the pre-built delivery module (and its liblogosdelivery chain) from
  # the self-hosted Logos Attic cache, for local builds too — CI configures its
  # substituters itself. Read-only and public; see infra-ci#263. Only the
  # public (default-branch-built) cache belongs here; ci is CI-only by design.
  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:zaDAOkd+E3cQyFm9J7qejQYd9HoLJc1SJvnk68hNWeI=" ];
  };

  inputs = {
    # Same release logos-delivery-module pins. Below 0.2.5 binary event
    # payloads arrive empty (logos-cpp-sdk#99).
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.3.1";
    # follows keeps the module on our builder: emitter and consumer must agree
    # on the binary event wire form.
    delivery_module = {
      url = "github:logos-co/logos-delivery-module/v0.4.0-rc.1";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.liblogos_rln_module.follows = "liblogos_rln_module";
    };
    # The demo reads RLN state itself, so it needs its own generated client:
    # the builder resolves a declared dependency only from a same-named input.
    # delivery_module follows this one — two instances would bundle twice.
    liblogos_rln_module.url = "git+https://github.com/logos-co/logos-rln-modules?ref=main&rev=a814e7feda974a16eaa5dd50667b8fd843177f0e&dir=logos-rln-module";
    # Must match delivery_module's lez pin; follows drops its own override.
    liblogos_rln_module.inputs.liblogos_lez_rln_module.url = "git+https://github.com/logos-co/logos-rln-modules?ref=main&rev=a814e7feda974a16eaa5dd50667b8fd843177f0e&dir=logos-lez-rln-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
