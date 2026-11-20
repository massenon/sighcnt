/// SHA-256 (FIPS 180-4) d'OCTETS, en Dart pur, sans paquet : l'empreinte d'un fichier numérisé (lot D5). Un exemplaire, au domaine : le poste, la mère et le mobile
/// ne recalculent jamais l'empreinte chacun à sa façon. Le flux ([Sha256Flux]) hache un fichier par morceaux sans le tenir en mémoire.
library;

import 'dart:typed_data';

const List<int> _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

/// Le calcul incrémental : `ajouter` autant de fois que voulu, puis `hex` (une seule fois).
class Sha256Flux {
  final Uint32List _h = Uint32List.fromList([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  final Uint32List _w = Uint32List(64);
  final Uint8List _tampon = Uint8List(64);
  int _dansTampon = 0;
  int _total = 0;
  bool _clos = false;

  void ajouter(List<int> octets) {
    if (_clos) throw StateError('Sha256Flux : déjà clos');
    var i = 0;
    final n = octets.length;
    _total += n;
    if (_dansTampon > 0) {
      while (i < n && _dansTampon < 64) {
        _tampon[_dansTampon++] = octets[i++];
      }
      if (_dansTampon == 64) {
        _bloc(_tampon, 0);
        _dansTampon = 0;
      }
    }
    final u8 = octets is Uint8List ? octets : null;
    while (i + 64 <= n) {
      if (u8 != null) {
        _bloc(u8, i);
      } else {
        for (var j = 0; j < 64; j++) {
          _tampon[j] = octets[i + j];
        }
        _bloc(_tampon, 0);
      }
      i += 64;
    }
    while (i < n) {
      _tampon[_dansTampon++] = octets[i++];
    }
  }

  void _bloc(Uint8List b, int off) {
    final w = _w;
    for (var t = 0; t < 16; t++) {
      final p = off + t * 4;
      w[t] = (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
    }
    for (var t = 16; t < 64; t++) {
      final a15 = w[t - 15], a2 = w[t - 2];
      final s0 = _rotr(a15, 7) ^ _rotr(a15, 18) ^ (a15 >> 3);
      final s1 = _rotr(a2, 17) ^ _rotr(a2, 19) ^ (a2 >> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
    }
    var a = _h[0], bb = _h[1], c = _h[2], d = _h[3], e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var t = 0; t < 64; t++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final t1 = (h + s1 + ch + _k[t] + w[t]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final mj = (a & bb) ^ (a & c) ^ (bb & c);
      final t2 = (s0 + mj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = bb;
      bb = a;
      a = (t1 + t2) & 0xffffffff;
    }
    _h[0] = (_h[0] + a) & 0xffffffff;
    _h[1] = (_h[1] + bb) & 0xffffffff;
    _h[2] = (_h[2] + c) & 0xffffffff;
    _h[3] = (_h[3] + d) & 0xffffffff;
    _h[4] = (_h[4] + e) & 0xffffffff;
    _h[5] = (_h[5] + f) & 0xffffffff;
    _h[6] = (_h[6] + g) & 0xffffffff;
    _h[7] = (_h[7] + h) & 0xffffffff;
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  /// L'empreinte en hexadécimal (64 caractères minuscules). Clôt le flux.
  String hex() {
    if (!_clos) {
      _clos = true;
      final bits = _total * 8;
      _tampon[_dansTampon++] = 0x80;
      if (_dansTampon > 56) {
        while (_dansTampon < 64) {
          _tampon[_dansTampon++] = 0;
        }
        _bloc(_tampon, 0);
        _dansTampon = 0;
      }
      while (_dansTampon < 56) {
        _tampon[_dansTampon++] = 0;
      }
      for (var i = 0; i < 8; i++) {
        _tampon[56 + i] = (bits >> (8 * (7 - i))) & 0xff;
      }
      _bloc(_tampon, 0);
    }
    final sb = StringBuffer();
    for (final v in _h) {
      sb.write(v.toRadixString(16).padLeft(8, '0'));
    }
    return sb.toString();
  }
}

/// L'empreinte SHA-256 hexadécimale des octets.
String sha256Octets(List<int> octets) {
  final f = Sha256Flux()..ajouter(octets);
  return f.hex();
}

/// Une empreinte est 64 caractères hexadécimaux minuscules (`^[0-9a-f]{64}$`) : rien d'autre ne sert de nom de fichier.
bool empreinteValide(String s) => RegExp(r'^[0-9a-f]{64}$').hasMatch(s);
