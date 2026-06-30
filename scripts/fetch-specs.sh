#!/usr/bin/env bash
# Regenerates data/specs.json by fetching all French interop spec registries.
# Pass 1 : normalise each source registry (ANS, HL7 France, ig-registry, CI-SIS static)
# Pass 2 : enriches each spec with description, fhirVersion, status from package-list.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUT="$REPO_ROOT/data/specs.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

log() { echo "[fetch-specs] $*" >&2; }

fetch_to() {
  local url="$1" dest="$2"
  log "Fetching $url"
  curl -sf --max-time 30 --retry 2 "$url" > "$dest" 2>/dev/null || echo "null" > "$dest"
}

# ── Pass 1 : fetch source registries ─────────────────────────────────────────
fetch_to "https://interop.esante.gouv.fr/ig/fhir/package-registry.json"  "$TMP/ans_fhir.json"
fetch_to "https://interop.esante.gouv.fr/ig/package-registry.json"       "$TMP/ans_other.json"
fetch_to "https://interop.esante.gouv.fr/ig/hl7v2/package-registry.json" "$TMP/ans_hl7v2.json"
fetch_to "https://interop.esante.gouv.fr/ig/cda/package-registry.json"   "$TMP/ans_cda.json"
fetch_to "https://hl7.fr/ig/fhir/package-registry.json"                  "$TMP/hl7_fr.json"
fetch_to "https://raw.githubusercontent.com/FHIR/ig-registry/master/fhir-ig-list.json" "$TMP/hl7_global.json"

