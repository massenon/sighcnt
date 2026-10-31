import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_autonome.dart';
import 'qual_commun.dart';

/// `enquete-publique` — la page publique d'une fiche d'enquête (lien partagé). Elle est ISOLÉE, et c'est tout son intérêt : ni ruban, ni recherche, ni
/// session, ni fil d'Ariane, ni le moindre lien vers le logiciel. Une page d'enquête qui afficherait la coquille de l'application serait une porte — on la
/// tend à des inconnus.
///
/// Le formulaire naît du MÊME générateur que la saisie interne (`champsDeModele`) : un second
/// générateur aurait divergé à la première question ajoutée. SANS JETON VALIDE, elle ne montre rien — pas même le titre de l'enquête : « inconnu »,
/// « expiré » et « révoqué » reçoivent LA MÊME réponse (`qualPagePublique`). L'anonymat est porté par le lien : annoncé anonyme, on ne stocke ni nom ni
/// lien vers un dossier. Aucune donnée médicale.
///
/// LIMITE DE LA COQUE (E571) LEVÉE : la coque sert désormais les écrans `standalone` en plein écran (`EcranAutonome`, `ContexteAutonome`). Le registre
/// branche cette page par `EnquetePubliqueAutonome` (le jeton vient de l'adresse) ; `ouvrirPagePublique` reste le chemin du bouton « Ouvrir le lien » de
/// l'écran des enquêtes (une route plein écran au-dessus de la coque).
class EcranEnquetePublique extends StatefulWidget {
  const EcranEnquetePublique({super.key, required this.magasin, required this.code, this.horloge, this.chrome = false});

  /// Le magasin local : la collecte du prototype reste LOCALE au poste (la collecte réelle appartient à la version web).
  final Magasin magasin;

  /// Le code de l'adresse (`?jeton=…`) ; `null` ou inconnu = la réponse unique.
  final String? code;
  final DateTime Function()? horloge;

  /// `true` quand la coque enveloppe la page (branchement du registre) : un bouton de retour n'a alors pas de sens.
  final bool chrome;

  @override
  State<EcranEnquetePublique> createState() => _EtatPublique();
}

class _EtatPublique extends State<EcranEnquetePublique> {
  ControleurFormulaire? _ctl;
  bool _envoye = false;

  DateTime get _maintenant => (widget.horloge ?? DateTime.now)();
  String get _jour => iso(_maintenant);

  ({Fiche jeton, Fiche enquete})? get _page => qualPagePublique(
      jetons: colJetons(widget.magasin).toutes,
      enquetes: colEnquetes(widget.magasin).toutes,
      code: widget.code,
      aLaDate: _jour);

  @override
  void didUpdateWidget(EcranEnquetePublique ancien) {
    super.didUpdateWidget(ancien);
    // Une autre adresse est un autre formulaire : on ne garde ni les saisies ni le « Merci » de la précédente.
    if (ancien.code != widget.code) {
      _ctl?.dispose();
      _ctl = null;
      _envoye = false;
    }
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  Widget _entete() => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: _carte(),
      child: Column(children: [
        Image.asset('assets/img/logo.jpeg',
            width: 56, height: 56, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(width: 56, height: 56)),
        const SizedBox(height: 8),
        Text(IdentiteClinique.nomCourt,
            style: const TextStyle(color: JetonsShell.navy950, fontSize: 18, fontWeight: FontWeight.w700)),
        Text(IdentiteClinique.slogan,
            style: const TextStyle(color: JetonsShell.navy700, fontSize: 12, fontStyle: FontStyle.italic)),
      ]));

