#!/bin/bash


# Interrompe l'esecuzione in caso di errore
set -e

# --- CONFIGURAZIONE ---
CONTRACT_NAME="messaging_tuto_contract_msg"
COMPILER_VERSION="2.8.5"
ADDRESS_FILE="deployment_address.txt"

# --- DEPLOY CONTRATTO STARKNET (L2) ---

echo "▶️  Inizio deploy del contratto L2..."

source katana.env

scarb build

CLASS_FILE_PATH="./target/dev/${CONTRACT_NAME}.contract_class.json"
DECLARE_OUTPUT=$(starkli declare "$CLASS_FILE_PATH" --compiler-version "$COMPILER_VERSION" || true)
CLASS_HASH=$(echo "$DECLARE_OUTPUT" | tail -n 1)
echo
echo "Class Hash L2: ${CLASS_HASH}"
echo "Deploy del contratto L2 in corso..."
echo
DEPLOY_OUTPUT=$(starkli deploy "$CLASS_HASH" 2>&1)
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "The contract will be deployed at address" | awk '{print $NF}')

echo

if [ -z "$CONTRACT_ADDRESS" ]; then
    echo "Errore: Impossibile estrarre l'indirizzo del contratto L2 dall'output del deploy." >&2
    exit 1
fi

echo "${CONTRACT_ADDRESS}" > "${ADDRESS_FILE}"
echo "✅ Contratto L2 deployato: ${CONTRACT_ADDRESS}"
echo "✅ Indirizzo salvato in ./cairo/${ADDRESS_FILE}"

# --- AGGIORNAMENTO FILE .ENV (L1) ---

echo "▶️  Aggiornamento dei file .env nella cartella solidity..."

SOLIDITY_DIR="../solidity"
ENV_FILE="${SOLIDITY_DIR}/env"
ANVIL_ENV_FILE="${SOLIDITY_DIR}/anvil.env"
FILES_TO_UPDATE=("$ENV_FILE" "$ANVIL_ENV_FILE")

for file_path in "${FILES_TO_UPDATE[@]}"; do
    if [ -f "$file_path" ]; then
        echo "   - Aggiornamento di ${file_path}..."
        sed -i '' "s|^L2_CONTRACT_ADDRESS=.*|L2_CONTRACT_ADDRESS=${CONTRACT_ADDRESS}|" "$file_path"
        echo "     ...fatto."
    else
        # Se il file non esiste, stampa un avviso ma non fermare lo script
        echo "⚠️  Attenzione: il file ${file_path} non è stato trovato. Salto l'aggiornamento."
    fi
done


