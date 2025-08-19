#!/bin/bash
set -e

CONTRACT_NAME="messaging_tuto_contract_msg"
COMPILER_VERSION="2.8.5"
ADDRESS_FILE="deployment_address.txt"

echo "Inizio deploy del contratto L2..."
source katana.env

scarb build

CLASS_FILE_PATH="./target/dev/${CONTRACT_NAME}.contract_class.json"

DECLARE_OUTPUT=$(starkli declare "$CLASS_FILE_PATH" --compiler-version "$COMPILER_VERSION" 2>&1 || true)
echo "$DECLARE_OUTPUT"

CLASS_HASH=$(printf "%s\n" "$DECLARE_OUTPUT" | sed -n 's/^Class hash:[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p' | head -n1)
if [ -z "$CLASS_HASH" ]; then
  CLASS_HASH=$(printf "%s\n" "$DECLARE_OUTPUT" | grep -Eo '0x[0-9a-fA-F]{64}' | head -n1)
fi
if [ -z "$CLASS_HASH" ]; then
  echo "Errore: impossibile estrarre CLASS_HASH." >&2
  exit 1
fi

DECLARE_TX=$(printf "%s\n" "$DECLARE_OUTPUT" | sed -n 's/^Transaction hash:[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p' | head -n1)
if [ -n "$DECLARE_TX" ]; then
  echo "Attendo conferma della declare: $DECLARE_TX"
  for i in {1..60}; do
    RECEIPT=$(starkli tx-receipt "$DECLARE_TX" 2>&1 || true)
    if echo "$RECEIPT" | grep -q '"execution_status": "SUCCEEDED"'; then
      echo "Declare confermata"
      break
    fi
    sleep 1
    [ "$i" -eq 60 ] && echo "Declare non ancora confermata: proseguo comunque" || true
  done
else
  echo "Nessuna transaction hash per la declare: la classe potrebbe essere già dichiarata"
fi

echo
echo "Class Hash L2: ${CLASS_HASH}"
echo "Deploy del contratto L2 in corso..."
echo

DEPLOY_OUTPUT=$(starkli deploy "$CLASS_HASH" 2>&1)
echo "$DEPLOY_OUTPUT"

CONTRACT_ADDRESS=$(printf "%s\n" "$DEPLOY_OUTPUT" | grep -Eo '0x[0-9a-fA-F]{64}' | tail -n1)
if [ -z "$CONTRACT_ADDRESS" ]; then
  CONTRACT_ADDRESS=$(printf "%s\n" "$DEPLOY_OUTPUT" | sed -n 's/^The contract will be deployed at address[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p' | tail -n1)
fi
if [ -z "$CONTRACT_ADDRESS" ]; then
  echo "Errore: impossibile estrarre l'indirizzo del contratto L2 dall'output del deploy." >&2
  exit 1
fi

echo
echo "${CONTRACT_ADDRESS}" > "${ADDRESS_FILE}"
echo "Contratto L2 deployato: ${CONTRACT_ADDRESS}"
echo "Indirizzo salvato in ./${ADDRESS_FILE}"

echo
echo "Aggiornamento dei file .env nella cartella solidity..."

SOLIDITY_DIR="../solidity"
ENV_FILE="${SOLIDITY_DIR}/env"
ANVIL_ENV_FILE="${SOLIDITY_DIR}/anvil.env"
FILES_TO_UPDATE=("$ENV_FILE" "$ANVIL_ENV_FILE")

for file_path in "${FILES_TO_UPDATE[@]}"; do
  if [ -f "$file_path" ]; then
    echo "   - Aggiornamento di ${file_path}..."
    # Aggiorna la riga se esiste; se non esiste, la aggiunge in coda.
    sed -i '' "s|^L2_CONTRACT_ADDRESS=.*|L2_CONTRACT_ADDRESS=${CONTRACT_ADDRESS}|" "$file_path" || true
    if ! grep -q '^L2_CONTRACT_ADDRESS=' "$file_path"; then
      printf "\nL2_CONTRACT_ADDRESS=%s\n" "$CONTRACT_ADDRESS" >> "$file_path"
    fi
    echo "     fatto."
  else
    echo "   - ${file_path} non trovato. Salto."
  fi
done