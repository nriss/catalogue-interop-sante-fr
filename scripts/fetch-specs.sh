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
cat > "$TMP/cissis.json" << 'ENDJSON'
[
  {"id":"cissis.cda.fr.structuration-minimale","title":"Structuration minimale des documents de santé","latestVersion":"1.16.8"},
  {"id":"cissis.cda.fr.ips-fr","title":"Synthèse médicale — Patient Summary (IPS-FR)","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.dlu","title":"Dossier de Liaison d'Urgence (DLU)","latestVersion":"2025.01"},
  {"id":"cissis.cda.fr.cr-bio","title":"Compte-rendu de biologie médicale","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.cr-img","title":"Compte-rendu d'imagerie médicale","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.ep-med","title":"ePrescription de médicaments","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.ep-dm","title":"ePrescription de dispositifs médicaux","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.vac","title":"Vaccination","latestVersion":"2023.01"},
  {"id":"cissis.cda.fr.tlm","title":"Télémédecine","latestVersion":"2026.01"},
  {"id":"cissis.cda.fr.frcp","title":"Fiche de Réunion de Concertation Pluridisciplinaire (RCP) en oncologie","latestVersion":"2025.01"},
  {"id":"cissis.cda.fr.obp","title":"Obstétrique et périnatalité","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.cse","title":"Certificats de santé de l'enfant (CS8, CS9, CS24)","latestVersion":"2025.01"},
  {"id":"cissis.cda.fr.sdm-mr","title":"Dataset maladies rares","latestVersion":"2025.01"},
  {"id":"cissis.cda.fr.lls","title":"Lettre de liaison à la sortie d'hospitalisation","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.cr-ope","title":"Compte-rendu opératoire","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.cr-consult","title":"Compte-rendu de consultation","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.phrm","title":"Plan personnalisé de soins (PPS) — Médecine du travail","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.ldm","title":"Lettre de demande / Lettre de référence","latestVersion":"2024.01"},
  {"id":"cissis.cda.fr.vsm","title":"Volet de synthèse médicale (VSM)","latestVersion":"2023.01"},
  {"id":"cissis.cda.fr.tra","title":"Transfert d'un patient (TRA)","latestVersion":"2024.01"}
]
ENDJSON

# ── Preserve descriptions from previous run ───────────────────────────────────
if [[ -f "$OUT" ]]; then
  jq '[(.specs // [])[] | select(.description != null and .description != "") | {(.id): .description}] | add // {}' \
    "$OUT" > "$TMP/descs.json" 2>/dev/null || echo "{}" > "$TMP/descs.json"
else
  echo "{}" > "$TMP/descs.json"
fi

# ── Normalise + merge (Pass 1) ────────────────────────────────────────────────
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
      publisher:     (.authority // "Autre"),
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
      latestUrl:     "https://esante.gouv.fr/offres-services/ci-sis/espace-publication",
      ciBuild:       null,
      historyUrl:    null,
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
