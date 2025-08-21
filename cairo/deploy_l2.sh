#!/bin/bash
set -euo pipefail

CONTRACT_NAME="messaging_tuto_contract_msg"
ADDRESS_FILE="deployment_address.txt"

echo "Inizio deploy del contratto L2..."
source katana.env

# Build
scarb build
CLASS_FILE_PATH="./target/dev/${CONTRACT_NAME}.contract_class.json"

# Declare (senza --compiler-version: deprecato e ignorato)
DECLARE_OUTPUT="$(starkli declare "$CLASS_FILE_PATH" 2>&1 || true)"
echo "$DECLARE_OUTPUT"

# Estrai CLASS_HASH: gestisce "Class hash declared:" e "already declared"
CLASS_HASH="$(
  printf '%s\n' "$DECLARE_OUTPUT" | awk '
    BEGIN{grab=0}
    /^Class hash declared:$/ {grab=1; next}
    /^Not declaring class as it'\''s already declared\. Class hash:$/ {grab=1; next}
    grab && $0 ~ /^0x[0-9a-fA-F]+$/ {print; exit}
  '
)"
# Fallback su "Declaring Cairo 1 class:"
if [ -z "$CLASS_HASH" ]; then
  CLASS_HASH="$(printf '%s\n' "$DECLARE_OUTPUT" | sed -n 's/^Declaring Cairo 1 class:[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p' | head -n1)"
fi
# Fallback estremo: prendi l’ultimo 0x{64} che NON sia il CASM
if [ -z "$CLASS_HASH" ]; then
  CASM_HASH="$(printf '%s\n' "$DECLARE_OUTPUT" | sed -n 's/^CASM class hash:[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p' | head -n1)"
  CLASS_HASH="$(
    printf '%s\n' "$DECLARE_OUTPUT" \
    | grep -E '^0x[0-9a-fA-F]{64}$' \
    | grep -v -F "${CASM_HASH:-}" \
    | tail -n1
  )"
fi
[ -z "$CLASS_HASH" ] && { echo "Errore: impossibile estrarre CLASS_HASH."; exit 1; }

# Estrai TX della declare (nuovo e vecchio formato)
DECLARE_TX="$(
  printf '%s\n' "$DECLARE_OUTPUT" \
  | grep -Eo 'Contract declaration transaction:[[:space:]]*0x[0-9a-fA-F]+' \
  | awk '{print $NF}' \
  | tail -n1
)"
[ -z "$DECLARE_TX" ] && DECLARE_TX="$(
  printf '%s\n' "$DECLARE_OUTPUT" \
  | grep -Eo 'Transaction hash:[[:space:]]*0x[0-9a-fA-F]+' \
  | awk '{print $NF}' \
  | head -n1
)"

# Attendi che la classe sia visibile: receipt OK o class-by-hash OK
wait_until_declared() {
  local tx="$1" hash="$2"
  for i in {1..60}; do
    if [ -n "$tx" ]; then
      if starkli tx-receipt "$tx" 2>/dev/null | grep -q '"execution_status": "SUCCEEDED"'; then
        return 0
      fi
    fi
    if starkli class-by-hash "$hash" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if ! wait_until_declared "$DECLARE_TX" "$CLASS_HASH"; then
  echo "Errore: la declare non è stata confermata/visibile entro il tempo previsto." >&2
  exit 1
fi

echo
echo "Class Hash L2: ${CLASS_HASH}"
echo "Deploy del contratto L2 in corso..."
echo

# Deploy
DEPLOY_OUTPUT="$(starkli deploy "$CLASS_HASH" 2>&1 || true)"
echo "$DEPLOY_OUTPUT"

# Indirizzo dal nuovo output ("Contract deployed:" riga successiva), poi fallback "will be deployed at address"
CONTRACT_ADDRESS="$(
  printf '%s\n' "$DEPLOY_OUTPUT" | awk '
    BEGIN{grab=0}
    /^Contract deployed:$/ {grab=1; next}
    grab && $0 ~ /^0x[0-9a-fA-F]+$/ {print; exit}
  '
)"
[ -z "$CONTRACT_ADDRESS" ] && CONTRACT_ADDRESS="$(
  printf '%s\n' "$DEPLOY_OUTPUT" \
  | sed -n 's/^The contract will be deployed at address[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p' \
  | tail -n1
)"

# Tx del deploy (nuovo e vecchio formato)
DEPLOY_TX="$(
  printf '%s\n' "$DEPLOY_OUTPUT" \
  | sed -n 's/^Contract deployment transaction:[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p' \
  | tail -n1
)"
[ -z "$DEPLOY_TX" ] && DEPLOY_TX="$(
  printf '%s\n' "$DEPLOY_OUTPUT" \
  | sed -n 's/^Transaction hash:[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p' \
  | tail -n1
)"

# Se ho la tx, verifica il receipt; se manca l’address, leggilo dal receipt
if [ -n "$DEPLOY_TX" ]; then
  for i in {1..60}; do
    DEPLOY_RECEIPT="$(starkli tx-receipt "$DEPLOY_TX" 2>/dev/null || true)"
    if printf '%s' "$DEPLOY_RECEIPT" | grep -q '"execution_status": "SUCCEEDED"'; then
      [ -z "$CONTRACT_ADDRESS" ] && CONTRACT_ADDRESS="$(printf '%s' "$DEPLOY_RECEIPT" | jq -r '.contract_address // empty' 2>/dev/null || true)"
      break
    fi
    sleep 1
  done
fi

[ -z "$CONTRACT_ADDRESS" ] && { echo "Errore: impossibile estrarre l'indirizzo del contratto L2."; exit 1; }

# Salva address
printf '%s\n' "$CONTRACT_ADDRESS" > "$ADDRESS_FILE"
echo
echo "Contratto L2 deployato: ${CONTRACT_ADDRESS}"
echo "Indirizzo salvato in ./${ADDRESS_FILE}"

# Aggiorna env nella cartella solidity
SOLIDITY_DIR="../solidity"
FILES_TO_UPDATE=("${SOLIDITY_DIR}/env" "${SOLIDITY_DIR}/anvil.env" "${SOLIDITY_DIR}/.env")

if [[ "${OSTYPE:-}" == "darwin"* ]]; then SED_INPLACE=(sed -i ''); else SED_INPLACE=(sed -i); fi

for file_path in "${FILES_TO_UPDATE[@]}"; do
  if [ -f "$file_path" ]; then
    echo "   - Aggiornamento di ${file_path}..."
    "${SED_INPLACE[@]}" "s|^L2_CONTRACT_ADDRESS=.*|L2_CONTRACT_ADDRESS=${CONTRACT_ADDRESS}|" "$file_path" || true
    if ! grep -q '^L2_CONTRACT_ADDRESS=' "$file_path"; then
      printf "\nL2_CONTRACT_ADDRESS=%s\n" "$CONTRACT_ADDRESS" >> "$file_path"
    fi
    echo "     fatto."
  else
    echo "   - ${file_path} non trovato. Salto."
  fi
done