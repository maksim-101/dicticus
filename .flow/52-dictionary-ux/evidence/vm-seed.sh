#!/bin/zsh
# Slice 52 task 4: build the branch in the mac-space VM, seed an invented dictionary and three
# invented dictations, launch the app. "readback" prints the guest dictionary for the final check.
# Usage: vm-seed.sh seed | readback. Runs on the host; the VM must already be up and free.
set -euo pipefail
VM="$HOME/code/agent-vm/vm"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
export AGENT_VM=mac-space
BID=com.dicticus.app
APP='~/code/dicticus/macOS/build/Build/Products/Release/Dicticus.app'
DB='~/Library/Application\ Support/com.dicticus.app/Database/History.sqlite'

# Invented words only (public repo). createdAt is seconds since 2001-01-01, JSONEncoder's default.
DICT_JSON='{
 "kwib ly":{"replacement":"Quibbly","createdAt":784800000,"source":"user"},
 "quibli":{"replacement":"Quibbly","createdAt":784800100,"source":"user"},
 "Kwiblee":{"replacement":"Quibbly","createdAt":784800200,"source":"imported"},
 "cloud":{"replacement":"Zornex","createdAt":784800300,"source":"user"},
 "zorn ex":{"replacement":"Zornex","createdAt":784800400,"source":"user"},
 "flor dex":{"replacement":"FlorDex","createdAt":784800500,"source":"imported"},
 "floor decks":{"replacement":"FlorDex","createdAt":784800600,"source":"imported"},
 "flawdex":{"replacement":"FlorDex","createdAt":784800700,"source":"imported"},
 "flor-dex":{"replacement":"FlorDex","createdAt":784800800,"source":"imported"},
 "florr dex":{"replacement":"FlorDex","createdAt":784800900,"source":"imported"},
 "vantel":{"replacement":"Vantelli","createdAt":784801000,"source":"default"},
 "mirra cove":{"replacement":"Miracove","createdAt":784801100,"source":"user"}
}'

case "${1:-}" in
seed)
  "$VM" sync "$REPO"
  "$VM" ssh "cd ~/code/dicticus/macOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build 2>&1 | tail -1"
  # The history database exists only after the History tab was opened once in the app
  # (first run: skip the onboarding, open the menu bar popover, click History). Quit before seeding.
  "$VM" ssh "pkill -x Dicticus; sleep 3; true"
  HEX=$(printf '%s' "$DICT_JSON" | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin),separators=(",",":")).encode().hex())')
  "$VM" ssh "defaults write $BID customDictionaryMetadata -data $HEX"
  "$VM" ssh "sqlite3 $DB \"DELETE FROM transcriptionEntry;
    INSERT INTO transcriptionEntry(uuid,text,rawText,language,mode,createdAt,confidence) VALUES
    ('52-a','Can you check whether mirror cove imports the timeline from the FlorDex export correctly?','can you check whether mirror cove imports the timeline from the flor dex export correctly?','en','aiCleanup',datetime('now','-5 minutes'),0.9),
    ('52-b','Send the Zornex logs to the dev channel before lunch.','send the cloud logs to the dev channel before lunch.','en','plain',datetime('now','-20 minutes'),0.9),
    ('52-c','Ich schicke dir die Rechnung von Vantelli heute Abend noch.','ich schicke dir die Rechnung von vantel heute Abend noch.','de','plain',datetime('now','-3 hours'),0.9);\""
  "$VM" ssh "open $APP"
  echo "seeded: 12 fixture entries, 3 fixture dictations"
  ;;
readback)
  "$VM" ssh "defaults export $BID - | plutil -extract customDictionaryMetadata raw -o - - | base64 -d" \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print("entries",len(d));[print(k,"->",v["replacement"]) for k,v in sorted(d.items())]'
  ;;
*) echo "usage: $0 seed|readback" >&2; exit 2 ;;
esac
