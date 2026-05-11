# logos-delivery-demo

A small `ui_qml` module that demonstrates **how an application uses [`logos-delivery-module`](https://github.com/logos-co/logos-delivery-module)** to send and receive messages on the Logos messaging network.

This repo is the runnable companion to the journey doc [**Use the Logos Delivery module API from an app**](https://github.com/logos-co/logos-docs/blob/main/docs/messaging/journeys/use-the-logos-delivery-module-api-from-an-app.md) — every code path in the doc is exercised here, and every interactive control has an info button explaining which `delivery_module` API call it triggers.

Pinned to `logos-delivery-module` [**`v0.1.1`**](https://github.com/logos-co/logos-delivery-module/tree/v0.1.1).

## What it shows

- Declaring `delivery_module` as a Logos module dependency (in `metadata.json` and `flake.nix`)
- Constructing the typed `LogosModules` wrapper from `LogosAPI*` in `initLogos`
- Bootstrapping the node with `createNode(...)` and `start()`, with `LogosResult` checks
- Subscribing to user-managed [LIP-23](https://lip.logos.co/messaging/informational/23/topics.html) content topics
- Sending raw-text messages and tracking their lifecycle through `messageSent` → `messagePropagated` (or `messageError`), surfaced as an inline status glyph next to each outgoing message
- Decoding incoming `messageReceived` events (payload arrives base64-encoded)
- Surfacing `connectionStateChanged` as a live health indicator
- Polling `delivery_module.getNodeInfo(...)` for my peer ID (`MyPeerId`) and peer count (parsed from the `Metrics` Prometheus text, `libp2p_peers` gauge) every 3s
- Using **[`Logos.Theme`](https://github.com/logos-co/logos-design-system) and `Logos.Controls`** for tokens, colors, and themed components — no hard-coded styling in the demo

## UI

```
┌──────────────────────────────────────────────────────────┐
│ Logos Delivery demo     ● node: <connection status>  [?] │
├──────────────────┬───────────────────────────────────────┤
│ Content topics   │ /selected/topic                    [?]│
│ ┌──────────┐ [+] │ ┌─────────────────────────────────┐   │
│ │ /a/1/x   │     │ │ ← incoming                      │   │
│ │ /a/1/y × │     │ │   outgoing →     ✓✓ propagated  │   │
│ └──────────┘     │ └─────────────────────────────────┘   │
│              [?] │ [message…              ] [Send] [?]   │
└──────────────────┴───────────────────────────────────────┘
```

The `[?]` buttons are tooltips spelling out the exact `delivery_module` method behind each control — the demo doubles as live API documentation.

## Build & run

Prerequisites: Nix with flakes enabled. macOS (aarch64/x86_64) or Linux (aarch64/x86_64).

```bash
# Build the module
nix build

# Preview the UI standalone (uses logos-standalone-app, bundled with logos-module-builder)
nix run

# Package as an installable .lgx
nix build .#lgx
# → ./result/logos-logos_delivery_demo-module.lgx
```

Install the `.lgx` into a Logos host (e.g. `logos-basecamp` or `logoscore`):

```bash
lgpm install ./result/logos-logos_delivery_demo-module.lgx --to ./modules
```

## Repository layout

```
logos-delivery-demo/
├── flake.nix                            # pins delivery_module to v0.1.1
├── metadata.json                        # type: ui_qml, deps: [delivery_module]
├── CMakeLists.txt
└── src/
    ├── logos_delivery_demo.rep          # Qt Remote Objects contract
    ├── logos_delivery_demo_interface.h  # plugin interface (discovery)
    ├── logos_delivery_demo_plugin.h     # C++ backend
    ├── logos_delivery_demo_plugin.cpp   # wires delivery_module events → QML, exposes slots
    └── qml/
        └── Main.qml                     # the UI
```

The C++ backend lives in the `ui-host` process; the QML view runs in the host application. They communicate over Qt Remote Objects (auto-generated from `logos_delivery_demo.rep`).

## Network

The demo hardcodes the **`logos.dev`** preset for the underlying `createNode` call. Configuration is intentionally not exposed in the UI — the goal is to show the `delivery_module` API surface, not act as a general-purpose chat client.

### Running multiple instances on one machine

You can run two (or more) demo instances side-by-side and watch them message each other. Each instance picks a unique port window automatically:

- Each host process (`nix run`, `logos-basecamp`, `logoscore`) gets a unique `LOGOS_INSTANCE_ID` at startup via `LogosInstance::id()`, scoping every Logos-platform unix socket (token exchange, Qt Remote Objects, …).
- The demo additionally hashes that instance ID into a **`portsShift`** value passed to `createNode`. WakuNodeConf's `portsShift` offsets *all* listener ports (TCP, REST, metrics, discv5 UDP, websocket) by the same amount, so two instances can't collide on the underlying waku ports either.

Just run `nix run` twice in separate terminals — subscribe both to the same content topic, send from one, and the other should fire `messageReceived`.

The shift is logged on startup, e.g.:

```
logos_delivery_demo: createNode portsShift= 2317 instanceId= "9f3a1c5b6e80"
```

## References

- [Journey doc — Use the Logos Delivery module API from an app](https://github.com/logos-co/logos-docs/blob/main/docs/messaging/journeys/use-the-logos-delivery-module-api-from-an-app.md)
- [`logos-delivery-module` @ v0.1.1](https://github.com/logos-co/logos-delivery-module/tree/v0.1.1)
- [`logos-module-builder` — the Nix flake library this demo builds with](https://github.com/logos-co/logos-module-builder)
- [Logos module developer guide](https://github.com/logos-co/logos-tutorial/blob/master/logos-developer-guide.md) — full walkthrough of module dev, `LogosResult`, generated wrappers
- [LIP-23 — content topic format](https://lip.logos.co/messaging/informational/23/topics.html)

## License

Dual-licensed under MIT and Apache 2.0, matching the rest of the Logos module ecosystem.
