import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show CoffrePin, mobLibelleProfil, mobProfilDe;

import 'core/coffre_pin_securise.dart';
import 'core/theme.dart';
import 'moteur/moteur_mobile.dart';
import 'ui/accueil.dart';
import 'ui/appairage.dart';
import 'ui/pin.dart';

const String adresseRelais = String.fromEnvironment('SIGH_RELAIS', defaultValue: 'https://relais.exemple.bj');
const String cheminBase = String.fromEnvironment('SIGH_DB', defaultValue: 'sigh-mobile.db');

/// Sur un téléphone, le code PIN est OBLIGATOIRE (spec §11) : le coffre est celui du système (`flutter_secure_storage`), jamais éprouvé ici faute de
/// chaîne native (ECARTS-MAQUETTE E1658). Le coffre est SONDÉ au démarrage ; s'il ne répond pas, l'application ne s'ouvre pas et dit pourquoi (E1820) :
/// pas de repli qui rangerait le haché du code ailleurs, pas de contournement du verrou.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(Demarrage(
    stockage: StockageFlutterSecure(),
    creerMoteur: () => MoteurMobileSync.creer(dbChemin: cheminBase, relais: adresseRelais),
  ));
}

/// Le démarrage à froid : sonde le stockage sécurisé, puis ouvre l'application AVEC son coffre. Le moteur (la base locale) n'est créé qu'une fois le
/// coffre jugé sain : un téléphone sans coffre n'ouvre rien.
class Demarrage extends StatefulWidget {
  const Demarrage({super.key, required this.stockage, required this.creerMoteur, this.horlogeVerrou, this.iterationsPin = 120000});
  final int iterationsPin;
  final StockageSecret stockage;
  final MoteurMobile Function() creerMoteur;
  final DateTime Function()? horlogeVerrou;

  @override
  State<Demarrage> createState() => _DemarrageState();
}

class _DemarrageState extends State<Demarrage> {
  MoteurMobile? _moteur;
  String? _cause;

  @override
  void initState() {
    super.initState();
    _sonder();
  }

  Future<void> _sonder() async {
    final cause = await sonderStockage(widget.stockage);
    if (!mounted) return;
    setState(() {
      _cause = cause;
      if (cause == null) _moteur ??= widget.creerMoteur();
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _moteur;
    if (m != null) return SighMobile(moteur: m, coffre: CoffrePinSecurise(widget.stockage, iterations: widget.iterationsPin), horlogeVerrou: widget.horlogeVerrou);
    return MaterialApp(
      title: 'SIGH-CNT',
      debugShowCheckedModeBanner: false,
      theme: ThemeSigh.clair(),
      home: _cause == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : EcranStockageIndisponible(
              cause: _cause!,
              reessayer: () {
                setState(() => _cause = null);
                _sonder();
              }),
    );
  }
}

/// Le repli NOMMÉ quand le coffre du système est indisponible : aucun écran métier, aucune saisie, la cause et le geste (E1820, texte proposé).
class EcranStockageIndisponible extends StatelessWidget {
  const EcranStockageIndisponible({super.key, required this.cause, required this.reessayer});
  final String cause;
  final VoidCallback reessayer;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('SIGH-CNT')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 40, color: ThemeSigh.danger),
              const SizedBox(height: 12),
              const Text('Stockage sécurisé indisponible', key: Key('stockage-titre'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 8),
              const Text('Le code PIN et les données de santé ne peuvent pas être protégés sur ce téléphone : l’application reste fermée plutôt que de les exposer. Vérifiez que le téléphone a un verrouillage d’écran, puis réessayez ou contactez la clinique.', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(cause, key: const Key('stockage-cause'), textAlign: TextAlign.center, style: TextStyle(color: ThemeSigh.danger)),
              const SizedBox(height: 16),
              FilledButton(key: const Key('stockage-reessayer'), onPressed: reessayer, child: const Text('Réessayer')),
            ]),
          ),
        ),
      );
}

class SighMobile extends StatefulWidget {
  /// [coffre] absent : aucun verrou. C'est le cas des tests d'écran, jamais celui de l'application (`main` le fournit toujours).
  const SighMobile({super.key, required this.moteur, this.coffre, this.horlogeVerrou});
  final MoteurMobile moteur;
  final CoffrePin? coffre;

  /// L'horloge du verrou (le blocage de 30 s se compte avec elle) ; absente, l'heure du téléphone. Les tests la déplacent.
  final DateTime Function()? horlogeVerrou;

  @override
  State<SighMobile> createState() => _SighMobileState();
}

class _SighMobileState extends State<SighMobile> {
  /// L'identification affichée sur le verrou : l'agent et le profil (avec la fonction du soignant) que la mère a fixés ; rien n'est saisi.
  Widget? _identite() {
    final m = widget.moteur;
    if (m.profil == null) return null;
    final agent = m.soignant?.session.agent ?? (m is ExtensionsMobile ? (m as ExtensionsMobile).agent : '');
    final profil = mobProfilDe(reception: m.profil != ProfilMobile.soignant, fonction: m.soignant?.session.fonction ?? '');
    return EnteteIdentite(agent: agent, profil: mobLibelleProfil(profil));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIGH-CNT',
      debugShowCheckedModeBanner: false,
      theme: ThemeSigh.clair(),
      // Le verrou suit l'état du moteur : il ne couvre qu'un téléphone appairé, et l'écran de verrou nomme l'agent et son profil, lus du code (E1820, E1821).
      builder: (context, child) => ValueListenableBuilder<EtatMobile>(
        valueListenable: widget.moteur.etat,
        builder: (c, _, __) => GardeVerrou(
          coffre: widget.coffre,
          horloge: widget.horlogeVerrou,
          appaire: widget.moteur.profil != null,
          identite: _identite,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      // Le profil vient de la mère (code d'appairage, E1600) : l'écran suit l'état du moteur, il ne devine pas.
      home: ValueListenableBuilder<EtatMobile>(
        valueListenable: widget.moteur.etat,
        builder: (c, _, __) => widget.moteur.profil == null ? EcranAppairage(moteur: widget.moteur, apres: () => setState(() {})) : Accueil(moteur: widget.moteur, coffreActif: widget.coffre != null, apresReinitialisation: () => setState(() {})),
      ),
    );
  }
}
