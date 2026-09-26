/// La escena 3D de una grabación: se arma una vez y se actualiza a cada
/// instante `t` de la reproducción.
///
/// La luz es la del camino de GPU débil de Nairda (difuso constante + una
/// direccional, sin antialias): un solo camino para todos los aparatos.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:proteus/visor.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Lado del parche de suelo coloreado y su resolución.
const double _ladoSuelo = 110;
const int _celdas = 88;

/// Cuánto puede alejarse la ameba del centro del parche antes de rehacerlo.
const double _margenSuelo = 18;

/// Densidad de rasterizado aprobada en Nairda mirando el Redmi 7.
const double _densidadObjetivo = 1.3;

final class EscenaProteus {
  EscenaProteus(this.g) {
    _luz();
    _ameba();
    _rehacerSuelo(0, 0);
    _sincronizar();
  }

  final Grabacion g;
  final Scene scene = Scene();

  final Node _suelo = Node(name: 'suelo');
  double _sueloX = double.nan, _sueloZ = double.nan;
  bool _sueloEnEscena = false;

  final Map<int, Node> _nodosAlimento = {};
  late final Node _membrana, _nucleo, _pIzq, _pDer;
  late final PhysicallyBasedMaterial _matMembrana;

  /// Dónde está la ameba ahora (para la cámara).
  vm.Vector3 posicion = vm.Vector3(0, 0.75, 0);

  /// Rumbo de la ameba (radianes; 0 = +Z).
  double rumbo = 0;

  // --- construcción -----------------------------------------------------

  void _luz() {
    final dpr =
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
    scene.renderScale = (_densidadObjetivo / dpr).clamp(0.0, 1.0);
    // constantDiffuse: sin él la escena sale NEGRA (el difuso es
    // environment × albedo).
    scene.environment =
        EnvironmentMap.constantDiffuse(vm.Vector3(0.55, 0.58, 0.62));
    scene.exposure = 1.0;
    scene.antiAliasingMode = AntiAliasingMode.none;
    // OJO: `direction` apunta HACIA la luz en esta versión (medido en Nairda).
    scene.add(Node(name: 'sol')
      ..addComponent(DirectionalLightComponent(DirectionalLight(
        direction: vm.Vector3(0.35, 1.0, 0.45),
        color: vm.Vector3(0.80, 0.80, 0.76),
        intensity: 3.0,
      ))));
  }

  static PhysicallyBasedMaterial _mate(double r, double gr, double b,
          {double a = 1, double rugosidad = 0.8}) =>
      PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(r, gr, b, a)
        ..metallicFactor = 0
        ..roughnessFactor = rugosidad
        ..alphaMode = a < 1 ? AlphaMode.blend : AlphaMode.opaque;

  // En vivo, las rocas y el alimento van llegando: se crean los nodos de lo
  // que la escena aún no tiene.
  int _rocasPuestas = 0;
  final _matRoca = _mate(0.42, 0.39, 0.36, rugosidad: 0.95);
  final _geoAlimento = SphereGeometry(radius: 0.32, segments: 12, rings: 8);
  final _matAlimento = _mate(0.55, 0.85, 0.25, rugosidad: 0.5);

  void _sincronizar() {
    for (; _rocasPuestas < g.rocas.length; _rocasPuestas++) {
      final r = g.rocas[_rocasPuestas];
      // La física usa un cilindro de semialtura 1 centrado en y = 1.
      scene.add(Node(name: 'roca')
        ..localTransform = vm.Matrix4.translation(vm.Vector3(r.x, 1, r.z))
        ..mesh = Mesh(
            CylinderGeometry(
                bottomRadius: r.radio, topRadius: r.radio * 0.82, height: 2),
            _matRoca));
    }
    for (final a in g.alimentos) {
      if (_nodosAlimento.containsKey(a.id)) continue;
      final n = Node(name: 'alimento-${a.id}')
        ..localTransform = vm.Matrix4.translation(vm.Vector3(a.x, 0.32, a.z))
        ..mesh = Mesh(_geoAlimento, _matAlimento)
        ..visible = false;
      _nodosAlimento[a.id] = n;
      scene.add(n);
    }
  }

