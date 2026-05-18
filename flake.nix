{
  description = "Logos Delivery demo — UI example showing how to use logos-delivery-module from an app";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    delivery_module.url = "github:logos-co/logos-delivery-module/v0.1.1";
    # Logos.Theme / Logos.Controls for src/qml/Main.qml. Pinned here so the
    # version is controlled per-module via this repo's flake.lock.
    logos-design-system.url = "github:logos-co/logos-design-system";
  };

  outputs = inputs@{ logos-module-builder, logos-design-system, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;

      # Bundle the design system into the .lgx (the recommended consumer
      # pattern from logos-design-system's README). It lands at the .lgx
      # variant root → pluginPath/Logos, which logos-basecamp's locked-down
      # module import path resolves. Inert under logos-standalone-app (it
      # provides the design system globally).
      postInstall = ''
        mkdir -p "$out/lib/Logos"
        cp -r ${logos-design-system}/src/qml/Logos/. "$out/lib/Logos/"
        chmod -R u+w "$out/lib/Logos"
        echo "Bundled logos-design-system into \$out/lib/Logos (per-module pinned)"
      '';
    };
}
