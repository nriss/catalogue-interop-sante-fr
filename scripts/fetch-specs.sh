#!/usr/bin/env bash
# Regenerates data/specs.json by fetching all French interop spec registries.
# Merges live data with existing descriptions (preserved from previous run).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUT="$REPO_ROOT/data/specs.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

log() { echo "[fetch-specs] $*" >&2; }

# Safe fetch to a file: writes "null" on error
fetch_to() {
  local url="$1" dest="$2"
  log "Fetching $url"
  curl -sf --max-time 30 --retry 2 "$url" > "$dest" 2>/dev/null || echo "null" > "$dest"
}

# ── Fetch all sources ─────────────────────────────────────────────────────────
fetch_to "https://interop.esante.gouv.fr/ig/fhir/package-registry.json"  "$TMP/ans_fhir.json"
fetch_to "https://interop.esante.gouv.fr/ig/package-registry.json"       "$TMP/ans_other.json"
fetch_to "https://interop.esante.gouv.fr/ig/hl7v2/package-registry.json" "$TMP/ans_hl7v2.json"
fetch_to "https://interop.esante.gouv.fr/ig/cda/package-registry.json"   "$TMP/ans_cda.json"
fetch_to "https://hl7.fr/ig/fhir/package-registry.json"                  "$TMP/hl7_fr.json"
fetch_to "https://raw.githubusercontent.com/FHIR/ig-registry/master/fhir-ig-list.json" "$TMP/hl7_global.json"

# ── Static CI-SIS CDA volets (PDF-only, no machine-readable catalog) ──────────
cat > "$TMP/cissis.json" << 'ENDJSON'
[
  {"id":"cissis.cda.fr.structuration-minimale","title":"Structuration minimale des documents de santé (CI-SIS)","latestVersion":"1.16.8"},
  {"id":"cissis.cda.fr.ips-fr","title":"Synthèse médicale — IPS-FR (CI-SIS)","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.dlu","title":"Dossier de Liaison d'Urgence (DLU) — CI-SIS","latestVersion":"2025.01"},
  {"id":"cissis.cda.fr.cr-bio","title":"Compte-rendu de biologie médicale (CI-SIS)","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.cr-img","title":"Compte-rendu d'imagerie médicale (CI-SIS)","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.ep-med","title":"ePrescription de médicaments (CI-SIS)","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.ep-dm","title":"ePrescription de dispositifs médicaux (CI-SIS)","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.vac","title":"Vaccination (CI-SIS)","latestVersion":"2023.01"},
  {"id":"cissis.cda.fr.tlm","title":"Télémédecine (CI-SIS)","latestVersion":"2026.01"},
  {"id":"cissis.cda.fr.frcp","title":"Fiche RCP Cancer (CI-SIS)","latestVersion":"2025.01"},
  {"id":"cissis.cda.fr.obp","title":"Obstétrique et périnatalité (CI-SIS)","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.cse","title":"Certificats de santé de l'enfant (CI-SIS)","latestVersion":"2025.01"},
  {"id":"cissis.cda.fr.sdm-mr","title":"Dataset maladies rares (CI-SIS)","latestVersion":"2025.01"}
]
ENDJSON

# ── Extract existing descriptions to preserve them ────────────────────────────
if [[ -f "$OUT" ]]; then
  jq '[(.specs // [])[] | select(.description != null and .description != "") | {(.id): .description}] | add // {}' \
    "$OUT" > "$TMP/descs.json" 2>/dev/null || echo "{}" > "$TMP/descs.json"
else
  echo "{}" > "$TMP/descs.json"
fi

# ── Normalize + merge with jq (using file inputs, no arg size limit) ──────────
jq -n \
  --slurpfile ans_fhir   "$TMP/ans_fhir.json" \
  --slurpfile ans_other  "$TMP/ans_other.json" \
  --slurpfile ans_hl7v2  "$TMP/ans_hl7v2.json" \
  --slurpfile ans_cda    "$TMP/ans_cda.json" \
  --slurpfile hl7_fr     "$TMP/hl7_fr.json" \
  --slurpfile hl7_global "$TMP/hl7_global.json" \
  --slurpfile cissis     "$TMP/cissis.json" \
  --slurpfile descs      "$TMP/descs.json" \
  --arg ts               "$TIMESTAMP" \
'
# --slurpfile wraps the value in an array; unwrap with .[0]
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
      historyUrl:    (.history // ((.canonical // "") + "/history.html"))
    });

def normalize_hl7_global(data):
  to_arr(data)
  | map(select(.country == "fr" or .language == "fr"))
  | map({
      id:            (.["npm-name"] // ""),
      title:         (.name // .["npm-name"] // ""),
      description:   (.description // ""),
      canonical:     (.canonical // ""),
      publisher:     (.authority // "Autre"),
      specType:      "FHIR",
      fhirVersion:   ((.editions // [{}])[0]["fhir-version"] // []),
      latestVersion: ((.editions // [{}])[-1]["ig-version"] // null),
      latestDate:    null,
      latestUrl:     ((.editions // [{}])[-1].url // .canonical // ""),
      ciBuild:       (.["ci-build"] // null),
      historyUrl:    (.history // null)
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
      latestUrl:     "https://esante.gouv.fr/offres-services/ci-sis/espace-publication",
      ciBuild:       null,
      historyUrl:    null
    });

# Merge all sources
(
  normalize_registry(src($ans_fhir);   "ANS";        "FHIR")  +
  normalize_registry(src($ans_other);  "ANS";        "Autre") +
  normalize_registry(src($ans_hl7v2);  "ANS";        "HL7v2") +
  normalize_registry(src($ans_cda);    "ANS";        "CDA")   +
  normalize_registry(src($hl7_fr);     "HL7 France"; "FHIR")  +
  normalize_hl7_global(src($hl7_global))                      +
  normalize_cissis(src($cissis))
)
# Restore descriptions from previous run
| map(. as $s |
    .description = (
      if (.description // "" | length) > 0 then .description
      else (src($descs)[.id] // "")
      end
    )
  )
# Deduplicate: CI-SIS entries all share the same canonical URL, so dedup by id for them;
# for all others, dedup by canonical (keeps first occurrence = higher-priority source wins)
| group_by(
    if .canonical == "https://esante.gouv.fr/offres-services/ci-sis/espace-publication"
    then .id
    else .canonical
    end
  )
| map(.[0])
| sort_by([.publisher, .title])
| {
    lastUpdated: $ts,
    count: length,
    specs: .
  }
' > "$OUT"

COUNT=$(jq '.count' "$OUT")
log "Done. $COUNT specs written to $OUT"
