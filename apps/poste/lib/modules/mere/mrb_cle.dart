import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/qual_qr.dart';
import 'mra_affectation.dart';
import 'mrb_commun.dart';
import 'mrb_source.dart';

/// `mere-cle-clinique` : la clé qui chiffre tout ce qui quitte le serveur (M-10).
///
/// LA CLÉ NE S'AFFICHE JAMAIS EN CLAIR. L'écran montre son empreinte (8 premiers caractères du SHA-256) quand le service la publie, et rien d'autre. Le seul
/// endroit où la clé quitte le serveur est le QR d'appairage d'un mobile : un QR, jamais des caractères lisibles, jamais un journal, jamais un toast.
/// Ce que le service expose : uniquement `POST /admin/code-mobile` (le code et la clé du QR). L'empreinte, la date de création, l'impression de la copie
/// papier et la rotation ne sont pas exposées : « non disponible » (écarts E1345 à E1349). L'attestation de la copie papier (détenteur, scellé, contrôle)
/// est un acte administratif que la console enregistre au journal du poste (RG-12), collection `attestationsCle`.
const String mrbCollectionAttestations = 'attestationsCle';

class _Cle {
  const _Cle(this.empreinte, this.creeLe);
  final String? empreinte;
  final DateTime? creeLe;
}

class EcranCleClinique extends StatefulWidget with EcranMaquette {
  const EcranCleClinique({super.key});
  @override
  String get titre => 'Clé de clinique';
  @override
  String get description =>
      'La clé qui chiffre tout ce qui quitte le serveur : empreinte de contrôle, copie papier sous scellé, QR d’appairage mobile, rotation.';
  @override
  String get regle =>
      'La clé de clinique n’est jamais envoyée au relais et n’apparaît jamais à l’écran : seule son empreinte sert au contrôle. '
      'Perdue, elle rend irrécupérables les sauvegardes et le relais (spec §12).';

  @override
  State<EcranCleClinique> createState() => _EtatCle();
}

class _EtatCle extends MrbEtatEcran<EcranCleClinique, _Cle> {
  final TextEditingController _detenteur = TextEditingController();
  final TextEditingController _scelle = TextEditingController();
  final TextEditingController _controle = TextEditingController();

  @override
  void dispose() {
    _detenteur.dispose();
    _scelle.dispose();
    _controle.dispose();
    super.dispose();
  }

  @override
  Future<_Cle> charger(MrbSource s) async => _Cle(mrbEmpreinteCourte(await s.empreinteCle()), await s.cleCreeeLe());

  CollectionMagasin _attestations(ContexteEcran c) => c.magasin.collection(mrbCollectionAttestations);

  void _attester(BuildContext contexte, ContexteEcran c) {
    final manquants = mrbChampsAttestationManquants(detenteur: _detenteur.text, scelle: _scelle.text, controlePar: _controle.text);
    if (manquants.isNotEmpty) {
      ToastsSigh.afficher(contexte, 'Attestation refusée : champ(s) obligatoire(s) manquant(s) : ${manquants.join(', ')}.', type: TypeToast.erreur);
      return;
    }
    _attestations(c).inserer({
      'date': iso(c.aujourdhui),
      'detenteur': _detenteur.text.trim(),
      'scelle': _scelle.text.trim(),
      'controlePar': _controle.text.trim(),
      'saisiPar': acteurNom(c),
    }, prefixe: 'ATC');
    setState(() {
      _detenteur.clear();
      _scelle.clear();
      _controle.clear();
    });
    ToastsSigh.afficher(contexte, 'Attestation de la copie papier enregistrée.', type: TypeToast.succes);
  }

  Future<void> _imprimer(BuildContext contexte) async {
    final s = source;
    if (s != null) await geste(contexte, s.imprimerCopiePapier, ok: 'Copie papier envoyée à l’impression.');
  }

  Future<void> _tourner(BuildContext contexte) async {
    final s = source;
    if (s == null) return;
    final ok = await confirmerSigh(contexte,
        titre: 'Faire tourner la clé de clinique ?',
        message: 'La rotation change la clé qui chiffre le relais, les sauvegardes et les mobiles. Les anciennes sauvegardes ne se déchiffrent qu’avec l’ancienne clé : '
            'conservez sa copie papier. Cette opération est réservée à l’administrateur.',
        libelleOk: 'Faire tourner la clé',
        dangereux: true);
    if (ok && contexte.mounted) await geste(contexte, s.tournerCle, ok: 'Clé de clinique renouvelée.');
  }

