#!/usr/bin/env bash
# Regenerates data/specs.json by fetching all French interop spec registries.
# Merges live data with existing descriptions (preserved from previous run).
# Outputs the merged JSON to data/specs.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUT="$REPO_ROOT/data/specs.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() { echo "[fetch-specs] $*" >&2; }

# Safe fetch: returns "null" on error (jq handles null arrays gracefully)
fetch() {
  local url="$1"
  log "Fetching $url"
  curl -sf --max-time 30 --retry 2 "$url" 2>/dev/null || echo "null"
}

# ── Load existing descriptions to preserve them ──────────────────────────────
EXISTING_DESCS="{}"
if [[ -f "$OUT" ]]; then
  EXISTING_DESCS=$(jq '[(.specs // [])[] | select(.description != null and .description != "") | {(.id): .description}] | add // {}' "$OUT" 2>/dev/null || echo "{}")
fi

# ── Fetch all sources ─────────────────────────────────────────────────────────
ANS_FHIR=$(fetch "https://interop.esante.gouv.fr/ig/fhir/package-registry.json")
ANS_OTHER=$(fetch "https://interop.esante.gouv.fr/ig/package-registry.json")
HL7_FR=$(fetch "https://hl7.fr/ig/fhir/package-registry.json")
HL7_GLOBAL=$(fetch "https://raw.githubusercontent.com/FHIR/ig-registry/master/fhir-ig-list.json")

# ── Static CI-SIS CDA volets (PDF-only, no machine-readable catalog) ──────────
read -r -d '' CISSIS_STATIC << 'ENDJSON' || true
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

# ── Normalize + merge with jq ─────────────────────────────────────────────────
jq -n \
  --argjson ans_fhir  "$ANS_FHIR" \
  --argjson ans_other "$ANS_OTHER" \
  --argjson hl7_fr    "$HL7_FR" \
  --argjson hl7_global "$HL7_GLOBAL" \
  --argjson cissis    "$CISSIS_STATIC" \
  --argjson descs     "$EXISTING_DESCS" \
  --arg     ts        "$TIMESTAMP" \
'
# Normalize ANS/HL7-France package-registry format
def to_arr: if . == null then [] elif type == "array" then . else (.guides // .packages // []) end;

def normalize_registry(publisher; spec_type):
  to_arr
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

# Normalize HL7 global registry — filter French entries
def normalize_hl7_global:
  to_arr
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

# Normalize static CI-SIS entries
def normalize_cissis:
  ($cissis // [])
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
  ($ans_fhir  | normalize_registry("ANS";        "FHIR"))  +
  ($ans_other | normalize_registry("ANS";        "Autre")) +
  ($hl7_fr    | normalize_registry("HL7 France"; "FHIR"))  +
  ($hl7_global | normalize_hl7_global)                     +
  normalize_cissis
)
# Restore descriptions from previous run for entries where API gives none
| map(. as $s | .description = (if (.description // "" | length) > 0 then .description else ($descs[.id] // "") end))
# Deduplicate by canonical (keep first occurrence)
| (. | indices(map(.canonical)) | . as $idx |
   [ range(length) | select(. as $i | $idx[.] == $i) ] | map(.[. as $i | . as $_ | $i]) )
| . as $deduped
# Actually simpler dedup:
| group_by(.canonical)
| map(sort_by(.publisher) | .[0])
| sort_by([.publisher, .title])
| {
    lastUpdated: $ts,
    count: length,
    specs: .
  }
' > "$OUT"

COUNT=$(jq '.count' "$OUT")
log "Done. $COUNT specs written to $OUT"
