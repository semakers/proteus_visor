# proteus_visor

Visor 3D de la **Proteus** (la ameba del teatro cartesiano), en Flutter web
con [flutter_scene](https://pub.dev/packages/flutter_scene) 0.22.

- **Grabaciones**: reproduce los `grabacion.json` que escribe la simulación
  de consola (`assets/grabaciones/` + `indice.json`).
- **En vivo**: si lo sirve `bin/en_vivo.dart` del repo `proteus`, se conecta
  por WebSocket y muestra la simulación mientras ocurre, con el dado de jev
  y la narrativa del teatro. Las llaves de jev y DeepSeek nunca llegan al
  navegador.

## Estructura esperada

```
~/dev/proteus         # el núcleo (este visor depende de él por path)
~/dev/proteus_visor   # este repo
```

## Compilar

flutter_scene 0.22 exige Flutter ≥ 3.47 estable.

```bash
LANG=en_US.UTF-8 flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
```

Y para verlo en vivo, desde `~/dev/proteus`:

```bash
ODE_LIBRARY_PATH=$PWD/native/libode.so dart run bin/en_vivo.dart
```
