# logos-delivery-demo

[![CI](https://github.com/logos-co/logos-delivery-demo/actions/workflows/ci.yml/badge.svg)](https://github.com/logos-co/logos-delivery-demo/actions/workflows/ci.yml)

A small `ui_qml` module that demonstrates **how an application uses [`logos-delivery-module`](https://github.com/logos-co/logos-delivery-module)** to send and receive messages on the Logos messaging network.

This repo is the runnable companion to the journey doc [**Use the Logos Delivery module API from an app**](https://github.com/logos-co/logos-docs/blob/main/docs/messaging/journeys/use-the-logos-delivery-module-api-from-an-app.md) — every code path in the doc is exercised here, and every interactive control has an info button explaining which `delivery_module` API call it triggers.

Pinned to `logos-delivery-module` [**`v0.2.0`**](https://github.com/logos-co/logos-delivery-module/tree/v0.2.0).

![Screenshot of the demo running on logos.dev](docs/screenshot.png)

## What it shows

- Declaring `delivery_module` as a Logos module dependency (in `metadata.json` and `flake.nix`)
- Constructing the typed `LogosModules` wrapper from `LogosAPI*` in `initLogos`
- Bootstrapping the node from the UI with `createNode(...)` and `start()`, with `LogosResult` checks — the fleet (`logos.test` / `logos.dev`, defaulting to `logos.test`) and node mode (`Core` / `Edge`) are picked from dropdowns
- Polling `delivery_module.getNodeInfo("MyPeerId")` for my peer ID every 3s, and reading the `logos-delivery` library version once at startup (`getNodeInfo("Version")`)
- Surfacing `connectionStateChanged` as a live status badge
- The **Reliable Channels API**: `channelCreate(channelId, contentTopic, senderId)` / `channelExists` / `channelSend` / `channelClose`, with the `channelMessageReceived` / `channelMessageSent` / `channelMessageError` events surfaced in the event log
- A **global event log** that renders every observed event verbatim — `messageReceived`, `messageSent`, `messagePropagated`, `messageError`, `channelMessageReceived`, `channelMessageSent`, `channelMessageError`, plus the local return values of every playground call — colour-coded by event kind, with every field selectable so you can copy hashes, topics, payloads, request ids
- A **method-call playground** at the bottom: one card per public `delivery_module` API call, rendered as `methodName(arg…)` with a `Call` button — every interaction is reflected as a row in the event log above. `createNode` spans the full width on top; below it the calls are grouped side by side into **Messaging** (`subscribe`, `unsubscribe`, `send`) and **Reliable Channels** (`channelCreate`, `channelExists`, `channelSend`, `channelClose`). `createNode`'s two arguments are fixed-choice enums picked from dropdowns; message payloads are raw **bytes**: a global **Payload format** dropdown in the header switches between **HEX** and **UTF-8** for both payload entry and how payloads render in the event log (switching re-renders payloads already logged)
- An info `?` chip next to every interactive element with a tooltip spelling out the exact `delivery_module` call behind it — the demo doubles as live API documentation
- Using **[`Logos.Theme`](https://github.com/logos-co/logos-design-system) and `Logos.Controls`** for tokens, colors, and themed components — no hard-coded styling in the demo

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
├── flake.nix                            # pins delivery_module to v0.2.0
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

The node is **not** started automatically. Use the `createNode` row in the method-call playground to create and start it against a chosen network: pick the preset — **`logos.test`** (Logos Test Network, the default) or **`logos.dev`** (Logos Dev Network) — and the node **mode** — `Core` (full relay node) or `Edge` (light node). `createNode` can be called once per session; the other API calls stay disabled until the node is ready. To switch fleet/mode, restart the app.

### Sharing the node with other modules

`delivery_module` is a singleton per Logos Core instance, and so is its node. The demo never assumes it created that node: it reads the node's attributes from the module (`getNodeInfo`) when the view opens and on the `nodeStarted` event, clears them on `nodeStopped`, and takes everything else from the module's events. So when another module (e.g. the chat module) creates the node, the demo shows it like any other — peer id, version, live events — and `createNode` is disabled because the node already exists; the fleet/mode chosen by that module apply.

The flip side of a shared node: the event log shows *all* of the node's traffic, including other modules', and `unsubscribe` / `channelClose` affect topics and channels other modules opened.

### Running multiple instances on one machine

Give each instance its own session directory with `--user-dir`:

```bash
# terminal A
nix run . -- --user-dir ~/.local/share/delivery_demo_a
# terminal B
nix run . -- --user-dir ~/.local/share/delivery_demo_b
```

Then subscribe both to the same content topic and send from one — the other fires `messageReceived`. For channels, run `channelCreate` on both with the *same* `channelId`, then `channelSend` from one and watch `channelMessageReceived` on the other.

The demo specifies no ports, and its layered config gets ephemeral p2p ports from `logos-delivery` (defaulted to `0`), so the OS assigns free ports per instance — the underlying waku listeners (TCP, discv5, …) don't collide.

`--user-dir` is what keeps the two nodes' **storage** apart: the standalone app hands every module its own directory under `<session dir>/module_data`, and the delivery module points the node's storage there. Without it every instance shares the default application data location.

## References

- [Journey doc — Use the Logos Delivery module API from an app](https://github.com/logos-co/logos-docs/blob/main/docs/messaging/journeys/use-the-logos-delivery-module-api-from-an-app.md)
- [`logos-delivery-module` @ v0.2.0](https://github.com/logos-co/logos-delivery-module/tree/v0.2.0) — the module this demo drives
- [`logos-module-builder` — the Nix flake library this demo builds with](https://github.com/logos-co/logos-module-builder)
- [Logos module developer guide](https://github.com/logos-co/logos-tutorial/blob/master/logos-developer-guide.md) — full walkthrough of module dev, `LogosResult`, generated wrappers
- [LIP-23 — content topic format](https://lip.logos.co/messaging/informational/23/topics.html)

## License

Dual-licensed under MIT and Apache 2.0, matching the rest of the Logos module ecosystem.
