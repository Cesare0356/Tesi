#!/bin/bash
set -euo pipefail

# Config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOLIDITY_DIR="${SCRIPT_DIR}"
REPO_ROOT="$(cd "${SOLIDITY_DIR}/.." && pwd)"
ANVIL_MSG_JSON="${REPO_ROOT}/anvil.messaging.json"
CAIRO_DIR="${REPO_ROOT}/cairo"
CAIRO_CONTRACT_FILE="${CAIRO_DIR}/contract_msg_address.txt"

FILES_TO_UPDATE=(
  "${SOLIDITY_DIR}/.env"
  "${SOLIDITY_DIR}/env"
  "${SOLIDITY_DIR}/anvil.env"
)

ETH_RPC_URL_DEFAULT="http://127.0.0.1:8545"
if [[ -z "${ETH_RPC_URL:-}" ]]; then
  if [[ -f "${SOLIDITY_DIR}/.env" ]] && grep -Eq '^ETH_RPC_URL=' "${SOLIDITY_DIR}/.env"; then
    source "${SOLIDITY_DIR}/.env"
  elif [[ -f "${SOLIDITY_DIR}/env" ]] && grep -Eq '^ETH_RPC_URL=' "${SOLIDITY_DIR}/env"; then
    source "${SOLIDITY_DIR}/env"
  elif [[ -f "${SOLIDITY_DIR}/anvil.env" ]] && grep -Eq '^ETH_RPC_URL=' "${SOLIDITY_DIR}/anvil.env"; then
    source "${SOLIDITY_DIR}/anvil.env"
  fi
  ETH_RPC_URL="${ETH_RPC_URL:-$ETH_RPC_URL_DEFAULT}"
fi


# sed portabile
sed_inplace() {
  local pattern="$1"
  local file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i -E "$pattern" "$file"
  else
    sed -i '' -E "$pattern" "$file"
  fi
}

# aggiorna/aggiunge chiave=valore
upsert_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  if [[ ! -f "$file" ]]; then return 0; fi
  if grep -Eq "^[[:space:]]*${key}=" "$file"; then
    sed_inplace "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$file"
  else
    printf "\n%s=%s\n" "$key" "$value" >> "$file"
  fi
}

# 1) forge script
FORGE_OUT="$(
  forge script script/LocalTesting.s.sol:LocalSetup --broadcast --rpc-url "${ETH_RPC_URL}" 2>&1
)"
echo "$FORGE_OUT"

# 2) Estrai i due Contract Address
ADDRS_FROM_OUT="$(printf "%s\n" "$FORGE_OUT" | sed -n 's/^Contract Address:[[:space:]]*\(0x[0-9a-fA-F]\+\)$/\1/p')"

first_addr=""
second_addr=""
i=0
while read line; do
  [ -z "$line" ] && continue
  i=$((i+1))
  if [ $i -eq 1 ]; then
    first_addr="$line"
  elif [ $i -eq 2 ]; then
    second_addr="$line"
    break
  fi
done <<EOF
$ADDRS_FROM_OUT
EOF

if [ -z "$first_addr" ] || [ -z "$second_addr" ]; then
  LATEST_JSON="$(printf "%s\n" "$FORGE_OUT" | sed -n 's/^Transactions saved to:[[:space:]]*\(.*run-latest\.json\)$/\1/p' | tail -n1)"
  if [ -z "$LATEST_JSON" ]; then
    CAND="${SOLIDITY_DIR}/broadcast/LocalTesting.s.sol/1/run-latest.json"
    [ -f "$CAND" ] && LATEST_JSON="$CAND" || true
  fi
  if [ -n "$LATEST_JSON" ] && [ -f "$LATEST_JSON" ]; then
    ADDRS_FROM_JSON="$(grep -Eo '"contractAddress":[[:space:]]*"0x[0-9a-fA-F]+"' "$LATEST_JSON" | grep -Eo '0x[0-9a-fA-F]+')"
    first_addr=""
    second_addr=""
    i=0
    while read line; do
      [ -z "$line" ] && continue
      i=$((i+1))
      if [ $i -eq 1 ]; then
        first_addr="$line"
      elif [ $i -eq 2 ]; then
        second_addr="$line"
        break
      fi
    done <<EOF
$ADDRS_FROM_JSON
EOF
  fi
fi

if [ -z "$first_addr" ] || [ -z "$second_addr" ]; then
  echo "Errore: non ho trovato due Contract Address." >&2
  exit 1
fi

SN_MESSAGING_ADDRESS="$first_addr"
CONTRACT_MSG_ADDRESS="$second_addr"

echo "SN_MESSAGING_ADDRESS=${SN_MESSAGING_ADDRESS}"
echo "CONTRACT_MSG_ADDRESS=${CONTRACT_MSG_ADDRESS}"

# 3) aggiorna .env / env / anvil.env
for file in "${FILES_TO_UPDATE[@]}"; do
  if [[ -f "$file" ]]; then
    upsert_kv "$file" "SN_MESSAGING_ADDRESS" "$SN_MESSAGING_ADDRESS"
    upsert_kv "$file" "CONTRACT_MSG_ADDRESS" "$CONTRACT_MSG_ADDRESS"
  fi
done

# 4) aggiorna anvil.messaging.json
BLOCK_NUM="$(cast block-number --rpc-url "${ETH_RPC_URL}")"
if ! [[ "$BLOCK_NUM" =~ ^[0-9]+$ ]]; then
  echo "Errore: impossibile leggere il block-number da ${ETH_RPC_URL}. Output: ${BLOCK_NUM}" >&2
  exit 1
fi

if [[ ! -f "${ANVIL_MSG_JSON}" ]]; then
  cat > "${ANVIL_MSG_JSON}" <<EOF
{
  "chain": "ethereum",
  "rpc_url": "${ETH_RPC_URL}",
  "contract_address": "${SN_MESSAGING_ADDRESS}",
  "sender_address": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  "private_key": "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  "interval": 2,
  "from_block": ${BLOCK_NUM}
}
EOF
else
  sed_inplace "s|\"rpc_url\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"rpc_url\": \"${ETH_RPC_URL}\"|" "${ANVIL_MSG_JSON}"
  sed_inplace "s|\"contract_address\"[[:space:]]*:[[:space:]]*\"0x[0-9a-fA-F]+\"|\"contract_address\": \"${SN_MESSAGING_ADDRESS}\"|" "${ANVIL_MSG_JSON}"
  sed_inplace "s|\"from_block\"[[:space:]]*:[[:space:]]*[0-9]+|\"from_block\": ${BLOCK_NUM}|" "${ANVIL_MSG_JSON}"
fi

# 5) salva anche in ../cairo/contract_msg_address.txt
mkdir -p "${CAIRO_DIR}"
echo "${CONTRACT_MSG_ADDRESS}" > "${CAIRO_CONTRACT_FILE}"

echo "Fatto."
echo "Aggiornato: ${FILES_TO_UPDATE[*]} e ${ANVIL_MSG_JSON}"
echo "Salvato CONTRACT_MSG_ADDRESS anche in ${CAIRO_CONTRACT_FILE}"