  void _ameba() {
    final an = g.anatomia;
    // La membrana: una gota achatada que envuelve el núcleo físico
    // (semiejes 0.9 × 0.3 × 1.2), translúcida como una Proteus.
    _matMembrana = _mate(0.78, 0.80, 0.90, a: 0.72, rugosidad: 0.35);
    _membrana = Node(name: 'membrana')
      ..mesh = Mesh(SphereGeometry(radius: 1, segments: 28, rings: 16),
          _matMembrana);
    scene.add(_membrana);
    // El núcleo celular: una esfera oscura dentro, algo adelantada.
    _nucleo = Node(name: 'nucleo')
      ..mesh = Mesh(SphereGeometry(radius: 0.33, segments: 16, rings: 10),
          _mate(0.30, 0.25, 0.45, rugosidad: 0.6));
    scene.add(_nucleo);

    Node pseudopodo(String nombre) {
      final n = Node(name: nombre)
        ..mesh = Mesh(
            CylinderGeometry(
                bottomRadius: an.radioPseudopodo,
                topRadius: an.radioPseudopodo,
                height: an.semiGrosorPseudopodo * 2),
            _mate(0.70, 0.74, 0.86, rugosidad: 0.5));
      // Tres bultos en el borde: sin ellos no se ve que el pseudópodo gira.
      for (var k = 0; k < 3; k++) {
        final ang = k * 2 * math.pi / 3;
        n.add(Node(name: '$nombre-bulto$k')
          ..localTransform = vm.Matrix4.translation(vm.Vector3(
              math.cos(ang) * an.radioPseudopodo, 0,
              math.sin(ang) * an.radioPseudopodo))
          ..mesh = Mesh(SphereGeometry(radius: 0.13, segments: 10, rings: 6),
              _mate(0.45, 0.40, 0.65)));
      }
      scene.add(n);
      return n;
    }

    _pIzq = pseudopodo('pseudopodo-izq');
    _pDer = pseudopodo('pseudopodo-der');
  }

  // --- el suelo pintado por temperatura ----------------------------------

  /// Frío azul → templado verde agua → caliente naranja rojizo.
  static (double, double, double) colorDeTemperatura(double t) {
    const frio = (0.16, 0.34, 0.80);
    const comodo = (0.36, 0.74, 0.64);
    const calor = (0.95, 0.42, 0.16);
    (double, double, double) mezcla(
            (double, double, double) a, (double, double, double) b, double u) =>
        (a.$1 + (b.$1 - a.$1) * u, a.$2 + (b.$2 - a.$2) * u,
            a.$3 + (b.$3 - a.$3) * u);
    return t < 0.5
        ? mezcla(frio, comodo, (t / 0.5).clamp(0.0, 1.0))
        : mezcla(comodo, calor, ((t - 0.5) / 0.5).clamp(0.0, 1.0));
  }

