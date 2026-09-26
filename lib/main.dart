// El visor 3D de la Proteus: reproduce una grabación de la simulación de
// consola. Un dedo orbita, dos dedos (o la rueda) acercan; la cámara sigue a
// la ameba.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:proteus/visor.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'escena_proteus.dart';

void main() => runApp(const VisorApp());

class VisorApp extends StatelessWidget {
  const VisorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Proteus',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D8C), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const PantallaVisor(),
      );
}

/// Una entrada del índice de grabaciones empaquetadas.
class EntradaIndice {
  const EntradaIndice(this.archivo, this.titulo, this.detalle);
  final String archivo, titulo, detalle;
}

class PantallaVisor extends StatefulWidget {
  const PantallaVisor({super.key});

  @override
  State<PantallaVisor> createState() => _PantallaVisorState();
}

class _PantallaVisorState extends State<PantallaVisor> {
  List<EntradaIndice> _indice = const [];
  EntradaIndice? _actual;
  Grabacion? _g;
  EscenaProteus? _escena;
  String? _error;
  bool _recursosListos = false;

  double _t = 0;
  bool _reproduciendo = true;
  double _velocidad = 1;
  Cuadro? _cuadro;

  // Cámara orbital que sigue a la ameba.
  double _azimut = math.pi * 0.85;
  double _elevacion = 0.75;
  double _distancia = 16;
  vm.Vector3 _objetivo = vm.Vector3(0, 0.5, 0);
  double _distanciaInicial = 16;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  Future<void> _arrancar() async {
    try {
      // OBLIGATORIO antes de construir cualquier Material o Geometry.
      await Scene.initializeStaticResources();
      final texto =
          await rootBundle.loadString('assets/grabaciones/indice.json');
      final lista = (jsonDecode(texto) as List)
          .map((e) => EntradaIndice(e['archivo'] as String,
              e['titulo'] as String, (e['detalle'] ?? '') as String))
          .toList();
      setState(() {
        _recursosListos = true;
        _indice = lista;
      });
      if (lista.isNotEmpty) await _cargar(lista.first);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _cargar(EntradaIndice e) async {
    setState(() {
      _actual = e;
      _g = null;
      _escena = null;
    });
    final texto =
        await rootBundle.loadString('assets/grabaciones/${e.archivo}');
    final g = Grabacion.deJson(texto);
    final escena = EscenaProteus(g);
    setState(() {
      _g = g;
      _escena = escena;
      _t = 0;
      _reproduciendo = true;
      _cuadro = escena.poner(0);
      _objetivo = escena.posicion.clone()..y = 0.5;
    });
  }

  void _tick(Duration _, double dt) {
    final g = _g, escena = _escena;
    if (g == null || escena == null) return;
    if (_reproduciendo) {
      _t += dt * _velocidad;
      if (_t >= g.duracion) {
        _t = g.duracion;
        _reproduciendo = false;
      }
    }
    final c = escena.poner(_t);
    // La cámara persigue a la ameba con suavidad.
    final meta = escena.posicion.clone()..y = 0.5;
    _objetivo += (meta - _objetivo) * (1 - math.exp(-dt * 4));
    if (!identical(c, _cuadro) || _reproduciendo) {
      setState(() => _cuadro = c);
    }
  }

  Camera _camara(Duration _) {
    final ce = math.cos(_elevacion);
    final ojo = _objetivo +
        vm.Vector3(math.sin(_azimut) * ce, math.sin(_elevacion),
                math.cos(_azimut) * ce) *
            _distancia;
    return PerspectiveCamera(
        position: ojo, target: _objetivo, fovRadiansY: 50 * math.pi / 180);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    final g = _g, escena = _escena;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E2A33), Color(0xFF123F46)],
          ),
        ),
        child: Stack(children: [
          if (escena != null)
            Positioned.fill(
              child: Listener(
                onPointerSignal: (s) {
                  if (s is PointerScrollEvent) {
                    setState(() => _distancia =
                        (_distancia * math.exp(s.scrollDelta.dy * 0.001))
                            .clamp(5.0, 60.0));
                  }
                },
                child: GestureDetector(
                  onScaleStart: (_) {
                    _distanciaInicial = _distancia;
                  },
                  onScaleUpdate: (d) {
                    setState(() {
                      if (d.pointerCount >= 2) {
                        _distancia = (_distanciaInicial / d.scale)
                            .clamp(5.0, 60.0);
                      } else {
                        _azimut -= d.focalPointDelta.dx * 0.008;
                        _elevacion = (_elevacion + d.focalPointDelta.dy * 0.006)
                            .clamp(0.15, 1.45);
                      }
                    });
                  },
                  child: SceneView(escena.scene,
                      cameraBuilder: _camara, onTick: _tick),
                ),
              ),
            )
          else
            Center(
                child: Text(_recursosListos
                    ? 'Cargando grabación…'
                    : 'Preparando la escena 3D…')),
          if (g != null) ..._hud(context, g),
        ]),
      ),
    );
  }

  List<Widget> _hud(BuildContext context, Grabacion g) {
    final c = _cuadro;
    final narr = g.narrativaEn(_t);
    final muerta = g.causaDeMuerte != null && _t >= g.duracion - 0.01;
    return [
      // Arriba: qué corrida es y el selector.
      Positioned(
        left: 12,
        right: 12,
        top: 12,
        child: SafeArea(
          child: Row(children: [
            Expanded(
              child: _Panel(
                child: Row(children: [
                  const Text('🦠 ', style: TextStyle(fontSize: 18)),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<EntradaIndice>(
                        isExpanded: true,
                        value: _actual,
                        items: [
                          for (final e in _indice)
                            DropdownMenuItem(
                                value: e,
                                child: Text(e.titulo,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (e) => e == null ? null : _cargar(e),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
      // Izquierda: el medio interno.
      if (c != null)
        Positioned(
          left: 12,
          top: 84,
          width: 230,
          child: _Panel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('t = ${_t.toStringAsFixed(1)} s',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  _Barra('Energía', c.energia, const Color(0xFF8BC34A)),
                  _BarraTemperatura(c.temperatura),
                  _Barra('Integridad', c.integridad, const Color(0xFF4FC3F7)),
                  _Barra('Homeostasis', c.homeostasis, const Color(0xFFCE93D8)),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Text('Pseudópodos: ',
                        style: TextStyle(color: Colors.white70)),
                    Flexible(
                      child: Chip(
                        label: Text(_nombreAccion(c.accion)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ]),
                ]),
          ),
        ),
      // Abajo: la narrativa del teatro y los controles.
      Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (muerta)
              _Panel(
                color: const Color(0xCC7A1F1F),
                child: Text('Murió de ${g.causaDeMuerte} a los '
                    '${g.duracion.toStringAsFixed(0)} s'),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: narr == null
                  ? const SizedBox.shrink()
                  : _Panel(
                      key: ValueKey(narr.t),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🎭 ', style: TextStyle(fontSize: 18)),
                            Expanded(
                              child: Text(narr.texto,
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      height: 1.35)),
                            ),
                          ]),
                    ),
            ),
            const SizedBox(height: 8),
            _Panel(
              child: Row(children: [
                IconButton(
                  icon: Icon(_reproduciendo ? Icons.pause : Icons.play_arrow),
                  onPressed: () => setState(() {
                    if (!_reproduciendo && _t >= g.duracion) _t = 0;
                    _reproduciendo = !_reproduciendo;
                  }),
                ),
                Expanded(
                  child: Slider(
                    value: _t.clamp(0, g.duracion),
                    max: g.duracion,
                    onChanged: (v) => setState(() => _t = v),
                  ),
                ),
                PopupMenuButton<double>(
                  initialValue: _velocidad,
                  onSelected: (v) => setState(() => _velocidad = v),
                  itemBuilder: (_) => [
                    for (final v in [0.5, 1.0, 2.0, 4.0, 8.0])
                      PopupMenuItem(value: v, child: Text('×$v')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('×${_velocidad.toString().replaceAll('.0', '')}'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    ];
  }

  static String _nombreAccion(Accion a) => switch (a) {
        Accion.avanzar => 'avanzar',
        Accion.girarIzquierda => 'girar ←',
        Accion.girarDerecha => 'girar →',
        Accion.retroceder => 'retroceder',
        Accion.quieto => 'quieta',
        Accion.comer => 'comer 🍽',
      };
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color ?? const Color(0xB3102024),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _Barra extends StatelessWidget {
  const _Barra(this.nombre, this.valor, this.color);
  final String nombre;
  final double valor;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
              width: 92,
              child: Text(nombre,
                  style: const TextStyle(fontSize: 12, color: Colors.white70))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: valor.clamp(0, 1),
                minHeight: 8,
                color: color,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
        ]),
      );
}

/// La temperatura interna con su franja cómoda (0.38–0.62) marcada.
class _BarraTemperatura extends StatelessWidget {
  const _BarraTemperatura(this.t);
  final double t;

  @override
  Widget build(BuildContext context) {
    final (r, g, b) = EscenaProteus.colorDeTemperatura(t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        const SizedBox(
            width: 92,
            child: Text('Temperatura',
                style: TextStyle(fontSize: 12, color: Colors.white70))),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return SizedBox(
              height: 10,
              child: Stack(children: [
                Container(
                    decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4))),
                Positioned(
                  left: w * 0.38,
                  width: w * 0.24,
                  top: 0,
                  bottom: 0,
                  child: Container(color: Colors.white24),
                ),
                Positioned(
                  left: (w * t.clamp(0, 1)) - 4,
                  width: 8,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color.fromARGB(255, (r * 255).round(),
                          (g * 255).round(), (b * 255).round()),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ]),
            );
          }),
        ),
      ]),
    );
  }
}
