#!/usr/bin/env bash
# OCR pipeline: OCRmyPDF + Tesseract to add text layer to PDFs and create .txt sidecars.
# Optionally triggers DSpace discovery reindex so Solr indexes full text.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTAINER_NAME="${DSPACE_CONTAINER:-dspace}"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
OCR_OUTPUT_DIR="${OCR_OUTPUT_DIR:-}"  # If set, write PDFs+TXT here; else alongside originals
SKIP_EXISTING="${SKIP_EXISTING:-1}"   # Skip PDFs that already have a .txt sidecar
REINDEX="${REINDEX:-1}"              # Run DSpace index-discovery after OCR
COMPOSE_DIR="${COMPOSE_DIR:-$PROJECT_ROOT}"

usage() {
  cat <<EOF
Usage: $0 INPUT_DIR [INPUT_DIR ...]
       $0 --stdin  (read one path per line from stdin)

  Runs OCRmyPDF on PDFs (with Tesseract), writes TXT sidecars alongside each PDF.
  With REINDEX=1 (default), runs DSpace index-discovery so Solr picks up full text.

  Environment:
    OCR_OUTPUT_DIR   If set, write processed PDFs and .txt here (default: same dir as each PDF)
    SKIP_EXISTING    1 = skip PDFs that already have a .txt file (default: 1)
    REINDEX          1 = run 'dspace index-discovery -b' after OCR (default: 1)
    DSPACE_CONTAINER  DSpace container name (default: dspace)
    LOG_DIR           Log directory (default: \$PROJECT_ROOT/logs)
    COMPOSE_DIR       Project root for docker compose (default: \$PROJECT_ROOT)

  Requires: ocrmypdf, tesseract (and optionally pdftotext for .txt extraction).
  Install: pip install ocrmypdf; apt-get install tesseract-ocr poppler-utils
EOF
  exit 0
}

log_ts() { date "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date "+%Y-%m-%d %H:%M:%S"; }
log_msg() { echo "[$(log_ts)] $*" | tee -a "$LOG_FILE"; }
log_err() { echo "[$(log_ts)] ERROR: $*" | tee -a "$LOG_FILE" >&2; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; fi

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ocr-pipeline-$(date +%Y%m%d-%H%M%S).log"

# Collect input paths
INPUTS=()
if [[ "${1:-}" == "--stdin" ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && INPUTS+=("$p")
  done
else
  for d in "$@"; do
    [[ -d "$d" ]] && INPUTS+=("$d")
  done
fi

if [[ ${#INPUTS[@]} -eq 0 ]]; then
  echo "Usage: $0 INPUT_DIR [INPUT_DIR ...] or $0 --stdin" >&2
  exit 1
fi

# Check for ocrmypdf and tesseract
if ! command -v ocrmypdf &>/dev/null; then
  log_err "ocrmypdf not found. Install: pip install ocrmypdf"
  exit 1
fi
if ! command -v tesseract &>/dev/null; then
  log_err "tesseract not found. Install tesseract-ocr."
  exit 1
fi

TXT_EXTRACTOR=""
if command -v pdftotext &>/dev/null; then
  TXT_EXTRACTOR="pdftotext"
elif command -v tesseract &>/dev/null; then
  TXT_EXTRACTOR="tesseract"
fi

process_pdf() {
  local src="$1"
  local dir base out_dir out_pdf out_txt
  dir="$(dirname "$src")"
  base="$(basename "$src" .pdf)"
  if [[ -n "$OCR_OUTPUT_DIR" ]]; then
    mkdir -p "$OCR_OUTPUT_DIR"
    out_dir="$OCR_OUTPUT_DIR"
  else
    out_dir="$dir"
  fi
  out_pdf="$out_dir/${base}.pdf"
  out_txt="$out_dir/${base}.txt"

  if [[ "$SKIP_EXISTING" == "1" && -f "$out_txt" ]]; then
    log_msg "Skip (existing TXT): $src"
    return 0
  fi

  if [[ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" == "$(cd "$(dirname "$out_pdf")" && pwd)/$(basename "$out_pdf")" ]]; then
    local tmp_pdf
    tmp_pdf="$(mktemp -t "ocrmypdf.XXXXXX.pdf")"
    if ocrmypdf -l eng --optimize 0 "$src" "$tmp_pdf" 2>>"$LOG_FILE"; then
      mv "$tmp_pdf" "$out_pdf"
    else
      rm -f "$tmp_pdf"
      log_err "OCR failed: $src"
      return 1
    fi
  else
    if ! ocrmypdf -l eng --optimize 0 "$src" "$out_pdf" 2>>"$LOG_FILE"; then
      log_err "OCR failed: $src"
      return 1
    fi
  fi

  # Create .txt sidecar (from OCR'd PDF)
  local pdf_for_txt="$src"
  [[ -f "$out_pdf" && "$out_pdf" != "$src" ]] && pdf_for_txt="$out_pdf"
  if [[ "$TXT_EXTRACTOR" == "pdftotext" ]]; then
    pdftotext -layout -enc UTF-8 "$pdf_for_txt" "$out_txt" 2>>"$LOG_FILE" || true
  elif [[ "$TXT_EXTRACTOR" == "tesseract" ]]; then
    # Tesseract from PDF: need to use a rendered image or ocrmypdf already embedded text; pdftotext is better. Fallback: tesseract on first page image.
    local tmpimg="$(mktemp -t "ocrpage.XXXXXX.png")"
    if command -v pdftoppm &>/dev/null; then
      pdftoppm -png -f 1 -l 1 "$pdf_for_txt" "${tmpimg%.png}" 2>/dev/null && tesseract "$tmpimg" "${out_txt%.txt}" -l eng 2>>"$LOG_FILE" || true
    fi
    rm -f "$tmpimg" "${tmpimg%.png}.png"
  fi
  if [[ -f "$out_txt" ]]; then
    log_msg "OK: $src -> $out_txt"
  else
    log_msg "OCR done, no TXT: $src"
  fi
  return 0
}

log_msg "Starting OCR pipeline. INPUTS=${INPUTS[*]} SKIP_EXISTING=$SKIP_EXISTING REINDEX=$REINDEX"
count=0
for dir in "${INPUTS[@]}"; do
  while IFS= read -r -d '' pdf; do
    process_pdf "$pdf" || true
    ((count++)) || true
  done < <(find "$dir" -maxdepth 1 -name "*.pdf" -print0 2>/dev/null)
done
log_msg "Processed $count PDF(s)."

if [[ "$REINDEX" == "1" && $count -gt 0 ]]; then
  if docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
    log_msg "Running DSpace index-discovery for Solr."
    if docker exec "$CONTAINER_NAME" /dspace/bin/dspace index-discovery -b 2>>"$LOG_FILE"; then
      log_msg "Index-discovery completed."
    else
      log_err "index-discovery failed (non-fatal)."
    fi
  else
    log_msg "DSpace container not running; skipping index-discovery."
  fi
fi

log_msg "OCR pipeline finished. Log: $LOG_FILE"
echo "Done. Log: $LOG_FILE"