# ── Static CI-SIS CDA volets (PDF only, no machine-readable catalog) ──────────
# Sources: https://esante.gouv.fr/offres-services/ci-sis/espace-publication (verified 2026-06-30)
cat > "$TMP/cissis.json" << 'ENDJSON'
[
  {"id":"cissis.cda.fr.structuration-minimale","title":"Structuration minimale des documents de santé","latestVersion":"1.16.8","url":"https://esante.gouv.fr/volet-structuration-minimale-de-documents-de-sante"},
  {"id":"cissis.cda.fr.modeles-contenus","title":"Modèles de contenus CDA","latestVersion":"3.15","url":"https://esante.gouv.fr/volet-de-reference-modeles-de-contenus-cda"},
  {"id":"cissis.cda.fr.ips-fr","title":"Synthèse médicale (IPS-FR)","latestVersion":"2024.01","url":"https://esante.gouv.fr/volet-synthese-medicale"},
  {"id":"cissis.cda.fr.vsm","title":"Volet de synthèse médicale (VSM)","latestVersion":"2023.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.dlu","title":"Dossier de liaison d'urgence (DLU)","latestVersion":"2025.01","url":"https://esante.gouv.fr/volet-dlu-dossier-de-liaison-durgence"},
  {"id":"cissis.cda.fr.lls","title":"Lettre de liaison à la sortie d'hospitalisation","latestVersion":"2024.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.idl","title":"Informations de liaison (IDL)","latestVersion":"2022.01","url":"https://esante.gouv.fr/volet-idl-informations-de-liaison"},
  {"id":"cissis.cda.fr.ldm","title":"Lettre de demande / Lettre de référence","latestVersion":"2024.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.tra","title":"Transfert d'un patient (TRA)","latestVersion":"2024.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.cr-bio","title":"Compte-rendu de biologie médicale (CR-BIO)","latestVersion":"2024.01","url":"https://esante.gouv.fr/volet-cr-bio-compte-rendu-dexamens-de-biologie-medicale"},
  {"id":"cissis.cda.fr.bio-trod","title":"Test rapide d'orientation diagnostique (BIO-TROD)","latestVersion":"2024.01","url":"https://esante.gouv.fr/volet-bio-trod"},
  {"id":"cissis.cda.fr.cr-img","title":"Compte-rendu d'imagerie médicale (IMG-CR-IMG)","latestVersion":"2024.01","url":"https://esante.gouv.fr/volet-imagerie-cr-imagerie"},
  {"id":"cissis.cda.fr.img-da-img","title":"Demande d'actes d'imagerie (IMG-DA-IMG)","latestVersion":"2024.01","url":"https://esante.gouv.fr/volet-img-demande-dactes-dimagerie"},
  {"id":"cissis.cda.fr.cr-ope","title":"Compte-rendu opératoire","latestVersion":"2024.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.cr-consult","title":"Compte-rendu de consultation","latestVersion":"2024.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.anest-cr-cpa","title":"Compte-rendu de consultation pré-anesthésique (ANEST-CR-CPA)","latestVersion":"2022.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.anest-cr-anest","title":"Compte-rendu d'anesthésie (ANEST-CR-ANEST)","latestVersion":"2022.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.ep-med-dm","title":"ePrescription de produits de santé (médicaments et dispositifs médicaux)","latestVersion":"2024.01","url":"https://esante.gouv.fr/volet-eprescription-de-produits-de-sante-medicaments-etou-dispositifs-medicaux"},
  {"id":"cissis.cda.fr.edisp-med","title":"eDispensation de médicaments (eDisp-MED)","latestVersion":"2024.01","url":"https://esante.gouv.fr/volet-edispensation-de-medicaments"},
  {"id":"cissis.cda.fr.vac","title":"Vaccination (VAC)","latestVersion":"2023.01","url":"https://esante.gouv.fr/node/12535"},
  {"id":"cissis.cda.fr.tlm","title":"Télémédecine (TLM)","latestVersion":"2026.01","url":"https://esante.gouv.fr/volet-tlm-telemedecine"},
  {"id":"cissis.cda.fr.frcp","title":"Fiche de Réunion de Concertation Pluridisciplinaire (FRCP)","latestVersion":"2025.01","url":"https://esante.gouv.fr/volet-frcp-fiche-de-reunion-de-concertation-pluridisciplinaire"},
  {"id":"cissis.cda.fr.cancer-pps","title":"Programme personnalisé de soins en cancérologie (CANCER-PPS)","latestVersion":"2025.01","url":"https://esante.gouv.fr/volet-cancer-pps-programme-personnalise-de-soins-en-cancerologie"},
  {"id":"cissis.cda.fr.phrm","title":"Plan personnalisé de soins — Médecine du travail","latestVersion":"2024.01","url":"https://esante.gouv.fr/offres-services/ci-sis/espace-publication"},
  {"id":"cissis.cda.fr.obp","title":"Obstétrique et périnatalité (OBP)","latestVersion":"2024.01","url":"https://esante.gouv.fr/volet-obp-obstetrique-et-perinatalite"},
  {"id":"cissis.cda.fr.cse","title":"Certificats de santé de l'enfant — CS8, CS9, CS24","latestVersion":"2025.01","url":"https://esante.gouv.fr/certificats-de-sante-de-lenfant-volet-cse"},
  {"id":"cissis.cda.fr.cse-mde","title":"Mesures de l'enfant (CSE-MDE)","latestVersion":"2023.01","url":"https://esante.gouv.fr/volet-cse-mesures-de-lenfant"},
  {"id":"cissis.cda.fr.sdm-mr","title":"Set de données minimum maladies rares (SDM-MR)","latestVersion":"2025.01","url":"https://esante.gouv.fr/volet-sdm-mr-set-de-donnees-minimum-maladies-rares"},
  {"id":"cissis.cda.fr.avc","title":"Accident vasculaire cérébral (AVC)","latestVersion":"2022.01","url":"https://esante.gouv.fr/volet-avc-accident-vasculaire-cerebral"},
  {"id":"cissis.cda.fr.card-f-prc","title":"Cardiologie — Fiches patient à risque (CARD-F-PRC)","latestVersion":"2022.01","url":"https://esante.gouv.fr/volet-card-f-prc-cardiologie-fiches-patient-risque-en-cardiologie"},
  {"id":"cissis.cda.fr.cr-gm","title":"Compte-rendu de génétique moléculaire (CR-GM)","latestVersion":"2022.01","url":"https://esante.gouv.fr/volet-cr-gm-compte-rendu-de-genetique-moleculaire"},
  {"id":"cissis.cda.fr.cancer-d2lm","title":"Dématérialisation de la seconde lecture de mammographie (CANCER-D2LM)","latestVersion":"2022.01","url":"https://esante.gouv.fr/volet-cancer-d2lm-dematerialisation-de-la-seconde-lecture-de-mammographie"},
  {"id":"cissis.cda.fr.oph-bre","title":"Ophtalmologie — Bilan de réfraction (OPH-BRE)","latestVersion":"2022.02","url":"https://esante.gouv.fr/volet-oph-bre"},
  {"id":"cissis.cda.fr.oph-cr-rtn","title":"Compte-rendu de rétinographie (OPH-CR-RTN)","latestVersion":"2022.01","url":"https://esante.gouv.fr/volet-oph-cr-rtn-compte-rendu-de-retinographie"},
  {"id":"cissis.cda.fr.cnam-hr","title":"Historique des remboursements (CNAM-HR)","latestVersion":"2021.01","url":"https://esante.gouv.fr/volet-cnam-hr-historique-des-remboursements"}
]
ENDJSON

