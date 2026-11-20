import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/theme.dart';
import '../moteur/moteur_mobile.dart';
import 'commun.dart';
import 'note.dart';
import 'prescription.dart';
import 'sage_femme.dart';
import 'tournee.dart';

Future<void> ouvrirDossier(BuildContext context, MoteurMobile moteur, String patientId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DossierPatient(service: moteur.soignant!, patientId: patientId)));

/// Le dossier du patient du lot, en LECTURE (identité, couverture, allergies, motif, dernières constantes, notes, prescriptions).
/// Les gestes sont des commandes : celles que la fonction n'a pas ne sont PAS dessinées (une commande interdite est absente).
class DossierPatient extends StatefulWidget {
  const DossierPatient({super.key, required this.service, required this.patientId});
  final ServiceSoignant service;
  final String patientId;

  @override
  State<DossierPatient> createState() => _DossierPatientState();
}

class _DossierPatientState extends State<DossierPatient> {
  late Future<DossierLu> _dossier = widget.service.dossier(widget.patientId);

  void _recharger() => setState(() {
        _dossier = widget.service.dossier(widget.patientId);
      });

  Future<void> _ouvrir(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) _recharger();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DossierLu>(
      future: _dossier,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return Scaffold(appBar: AppBar(title: const Text('Dossier du patient')), body: Padding(padding: const EdgeInsets.all(16), child: e is RefusMobile ? CarteRefus(e) : Text('$e')));
        }
        if (!snap.hasData) return Scaffold(appBar: AppBar(title: const Text('Dossier du patient')), body: const Center(child: CircularProgressIndicator()));
        final d = snap.data!;
        final r = d.resume;
        final s = widget.service;
        final natures = s.naturesPrescriptibles;
        final suite = ServiceSuite.depuisSoignant(s);
        return Scaffold(
          appBar: AppBar(title: Text(r.nom.isEmpty ? r.code : r.nom), bottom: PreferredSize(preferredSize: const Size.fromHeight(24), child: Text(r.code, style: const TextStyle(color: Colors.white)))),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            CarteTitre(titre: 'Identité', enfants: [
              Text('Âge : ${r.age != null ? '${r.age} ans' : 'non renseigné'}'),
              Text('Quartier : ${r.quartier ?? 'non renseigné'}'),
              Text('Téléphone : ${r.telephone ?? 'non renseigné'}'),
            ]),
            CarteTitre(titre: 'Couverture', enfants: [
              Text(mobLibellesCouverture[r.couverture]!,
                  key: const Key('couverture'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: switch (r.couverture) {
                    MobCouverture.carteValide => ThemeSigh.succes,
                    MobCouverture.carteNonValide => ThemeSigh.danger,
                    MobCouverture.nonAssure => null,
                  })),
              if (r.couverture == MobCouverture.carteNonValide) const Text(mobExplicationCarteNonValide),
            ]),
            CarteTitre(titre: 'Allergies', enfants: [
              r.allergies.isEmpty
                  ? Text(mobTexte('allergiesAucune'), key: const Key('allergies'))
                  : Text(r.allergies.join(', '), key: const Key('allergies'), style: TextStyle(color: ThemeSigh.danger, fontWeight: FontWeight.w700)),
            ]),
            CarteTitre(titre: 'Motif de la visite', enfants: [
              Text(d.rendezVous == null ? 'Aucun rendez-vous aujourd’hui dans le lot.' : '${d.rendezVous!.motif}\nVisite à ${d.rendezVous!.heure}'),
            ]),
            CarteTitre(titre: 'Dernières constantes', enfants: [
              if (r.dernierReleve == null)
                Text(mobTexte('constantesAucune'), key: const Key('constantes-vide'))
              else
                Text(_texteReleve(r.dernierReleve!), key: const Key('constantes-derniere')),
              if (r.horsBornes.isNotEmpty) Text('Hors bornes : ${r.horsBornes.join(', ')}', key: const Key('hors-bornes'), style: TextStyle(color: ThemeSigh.attention, fontWeight: FontWeight.w600)),
            ]),
            CarteTitre(titre: 'Notes de consultation', enfants: [
              if (r.notes.isEmpty) const Text('Aucune note sur ce téléphone.', key: Key('notes-vide')),
              for (final n in r.notes)
                ListTile(
                  key: Key('note-${n['id'] ?? n['date']}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${n['motif'] ?? ''} : ${n['diagnostic'] ?? ''}'),
                  subtitle: Text('${_quand(n['date'])} · ${n['redigePar'] ?? ''}'),
                ),
            ]),
            CarteTitre(titre: 'Prescriptions', enfants: [
              if (r.prescriptions.isEmpty) const Text('Aucune prescription sur ce téléphone.', key: Key('prescriptions-vide')),
              for (final p in r.prescriptions)
                ListTile(
                  key: Key('prescription-${p['id']}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p['nature'] == 'analyse' ? 'Analyses : ${(p['examens'] as List?)?.join(', ') ?? ''}' : 'Ordonnance : ${((p['lignes'] as List?) ?? const []).map((l) => (l as Map)['medicament']).join(', ')}'),
                  subtitle: Text('${_quand(p['date'])} · ${p['prescripteur'] ?? ''}'),
                  trailing: null,
                  isThreeLine: true,
                ),
              for (final p in r.prescriptions) ..._etatTranscription(d.transcriptions['${p['id']}'], '${p['id']}', p['nature'] == 'analyse'),
            ]),
            // Les commandes : une commande dont la fonction n'a pas le droit n'est pas dessinée.
            FilledButton.icon(
              key: const Key('saisir-constantes'),
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('Saisir les constantes'),
              onPressed: () => _ouvrir(SaisieConstantes(service: s, patientId: widget.patientId, titre: r.nom)),
            ),
            if (s.peutSaisirNote) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('nouvelle-note'),
                icon: const Icon(Icons.edit_note),
                label: Text(mobLibelleEcran('consultation')),
                onPressed: () => _ouvrir(SaisieNote(service: s, patientId: widget.patientId, motif: d.rendezVous?.motif ?? '')),
              ),
            ],
            if (natures.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('prescrire'),
                icon: const Icon(Icons.medication_outlined),
                label: Text(mobLibelleEcran('prescription')),
                onPressed: () => _ouvrir(SaisiePrescription(service: s, patientId: widget.patientId)),
              ),
            ],
            // Le profil sage-femme : visite prénatale, visite post-natale, surveillance mère-bébé (la commande n'existe que si le simulateur ouvre l'écran).
            for (final e in const [('cpn', Icons.pregnant_woman, ouvrirCpn), ('cpon', Icons.child_friendly_outlined, ouvrirCpon), ('surveillance', Icons.monitor_heart_outlined, ouvrirSurveillance)])
              if (suite.peut(e.$1)) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: Key('ouvrir-${e.$1}'),
                  icon: Icon(e.$2),
                  label: Text(mobLibelleEcran(e.$1)),
                  onPressed: () async {
                    await e.$3(context, suite, widget.patientId);
                    if (mounted) _recharger();
                  },
                ),
              ],
          ]),
        );
      },
    );
  }

  /// Ce que la clinique a fait de la prescription. La phrase de la maquette (l'ordonnance et la facture de la caisse) n'est dite que quand elles existent.
  static List<Widget> _etatTranscription(MobTranscription? t, String id, bool analyse) {
    if (t == null) return const [];
    return [
      Padding(
        key: Key('transcription-$id'),
        padding: const EdgeInsets.only(bottom: 8, left: 8),
        child: Text(
          switch (t.etat) {
            MobEtatTranscription.transcrite => '${t.libelle} ${analyse ? mobTexte('analyses') : mobTexte('prescription')}',
            MobEtatTranscription.refusee => '${t.libelle}\nÀ faire : ${t.geste ?? ''} (${t.code ?? ''})',
            MobEtatTranscription.attente => t.libelle,
          },
          style: TextStyle(color: t.etat == MobEtatTranscription.refusee ? ThemeSigh.danger : null, fontSize: 13),
        ),
      ),
    ];
  }

  static String _quand(Object? v) {
    final d = DateTime.tryParse('$v');
    return d == null ? '' : '${dateFR(d)} ${heure(d)}';
  }

  static String _texteReleve(Map<String, Object?> r) {
    final morceaux = <String>[
      if (r['temperature'] != null) 'T° ${r['temperature']}',
      if (r['tension'] != null) 'TA ${r['tension']}',
      if (r['pouls'] != null) 'pouls ${r['pouls']}',
      if (r['fr'] != null) 'FR ${r['fr']}',
      if (r['spo2'] != null) 'SpO₂ ${r['spo2']} %',
      if (r['poids'] != null) '${r['poids']} kg',
    ];
    return '${morceaux.join(' · ')}\n${_quand(r['dateHeure'])}';
  }
}
