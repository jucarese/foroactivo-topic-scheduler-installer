#!/usr/bin/env sh
cd "$(dirname "$0")" || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js no está instalado."
  exit 1
fi

if [ ! -d node_modules ]; then
  npm install || exit 1
fi

npm run asistente
