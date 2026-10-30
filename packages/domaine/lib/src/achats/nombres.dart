/// 3.0 s'écrit « 3 » comme en JavaScript : un nombre entier reste entier au magasin (et à l'écran).
library;

import '../format/js.dart';

num entierSiPossible(num v) => v == v.truncateToDouble() ? v.toInt() : v;

/// `Number(v) || 0`, rendu entier quand il l'est.
num nombreEntier(Object? v) => entierSiPossible(nombreOuZero(v));
