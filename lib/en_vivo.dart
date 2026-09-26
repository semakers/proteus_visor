/// La conexión con `bin/en_vivo.dart`: va llenando una [Grabacion] con lo
/// que llega por el WebSocket mientras la simulación ocurre.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:proteus/visor.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Una decisión de jev tal como llegó: el dado y lo que salió.
class DecisionEnVivo {
  const DecisionEnVivo(this.t, this.accion, this.ganadora, this.confianza,
      this.probabilidades, this.ms, this.fallo);
  final double t;
  final String accion;
  final String? ganadora;
  final double? confianza;
  final Map<String, double> probabilidades;
  final int ms;
  final bool fallo;
}

class ConexionEnVivo extends ChangeNotifier {
  ConexionEnVivo(this.url);

  final Uri url;
  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _sub;

  bool conectado = false;
  bool corriendo = false;
  bool teatroPensando = false;
  String? error;
  Grabacion? g;
  DecisionEnVivo? ultimaDecision;

  /// Todas las decisiones de la corrida, en orden: el visor muestra la que
  /// corresponde al instante que se está viendo, no la última recibida.
  final List<DecisionEnVivo> decisiones = [];

  DecisionEnVivo? decisionEn(double t) {
    DecisionEnVivo? d;
    for (var i = decisiones.length - 1; i >= 0; i--) {
      if (decisiones[i].t <= t) {
        d = decisiones[i];
        break;
      }
    }
    return d;
  }
  Map<String, Object?>? resumenFinal;

  /// Se incrementa con cada corrida nueva, para que el visor rehaga la escena.
  int generacion = 0;

  /// La URL del WebSocket del servidor que sirvió la página, si lo hay.
  static Uri? urlDesde(Uri base) {
    if (base.scheme != 'http' && base.scheme != 'https') return null;
    return base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws', query: '');
  }

  Future<bool> conectar() async {
    try {
      final c = WebSocketChannel.connect(url);
      await c.ready.timeout(const Duration(seconds: 4));
      _canal = c;
      conectado = true;
      _sub = c.stream.listen(_recibir,
          onDone: () {
            conectado = false;
            notifyListeners();
          },
          onError: (Object e) {
            conectado = false;
            error = '$e';
            notifyListeners();
          });
      notifyListeners();
      return true;
    } catch (e) {
      conectado = false;
      return false;
    }
  }

  void iniciar(String cerebro, int semilla, double segundos) {
    _canal?.sink.add(jsonEncode({
      'tipo': 'iniciar',
      'cerebro': cerebro,
      'semilla': semilla,
      'segundos': segundos,
    }));
  }

  static double _d(Object? v) => (v as num).toDouble();

  void _recibir(dynamic dato) {
    final m = jsonDecode(dato as String) as Map<String, dynamic>;
    switch (m['tipo']) {
      case 'hola':
        corriendo = m['corriendo'] == true;
      case 'inicio':
        g = Grabacion.enVivo(
          cerebro: m['cerebro'] as String,
          semilla: m['semilla'] as int,
          dtCuadro: _d(m['dtCuadro']),
          anatomia:
              AnatomiaGrabada.fromJson(m['anatomia'] as Map<String, dynamic>),
          ondas: [
            for (final o in m['ondas'] as List)
              OndaTermica.fromJson(o as Map<String, dynamic>),
          ],
        );
        corriendo = true;
        resumenFinal = null;
        ultimaDecision = null;
        decisiones.clear();
        teatroPensando = false;
        generacion++;
      case 'roca':
        g?.rocas.add(RocaGrabada(_d(m['x']), _d(m['z']), _d(m['r'])));
      case 'alimento':
        g?.alimentos.add(AlimentoGrabado(m['id'] as int, _d(m['x']),
            _d(m['z']), _d(m['t']), null, false));
      case 'fin_alimento':
        for (final a in g?.alimentos ?? const <AlimentoGrabado>[]) {
          if (a.id == m['id']) {
            a
              ..muere = _d(m['t'])
              ..comido = m['comido'] == true;
          }
        }
      case 'cuadro':
        g?.cuadros.add(Cuadro.deLista((m['c'] as List).cast<num>()));
      case 'decision':
        final p = <String, double>{};
        (m['probabilidades'] as Map?)
            ?.forEach((k, v) => p['$k'] = (v as num).toDouble());
        ultimaDecision = DecisionEnVivo(
          _d(m['t']),
          m['accion'] as String,
          m['ganadora'] as String?,
          (m['confianza'] as num?)?.toDouble(),
          p,
          (m['ms'] as num?)?.toInt() ?? 0,
          m['fallo'] == true,
        );
        decisiones.add(ultimaDecision!);
      case 'teatro_pensando':
        teatroPensando = true;
      case 'narrativa':
        teatroPensando = false;
        g?.narrativas.add(NarrativaGrabada(_d(m['t']), m['texto'] as String));
      case 'fin':
        corriendo = false;
        teatroPensando = false;
        g?.causaDeMuerte = m['causa'] as String?;
        resumenFinal = (m['resumen'] as Map).cast<String, Object?>();
      case 'error':
        error = m['mensaje'] as String?;
        corriendo = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _canal?.sink.close();
    super.dispose();
  }
}
