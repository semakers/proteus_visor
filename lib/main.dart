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

import 'en_vivo.dart';
import 'escena_proteus.dart';

const _entradaVivo = EntradaIndice('__vivo__',
    '🔴 En vivo: la simulación corre ahora mismo', '');

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

  ConexionEnVivo? _vivo;
  bool _modoVivo = false;
  int _generacionVista = -1;
  bool _seguirBorde = true;
  String _cerebroVivo = 'teatro-m';
  int _semillaVivo = 1;
  double _segundosVivo = 120;

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
      // ¿Nos sirvió el servidor en vivo? Entonces hay WebSocket.
      final url = ConexionEnVivo.urlDesde(Uri.base);
      ConexionEnVivo? vivo;
      if (url != null) {
        final c = ConexionEnVivo(url);
        if (await c.conectar()) {
          vivo = c..addListener(_alCambiarVivo);
        }
      }
      setState(() {
        _recursosListos = true;
        _vivo = vivo;
        _indice = [if (vivo != null) _entradaVivo, ...lista];
      });
      if (_indice.isNotEmpty) await _cargar(_indice.first);
      // Enlace directo: ?iniciar=teatro-m&semilla=3&segundos=120
      final q = Uri.base.queryParameters;
      if (vivo != null && q['iniciar'] != null && !vivo.corriendo) {
        _cerebroVivo = q['iniciar']!;
        _semillaVivo = int.tryParse(q['semilla'] ?? '') ?? _semillaVivo;
        _segundosVivo = double.tryParse(q['segundos'] ?? '') ?? _segundosVivo;
        vivo.iniciar(_cerebroVivo, _semillaVivo, _segundosVivo);
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _alCambiarVivo() {
    final v = _vivo;
    if (v == null || !_modoVivo) return;
    if (v.generacion != _generacionVista && v.g != null) {
      _generacionVista = v.generacion;
      final escena = EscenaProteus(v.g!);
      _g = v.g;
      _escena = escena;
      _t = 0;
      _seguirBorde = true;
      _objetivo = vm.Vector3(0, 0.5, 0);
    }
    setState(() {});
  }

  Future<void> _cargar(EntradaIndice e) async {
    setState(() {
      _actual = e;
      _g = null;
      _escena = null;
      _modoVivo = e.archivo == _entradaVivo.archivo;
      _generacionVista = -1;
    });
    if (_modoVivo) {
      _alCambiarVivo();
      return;
    }
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
    if (_modoVivo) {
      // En vivo se reproduce a tiempo real un poco detrás del último cuadro
      // recibido; si jev o el teatro tardan, se espera en el borde.
      final borde = g.duracion;
      if (_seguirBorde) {
        // Medio segundo de colchón: jev manda los cuadros en ráfagas cada
        // ~250 ms (picos de 350); con menos, el visor alcanzaba el borde y
        // titubeaba. Nunca retrocede; si se queda muy atrás, salta.
        final meta = borde - 0.5;
        if (_t < meta - 1.5) {
          _t = meta;
        } else if (_t + dt <= meta) {
          _t += dt;
        } else if (_t < meta) {
          _t = meta;
        }
      } else if (_reproduciendo) {
        _t = math.min(_t + dt * _velocidad, borde);
      }
    } else if (_reproduciendo) {
      _t += dt * _velocidad;
      if (_t >= g.duracion) {
        _t = g.duracion;
        _reproduciendo = false;
      }
    }
    final c = escena.poner(_t);
    if (c == null) return;
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
      // Izquierda: el medio interno y, en vivo, el dado de jev.
      if (c != null)
        Positioned(
          left: 12,
          top: _modoVivo ? 136 : 84,
          width: 236,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Panel(
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
          if (_modoVivo && _vivo?.decisionEn(_t) != null) ...[
            const SizedBox(height: 8),
            _PanelDado(_vivo!.decisionEn(_t)!),
          ],
          ]),
        ),
      // En vivo: qué correr.
      if (_modoVivo)
        Positioned(
          left: 12,
          right: 12,
          top: 76,
          child: SafeArea(child: _controlesVivo()),
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
            if (_modoVivo && (_vivo?.teatroPensando ?? false))
              const _Panel(
                child: Text('🎭 el teatro está escribiendo…',
                    style: TextStyle(color: Colors.white70)),
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
                    if (_modoVivo) _seguirBorde = false;
                  }),
                ),
                Expanded(
                  child: Slider(
                    value: _t.clamp(0, math.max(g.duracion, 0.01)),
                    max: math.max(g.duracion, 0.01),
                    onChanged: (v) => setState(() {
                      _t = v;
                      if (_modoVivo) _seguirBorde = false;
                    }),
                  ),
                ),
                if (_modoVivo)
                  TextButton(
                    onPressed: () => setState(() {
                      _seguirBorde = true;
                      _reproduciendo = true;
                    }),
                    child: Text(_seguirBorde ? '● vivo' : '⏩ al vivo',
                        style: TextStyle(
                            color: _seguirBorde ? Colors.redAccent : null)),
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

  Widget _controlesVivo() {
    final v = _vivo!;
    final corriendo = v.corriendo;
    return _Panel(
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: _cerebroVivo,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'teatro-m', child: Text('teatro-m')),
              DropdownMenuItem(value: 'relato-m', child: Text('relato-m')),
              DropdownMenuItem(value: 'jev-m', child: Text('jev-m')),
              DropdownMenuItem(value: 'reflejo', child: Text('reflejo')),
            ],
            onChanged: corriendo
                ? null
                : (x) => setState(() => _cerebroVivo = x ?? _cerebroVivo),
          ),
          DropdownButton<int>(
            value: _semillaVivo,
            underline: const SizedBox.shrink(),
            items: [
              for (var i = 1; i <= 15; i++)
                DropdownMenuItem(value: i, child: Text('semilla $i')),
            ],
            onChanged: corriendo
                ? null
                : (x) => setState(() => _semillaVivo = x ?? _semillaVivo),
          ),
          DropdownButton<double>(
            value: _segundosVivo,
            underline: const SizedBox.shrink(),
            items: [
              for (final s in {60.0, 120.0, 180.0, 300.0, _segundosVivo}.toList()
                ..sort())
                DropdownMenuItem(
                    value: s,
                    child: Text(s % 60 == 0
                        ? '${(s / 60).round()} min'
                        : '${s.round()} s')),
            ],
            onChanged: corriendo
                ? null
                : (x) => setState(() => _segundosVivo = x ?? _segundosVivo),
          ),
          FilledButton.icon(
            onPressed: corriendo || !v.conectado
                ? null
                : () => v.iniciar(_cerebroVivo, _semillaVivo, _segundosVivo),
            icon: const Icon(Icons.play_arrow),
            label: Text(corriendo ? 'corriendo…' : 'Iniciar'),
          ),
          if (!v.conectado)
            const Text('sin conexión', style: TextStyle(color: Colors.redAccent)),
          if (v.g == null && !corriendo)
            const Text('elige y pulsa Iniciar',
                style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
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

/// El dado de jev: la probabilidad de cada acción, cuál era la ganadora y
/// cuál salió del sorteo.
class _PanelDado extends StatelessWidget {
  const _PanelDado(this.d);
  final DecisionEnVivo d;

  @override
  Widget build(BuildContext context) {
    final orden = Accion.values.toList()
      ..sort((a, b) => (d.probabilidades[b.id] ?? 0)
          .compareTo(d.probabilidades[a.id] ?? 0));
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            d.probabilidades.isEmpty
                ? '🎲 decisión (sin dado)'
                : '🎲 el dado de jev · ${d.ms} ms',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 4),
        for (final a in orden)
          if ((d.probabilidades[a.id] ?? 0) >= 0.01 || a.id == d.accion)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    '${a.id == d.accion ? '▶ ' : ''}${a.id.replaceAll('_', ' ')}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: a.id == d.accion
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: a.id == d.accion ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: d.probabilidades[a.id] ?? 0,
                      minHeight: 7,
                      color: a.id == d.accion
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFF80CBC4),
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    ' ${((d.probabilidades[a.id] ?? 0) * 100).round()}%',
                    style: const TextStyle(fontSize: 10, color: Colors.white60),
                  ),
                ),
              ]),
            ),
        if (d.ganadora != null && d.ganadora != d.accion)
          Text('la ganadora era ${d.ganadora!.replaceAll('_', ' ')}; salió otra',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ]),
    );
  }
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