# ── Preserve description/status/fhirVersion from previous run ────────────────
if [[ -f "$OUT" ]]; then
  jq '[(.specs // [])[] | select(.description != null and .description != "") | {(.id): .description}] | add // {}' \
    "$OUT" > "$TMP/descs.json" 2>/dev/null || echo "{}" > "$TMP/descs.json"
  jq '[(.specs // [])[] | select(.status != null and .status != "") | {(.id): .status}] | add // {}' \
    "$OUT" > "$TMP/prev_status.json" 2>/dev/null || echo "{}" > "$TMP/prev_status.json"
  jq '[(.specs // [])[] | select((.fhirVersion // []) | length > 0) | {(.id): .fhirVersion}] | add // {}' \
    "$OUT" > "$TMP/prev_fhir.json" 2>/dev/null || echo "{}" > "$TMP/prev_fhir.json"
else
  echo "{}" > "$TMP/descs.json"
  echo "{}" > "$TMP/prev_status.json"
  echo "{}" > "$TMP/prev_fhir.json"
fi

# ── Normalise + merge (Pass 1) ────────────────────────────────────────────────
jq -n \
  --slurpfile ans_fhir     "$TMP/ans_fhir.json" \
  --slurpfile ans_other    "$TMP/ans_other.json" \
  --slurpfile ans_hl7v2    "$TMP/ans_hl7v2.json" \
  --slurpfile ans_cda      "$TMP/ans_cda.json" \
  --slurpfile hl7_fr       "$TMP/hl7_fr.json" \
  --slurpfile hl7_global   "$TMP/hl7_global.json" \
  --slurpfile cissis       "$TMP/cissis.json" \
  --slurpfile descs        "$TMP/descs.json" \
  --slurpfile prev_status  "$TMP/prev_status.json" \
  --slurpfile prev_fhir    "$TMP/prev_fhir.json" \
  --arg ts                 "$TIMESTAMP" \
'
def src(f): f[0];