  Future<void> _qr(BuildContext contexte) async {
    final s = source;
    if (s == null) return;
    // E1600 : le profil et la fonction du téléphone sont affectés ICI, par le code ; le téléphone ne les déclare plus.
    final a = await demanderAffectationMobile(contexte, libelleOk: 'Générer le QR');
    if (a == null || a.etiquette.isEmpty || !contexte.mounted) return;
    final etiquette = a.etiquette;
    final MrbCodeMobile r;
    try {
      r = await s.codeMobile(etiquette, profil: a.profil, fonction: a.fonction);
    } catch (e) {
      if (contexte.mounted) ToastsSigh.afficher(contexte, 'QR refusé : ${mrbCause(e)}', type: TypeToast.erreur);
      return;
    }
    if (!contexte.mounted) return;
    await afficherModale<void>(contexte,
        titre: 'QR d’appairage mobile',
        taille: TailleModale.sm,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          QrSigh(r.payloadQr, taille: 240, libelle: 'QR d’appairage du mobile'),
          const SizedBox(height: 12),
          const Text('Code d’appairage', style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
          SelectableText(r.code,
              key: const Key('mrb:code-mobile'),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 4)),
          const SizedBox(height: 8),
          const Text('Code à usage unique, valable 15 minutes. Le QR contient aussi la clé de clinique : à scanner sur le téléphone, jamais à photographier ni à transmettre.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
        ]),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', onPressed: fermer)]);
  }

  Widget _champ(String libelle, TextEditingController ctl, Key cle) => SizedBox(
        width: 240,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(libelle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
          const SizedBox(height: 4),
          TextField(key: cle, controller: ctl, style: styleSaisie, decoration: decorationChamp(indicatif: libelle)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = _attestations(c);
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final att = col.actives;
          final derniere = att.isEmpty ? null : att.first;
          final cle = donnees;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (derniere == null)
              const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: NoteSigh(
                      'Détenteur de la copie papier non désigné. Tant qu’il ne l’est pas, la perte du serveur et de son disque serait définitive pour tout ce qui a été sauvegardé.',
                      ton: TonSigh.attention,
                      icone: LucideIcons.triangleAlert)),
            mrbGrilleKpi([
              mrbKpi('Empreinte (SHA-256, 8 premiers)', cle?.empreinte,
                  indice: cle?.empreinte == null ? 'Le service de la mère ne publie pas l’empreinte de sa clé.' : null, icone: LucideIcons.fingerprint),
              mrbKpi('Créée le', cle?.creeLe == null ? null : mrbDateHeure(cle!.creeLe!),
                  indice: cle?.creeLe == null ? 'Date de création non publiée par le service.' : null, icone: LucideIcons.calendar),
              mrbKpi('Copie papier', derniere == null ? 'Non attestée' : 'Attestée le ${mrbDateJourIso('${derniere['date']}')}',
                  indice: derniere == null ? null : 'Détenteur : ${derniere['detenteur']}, scellé n° ${derniere['scelle']}',
                  ton: derniere == null ? TonSigh.attention : TonSigh.succes,
                  icone: LucideIcons.fileLock),
            ]),
            const SizedBox(height: 12),
            if (c.peutEcrire || c.peutAnnuler)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (c.peutEcrire) BoutonSigh(libelle: 'Imprimer la copie papier', icone: LucideIcons.printer, onPressed: () => _imprimer(context)),
                  if (c.peutEcrire)
                    BoutonSigh(
                        libelle: 'Afficher le QR d’appairage mobile',
                        icone: LucideIcons.qrCode,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => _qr(context)),
                  if (c.peutAnnuler)
                    BoutonSigh(
                        libelle: 'Faire tourner la clé',
                        icone: LucideIcons.refreshCw,
                        variante: VarianteBouton.danger,
                        onPressed: () => _tourner(context)),
                ]),
              ),
            CarteSigh(
              titre: 'Attestation de la copie papier',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (c.peutEcrire) ...[
                  Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
                    _champ('Détenteur', _detenteur, const Key('mrb:detenteur')),
                    _champ('Scellé n°', _scelle, const Key('mrb:scelle')),
                    _champ('Contrôlé par', _controle, const Key('mrb:controle-par')),
                    BoutonSigh(
                        libelle: 'Enregistrer l’attestation', icone: LucideIcons.check, onPressed: () => _attester(context, c)),
                  ]),
                  const SizedBox(height: 12),
                ],
                MrbTableau(
                  recherche: false,
                  messageVide: 'Aucune attestation enregistrée.',
                  indiceVide: 'Aucun détenteur de la copie papier n’est désigné.',
                  colonnes: [
                    ColonneTableau(cle: 'date', libelle: 'Date', texte: (l) => mrbDateJourIso('${l['date']}')),
                    const ColonneTableau(cle: 'detenteur', libelle: 'Détenteur'),
                    const ColonneTableau(cle: 'scelle', libelle: 'Scellé n°'),
                    const ColonneTableau(cle: 'controlePar', libelle: 'Contrôlé par'),
                  ],
                  lignes: att,
                ),
              ]),
            ),
          ]);
        });
  }
}

/// `2026-10-31` devient `31/10/2026`.
String mrbDateJourIso(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  return m == null ? iso : '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}
