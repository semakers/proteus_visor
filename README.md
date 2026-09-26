# proteus_visor

The 3D viewer of [Proteus](https://github.com/semakers/proteus), the simulated
amoeba with a Cartesian theatre. It is a Flutter web app built with
[flutter_scene](https://pub.dev/packages/flutter_scene).

**Live demo: https://proteus.nairda-back.com**

![Proteus in the viewer](https://raw.githubusercontent.com/semakers/proteus/main/doc/proteus.gif)

It shows the amoeba, its internal gauges, the probabilities of jev's loaded
die and the narrative the theatre writes. It works in two modes:

- **Recordings.** It replays the `grabacion.json` files written by the
  console simulation, listed in `assets/grabaciones/indice.json`.
- **Live.** When the page is served by `bin/en_vivo.dart` from the Proteus
  repository, it connects over a WebSocket and shows the simulation as it
  happens. The API keys for jev and DeepSeek never reach the browser.

## Layout

The viewer depends on the Proteus core by path, so both repositories go side
by side:

```
proteus/         # the simulation
proteus_visor/   # this repository
```

## Build

flutter_scene needs Flutter 3.47 or newer.

```bash
flutter build web --release --no-wasm-dry-run
```

To watch it live, from the `proteus` folder:

```bash
ODE_LIBRARY_PATH=$PWD/native/libode.so dart run bin/en_vivo.dart
```

The code, its comments and the interface are in Spanish.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