def to_arr(x):
  if x == null then []
  elif (x | type) == "array" then x
  else (x.guides // x.packages // [])
  end;

def normalize_registry(data; publisher; spec_type):
  to_arr(data)
  | map(select(. != null and ((.["package-id"] // .id) != null)))
  | map({
      id:            (.["package-id"] // .id // ""),
      title:         (.title // .name // ""),
      description:   (.description // .introduction // ""),
      canonical:     (.canonical // ""),
      publisher:     publisher,
      specType:      spec_type,
      fhirVersion:   (.fhirVersion // .["fhir-version"] // []),
      latestVersion: (.latest.version // null),
      latestDate:    (.latest.date // null),
      latestUrl:     (.latest.path // .canonical // ""),
      ciBuild:       (.["ci-build"] // null),
      historyUrl:    (.history // ((.canonical // "") + "/history.html")),
      status:        ""
    });

def normalize_hl7_global(data):
  to_arr(data)
  | map(select(.country == "fr" or .language == "fr"))
  | map({
      id:            (.["npm-name"] // ""),
      title:         (.name // .["npm-name"] // ""),
      description:   (.description // ""),
      canonical:     (.canonical // ""),
      publisher:     (if (.authority // "" | test("^ANS")) then "ANS" else (.authority // "Autre") end),
      specType:      "FHIR",
      fhirVersion:   ((.editions // [{}])[0]["fhir-version"] // []),
      latestVersion: ((.editions // [{}])[-1]["ig-version"] // null),
      latestDate:    null,
      latestUrl:     ((.editions // [{}])[-1].url // .canonical // ""),
      ciBuild:       (.["ci-build"] // null),
      historyUrl:    (.history // null),
      status:        ""
    });

def normalize_cissis(data):
  to_arr(data)
  | map({
      id:            .id,
      title:         .title,
      description:   "",
      canonical:     "https://esante.gouv.fr/offres-services/ci-sis/espace-publication",
      publisher:     "ANS (CI-SIS)",
      specType:      "CDA",
      fhirVersion:   [],
      latestVersion: .latestVersion,
      latestDate:    null,
      latestUrl:     (.url // "https://esante.gouv.fr/offres-services/ci-sis/espace-publication"),
      ciBuild:       null,
      historyUrl:    (.url // null),
      status:        ""
    });

(
  normalize_registry(src($ans_fhir);   "ANS";        "FHIR")  +
  normalize_registry(src($ans_other);  "ANS";        "Autre") +
  normalize_registry(src($ans_hl7v2);  "ANS";        "HL7v2") +
  normalize_registry(src($ans_cda);    "ANS";        "CDA")   +
  normalize_registry(src($hl7_fr);     "HL7 France"; "FHIR")  +
  normalize_hl7_global(src($hl7_global))                      +
  normalize_cissis(src($cissis))
)
| map(. as $s |
    .description = (
      if (.description // "" | length) > 0 then .description
      else (src($descs)[.id] // "")
      end
    )
    | .status = (
        if (.status // "" | length) > 0 then .status
        else (src($prev_status)[.id] // "")
        end
      )
    | .fhirVersion = (
        if (.fhirVersion | length) > 0 then .fhirVersion
        elif ((src($prev_fhir)[.id] // []) | length) > 0 then src($prev_fhir)[.id]
        else []
        end
      )
  )
| group_by(
    if .canonical == "https://esante.gouv.fr/offres-services/ci-sis/espace-publication"
    then .id
    else .canonical
    end
  )
| map(.[0])
| sort_by([.publisher, .title])
| {lastUpdated: $ts, count: length, specs: .}
' > "$OUT"

# ── Pass 2 : enrich with package-list.json ───────────────────────────────────
log "Enriching with package-list.json (description, fhirVersion, status)..."
echo "{}" > "$TMP/enrichment.json"

while IFS=$'\t' read -r id canonical; do
  [[ -z "$canonical" || "$canonical" == "null" ]] && continue
  pkg_url="${canonical}/package-list.json"
  log "  $id"
  raw=$(curl -sf --max-time 15 "$pkg_url" 2>/dev/null || echo "null")
  enrich=$(printf '%s' "$raw" | jq -c '
    if . == null or type != "object" then {}
    else
      (
        (.list // []) |
        (map(select(.current == true and .version != "current")) | first) //
        (map(select(.version != "current" and (.status // "" | . != "ci-build"))) | last) //
        {}
      ) as $cur |
      {
        description: (.introduction // ""),
        fhirVersion: ([($cur.fhirversion // "")] | map(select(length > 0))),
        status:      ($cur.status // "")
      }
    end
  ' 2>/dev/null || echo '{}')
  jq --arg id "$id" --argjson e "$enrich" '. + {($id): $e}' \
    "$TMP/enrichment.json" > "$TMP/enrich_new.json"
  mv "$TMP/enrich_new.json" "$TMP/enrichment.json"
done < <(jq -r '
  .specs[] |
  select(
    (.canonical // "" | startswith("http")) and
    (.canonical // "" | contains("offres-services") | not)
  ) |
  "\(.id)\t\(.canonical)"
' "$OUT")

jq --slurpfile enrich "$TMP/enrichment.json" '
  . + {specs: (.specs | map(
    . as $s |
    ($enrich[0][$s.id] // {}) as $e |
    $s
    | .description = (if (.description // "" | length) > 0 then .description else ($e.description // "") end)
    | .fhirVersion = (
        if (.fhirVersion | length) > 0 then .fhirVersion
        elif (($e.fhirVersion // []) | length) > 0 then $e.fhirVersion
        else []
        end
      )
    | .status = (if (.status // "" | length) > 0 then .status else ($e.status // "") end)
  ))}
' "$OUT" > "$TMP/enriched.json" && mv "$TMP/enriched.json" "$OUT"

COUNT=$(jq '.count' "$OUT")
log "Done. $COUNT specs written to $OUT (with descriptions + fhirVersion + status)"