  BoxDecoration _carte() => BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: JetonsShell.ombreCarte);

  @override
  Widget build(BuildContext context) {
    final p = _page;
    final Widget contenu;
    if (_envoye) {
      contenu = Container(
          key: const Key('qual:merci'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          decoration: _carte(),
          child: Column(children: const [
            Text('Merci !',
                style: TextStyle(color: JetonsShell.success700, fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Votre réponse a bien été enregistrée.',
                style: TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14)),
            SizedBox(height: 16),
            Text(IdentiteClinique.slogan,
                style: TextStyle(color: JetonsShell.navy700, fontSize: 12, fontStyle: FontStyle.italic)),
          ]));
    } else if (p == null) {
      // UNE seule réponse pour « inconnu », « expiré » et « révoqué » : les distinguer renseignerait sur ce qui existe.
      contenu = Container(
          key: const Key('qual:lien-invalide'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: _carte(),
          child: Column(children: [
            const Text('Ce lien n’est plus valable.',
                style: TextStyle(color: JetonsShell.slate800, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
                'Le questionnaire est clos ou l’adresse est incomplète. Vous pouvez vous adresser à l’accueil de la clinique.',
                textAlign: TextAlign.center,
                style: TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14)),
            const SizedBox(height: 16),
            Text('Tél. ${IdentiteClinique.telephones.join(' / ')}',
                style: const TextStyle(color: JetonsShell.slate400, fontSize: 12)),
          ]));
    } else {
      contenu = _questionnaire(p.jeton, p.enquete);
    }
    final page = ColoredBox(
        color: JetonsShell.slate100,
        child: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 672),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _entete(),
                          const SizedBox(height: 16),
                          contenu,
                          const SizedBox(height: 16),
                          Text('${IdentiteClinique.nom} — ${IdentiteClinique.bp}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: JetonsShell.slate400, fontSize: 12)),
                        ]))))));
    return widget.chrome ? page : Scaffold(backgroundColor: JetonsShell.slate100, body: page);
  }

  Widget _questionnaire(Fiche jeton, Fiche enq) {
    final anonyme = jeton['anonyme'] == true;
    _ctl ??= ControleurFormulaire([
      if (!anonyme) const ChampDef(nom: '_repondant', libelle: 'Votre nom', requis: true, col: ColChamp.plein),
      ...champsDeModele(enq['questions'], pleineLargeur: true),
    ]);
    return Container(
        key: const Key('qual:questionnaire'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: _carte(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${enq['titre']}',
              style: const TextStyle(color: JetonsShell.slate900, fontSize: 20, fontWeight: FontWeight.w700)),
          if ('${enq['description'] ?? ''}'.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('${enq['description']}',
                    style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14))),
          const SizedBox(height: 16),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: anonyme ? JetonsShell.success50 : JetonsShell.warning50,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(qualMentionAnonymat(anonyme),
                  style: TextStyle(
                      color: anonyme ? JetonsShell.success800 : JetonsShell.warning800, fontSize: 12, height: 16 / 12))),
          const SizedBox(height: 16),
          FormulaireSigh(controleur: _ctl!),
          const SizedBox(height: 16),
          BoutonSigh(
              libelle: 'Envoyer ma réponse', taille: TailleBouton.lg, onPressed: () => _envoyer(jeton, enq, anonyme)),
        ]));
  }

  void _envoyer(Fiche jeton, Fiche enq, bool anonyme) {
    final v = _ctl!.valider();
    if (v == null) {
      ToastsSigh.afficher(context, 'Merci de compléter les réponses attendues.', type: TypeToast.erreur);
      return;
    }
    final nom = v.remove('_repondant');
    // ANONYME VEUT DIRE ANONYME : ni nom, ni adresse réseau, ni lien vers un dossier. Sinon le mot est un mensonge.
    colReponses(widget.magasin).inserer(
        qualReponse(enq, v,
            aujourdhui: _maintenant,
            canal: qualCanalPublic,
            jetonId: jeton['id'],
            saisiPar: qualSaisiPar(anonyme: anonyme, nom: nom == null ? null : '$nom')),
        prefixe: 'REP');
    setState(() => _envoye = true);
  }
}

/// Ouvre la page publique DANS UNE ROUTE PLEIN ÉCRAN au-dessus de la coque : aucun ruban, aucune barre, aucune session. Le seul chemin de retour est le
/// geste système (retour arrière) ; la page ne porte aucun lien vers le logiciel.
Future<void> ouvrirPagePublique(BuildContext contexte, Magasin magasin, String code, {DateTime Function()? horloge}) =>
    Navigator.of(contexte, rootNavigator: true).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => EcranEnquetePublique(magasin: magasin, code: code, horloge: horloge)));

/// Le branchement du registre de la coque : la coque sert cet écran EN PLEIN ÉCRAN, sans barre, sans ruban, sans page standard (`EcranAutonome`), et
/// ne lui donne NI session, NI manifeste, NI navigation (`ContexteAutonome.publique`) — seulement le magasin local, l'horloge et le paramètre `jeton`
/// de l'adresse. Sans jeton : la réponse unique.
class EnquetePubliqueAutonome extends StatelessWidget with EcranAutonome {
  const EnquetePubliqueAutonome({super.key});

  @override
  Widget build(BuildContext context) {
    final x = ContexteAutonome.of(context);
    return EcranEnquetePublique(magasin: x.magasin, code: x.parametres['jeton'], horloge: x.horloge);
  }
}
