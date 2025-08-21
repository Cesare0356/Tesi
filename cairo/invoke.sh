#!/bin/bash
set -euo pipefail

source katana.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_FILE="${SCRIPT_DIR}/deployment_address.txt"
CONTRACT_MSG_ADDRESS_FILE="${SCRIPT_DIR}/contract_msg_address.txt"

# --- Controlli file input ---
if [ ! -f "$DEPLOYMENT_FILE" ]; then
  echo "Errore: file ${DEPLOYMENT_FILE} non trovato." >&2
  exit 1
fi
if [ ! -f "$CONTRACT_MSG_ADDRESS_FILE" ]; then
  echo "Errore: file ${CONTRACT_MSG_ADDRESS_FILE} non trovato." >&2
  exit 1
fi

# --- Lettura e validazione indirizzi ---
L2_CONTRACT_ADDRESS="$(tr -d ' \t\r\n' < "$DEPLOYMENT_FILE")"
if ! echo "$L2_CONTRACT_ADDRESS" | grep -Eq '^0x[0-9a-fA-F]+$'; then
  echo "Errore: L2_CONTRACT_ADDRESS non valido in ${DEPLOYMENT_FILE}: '${L2_CONTRACT_ADDRESS}'" >&2
  exit 1
fi

CONTRACT_MSG_ADDRESS="$(tr -d ' \t\r\n' < "$CONTRACT_MSG_ADDRESS_FILE")"
if ! echo "$CONTRACT_MSG_ADDRESS" | grep -Eq '^0x[0-9a-fA-F]+$'; then
  echo "Errore: CONTRACT_MSG_ADDRESS non valido in ${CONTRACT_MSG_ADDRESS_FILE}: '${CONTRACT_MSG_ADDRESS}'" >&2
  exit 1
fi

# --- Target env files ---
SOLIDITY_DIR="../solidity"
DOT_ENV_FILE="${SOLIDITY_DIR}/.env"
ENV_FILE="${SOLIDITY_DIR}/env"
ANVIL_ENV_FILE="${SOLIDITY_DIR}/anvil.env"
FILES_TO_UPDATE=("$DOT_ENV_FILE" "$ENV_FILE" "$ANVIL_ENV_FILE")

# --- sed portabile ---
if [[ "${OSTYPE:-}" == "darwin"* ]]; then
  SED_INPLACE=(sed -i '')
else
  SED_INPLACE=(sed -i)
fi

upsert_env_var () {
  local file="$1" key="$2" value="$3"
  if [ ! -f "$file" ]; then
    echo "Avviso: il file ${file} non è stato trovato. Salto l'aggiornamento."
    return
  fi
  if grep -Eq "^(export[[:space:]]*)?${key}=" "$file"; then
    "${SED_INPLACE[@]}" "s|^${key}=.*|${key}=${value}|" "$file"
    "${SED_INPLACE[@]}" "s|^export[[:space:]]*${key}=.*|export ${key}=${value}|" "$file"
  else
    printf "\n%s=%s\n" "$key" "$value" >> "$file"
  fi
  echo "     -> $(grep -E "^(export[[:space:]]*)?${key}=" "$file" | tail -n1)"
}

echo "Avvio invoke su L2..."
echo
echo "Contratto L2: ${L2_CONTRACT_ADDRESS}"
echo "ContractMsg : ${CONTRACT_MSG_ADDRESS}"
echo

# --- Usa il VALORE dell'indirizzo, non il path del file ---
INVOKE_OUTPUT=$(
  starkli invoke "$L2_CONTRACT_ADDRESS" leave_review \
    0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    "$CONTRACT_MSG_ADDRESS" \
    1 \
    4 0x63 0x69 0x61 0x6f \
  2>&1
)


TX_HASH=$(printf "%s\n" "$INVOKE_OUTPUT" | grep -Eo '0x[0-9a-fA-F]{64}' | tail -n1)
if [ -z "$TX_HASH" ]; then
  echo "Errore: impossibile estrarre l'hash della transazione dall'output." >&2
  exit 1
fi

echo "Tx hash: ${TX_HASH}"
echo

echo "Recupero receipt (polling)..."
MAX_RETRIES="${MAX_RETRIES:-60}"
SLEEP_SECS="${SLEEP_SECS:-1}"
RECEIPT_JSON=""
RAW_RECEIPT=""

for ((i=1; i<=MAX_RETRIES; i++)); do
  set +e
  RAW_RECEIPT=$(starkli tx-receipt "$TX_HASH" 2>&1)
  STATUS=$?
  set -e
  if [ $STATUS -eq 0 ] && printf "%s" "$RAW_RECEIPT" | jq -e . >/dev/null 2>&1; then
    EXEC_STATUS=$(printf "%s" "$RAW_RECEIPT" | jq -r '.execution_status // empty')
    MAYBE_PAYLOAD=$(printf "%s" "$RAW_RECEIPT" | jq -r 'try .messages_sent[0].payload[1] // empty')
    if [ "$EXEC_STATUS" = "SUCCEEDED" ] || [ -n "$MAYBE_PAYLOAD" ]; then
      RECEIPT_JSON=$(printf "%s" "$RAW_RECEIPT" | jq -c .)
      break
    fi
  fi
  echo "retry $i/$MAX_RETRIES"
  sleep "$SLEEP_SECS"
done

if [ -z "$RECEIPT_JSON" ]; then
  echo "Errore: receipt non disponibile dopo $MAX_RETRIES tentativi." >&2
  printf "%s\n" "$RAW_RECEIPT"
  exit 1
fi

echo "$RECEIPT_JSON"
echo

PAYLOAD_SECOND=$(printf "%s" "$RECEIPT_JSON" | jq -r '
  if (.messages_sent | type == "array" and length > 0)
     and (.messages_sent[0].payload | type == "array" and length > 1)
  then .messages_sent[0].payload[1]
  else empty end
')

if [ -z "$PAYLOAD_SECOND" ] || [ "$PAYLOAD_SECOND" = "null" ]; then
  echo "Errore: impossibile estrarre messages_sent[0].payload[1] dal receipt." >&2
  exit 1
fi

echo "Payload[1]: ${PAYLOAD_SECOND}"
echo

echo "Aggiornamento dei file .env nella cartella solidity..."
for file_path in "${FILES_TO_UPDATE[@]}"; do
  if [ -f "$file_path" ]; then
    echo "   - Aggiornamento di ${file_path}..."
    upsert_env_var "$file_path" "L2_VALUE" "$PAYLOAD_SECOND"
    echo "   - fatto."
  else
    echo "   - ${file_path} non trovato. Salto l'aggiornamento."
  fi
done