  void _rehacerSuelo(double cx, double cz) {
    _sueloX = cx;
    _sueloZ = cz;
    const n = _celdas + 1;
    final pos = Float32List(n * n * 3);
    final nor = Float32List(n * n * 3);
    final col = Float32List(n * n * 4);
    final paso = _ladoSuelo / _celdas;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final k = i * n + j;
        final x = cx - _ladoSuelo / 2 + j * paso;
        final z = cz - _ladoSuelo / 2 + i * paso;
        pos[k * 3] = x;
        pos[k * 3 + 1] = 0;
        pos[k * 3 + 2] = z;
        nor[k * 3 + 1] = 1;
        final (r, gr, b) = colorDeTemperatura(g.temperatura(x, z));
        col[k * 4] = r;
        col[k * 4 + 1] = gr;
        col[k * 4 + 2] = b;
        col[k * 4 + 3] = 1;
      }
    }
    final idx = <int>[];
    for (var i = 0; i < _celdas; i++) {
      for (var j = 0; j < _celdas; j++) {
        final a = i * n + j, b = a + 1, c = a + n, d = c + 1;
        // Antihorario visto desde arriba (+Y): la cara mira hacia arriba.
        idx.addAll([a, c, b, b, c, d]);
      }
    }
    final mat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 1
      ..doubleSided = true;
    _suelo.mesh = Mesh(
        MeshGeometry.fromArrays(
            positions: pos, normals: nor, colors: col, indices: idx),
        mat);
    if (!_sueloEnEscena) {
      scene.add(_suelo);
      _sueloEnEscena = true;
    }
  }

  // --- a cada instante ---------------------------------------------------

  /// Pone la escena en el instante [t] (interpolando entre cuadros).
  Cuadro? poner(double t) {
    _sincronizar();
    if (g.cuadros.isEmpty) return null;
    final i = g.indiceEn(t);
    final a = g.cuadros[i];
    final b = i + 1 < g.cuadros.length ? g.cuadros[i + 1] : a;
    final u = b.t > a.t ? ((t - a.t) / (b.t - a.t)).clamp(0.0, 1.0) : 0.0;

    final (pn, qn) = _interp(a.nucleo, b.nucleo, u);
    posicion = pn;
    final frente = _rot(qn, vm.Vector3(0, 0, 1));
    rumbo = math.atan2(frente.x, frente.z);

    final an = g.anatomia;
    // La gota: algo mayor que la caja física, con un leve pulso de vida.
    final pulso = 1 + 0.03 * math.sin(t * 2.4);
    _membrana.localTransform = vm.Matrix4.compose(
        pn,
        qn,
        vm.Vector3(an.nucleo[0] * 1.35 * pulso, an.nucleo[1] * 1.9,
            an.nucleo[2] * 1.3 / pulso));
    _nucleo.localTransform = vm.Matrix4.compose(
        pn + _rot(qn, vm.Vector3(0, 0.05, 0.35)), qn, vm.Vector3.all(1));

    // El cilindro de scene va en Y; la física lo giró −90° sobre Z. La pose
    // grabada ya trae esa rotación.
    final (pi, qi) = _interp(a.pseudoIzq, b.pseudoIzq, u);
    final (pd, qd) = _interp(a.pseudoDer, b.pseudoDer, u);
    _pIzq.localTransform = vm.Matrix4.compose(pi, qi, vm.Vector3.all(1));
    _pDer.localTransform = vm.Matrix4.compose(pd, qd, vm.Vector3.all(1));

    // Color de la membrana según la homeostasis: sana = lila pálido,
    // en apuros = rojiza.
    final h = a.homeostasis + (b.homeostasis - a.homeostasis) * u;
    final s = (1 - h).clamp(0.0, 1.0);
    _matMembrana.baseColorFactor = vm.Vector4(
        0.78 + 0.17 * s, 0.80 - 0.45 * s, 0.90 - 0.50 * s, 0.72);

    for (final al in g.alimentos) {
      final n = _nodosAlimento[al.id]!;
      final vivo = al.vivoEn(t);
      n.visible = vivo;
      if (vivo) {
        // Flota un poco: el alimento también está vivo.
        final fase = al.id * 1.7;
        n.localTransform = vm.Matrix4.translation(vm.Vector3(
            al.x, 0.32 + 0.08 * math.sin(t * 1.8 + fase), al.z));
      }
    }

    if ((pn.x - _sueloX).abs() > _margenSuelo ||
        (pn.z - _sueloZ).abs() > _margenSuelo) {
      _rehacerSuelo(pn.x, pn.z);
    }
    return u < 0.5 ? a : b;
  }

  /// Rotación ACTIVA. `Quaternion.rotated` de vector_math hace la INVERSA
  /// (trampa medida en Nairda: «pasa» justo cuando el código está mal).
  static vm.Vector3 _rot(vm.Quaternion q, vm.Vector3 v) =>
      q.asRotationMatrix().transform(v.clone());

  static (vm.Vector3, vm.Quaternion) _interp(Pose a, Pose b, double u) {
    final p = vm.Vector3(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u,
        a.z + (b.z - a.z) * u);
    final qa = vm.Quaternion(a.qx, a.qy, a.qz, a.qw);
    var qb = vm.Quaternion(b.qx, b.qy, b.qz, b.qw);
    // El camino corto.
    if (qa.x * qb.x + qa.y * qb.y + qa.z * qb.z + qa.w * qb.w < 0) {
      qb = vm.Quaternion(-qb.x, -qb.y, -qb.z, -qb.w);
    }
    final q = vm.Quaternion(
      qa.x + (qb.x - qa.x) * u,
      qa.y + (qb.y - qa.y) * u,
      qa.z + (qb.z - qa.z) * u,
      qa.w + (qb.w - qa.w) * u,
    )..normalize();
    return (p, q);
  }
}
