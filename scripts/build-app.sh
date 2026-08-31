#!/usr/bin/env bash
#
# Construye Present.app en Release y la deja en la raíz del repositorio,
# lista para abrir con doble clic desde el Finder.
#
# La app resultante está en .gitignore: es un artefacto local, no se versiona.
#
#   ./scripts/build-app.sh          construye y actualiza ./Present.app
#   ./scripts/build-app.sh --open   además la abre al terminar
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Xcode se queja por stderr de que CoreSimulator está desactualizado. Es una
# incidencia del entorno, irrelevante para una app solo de macOS: la filtramos
# para no enterrar los errores que sí importan.
SIM_NOISE="CoreSimulator|SimServiceContext|DVTErrorPresenter|IDERunDestination|Unable to load simulator|^Domain:|^Code:|^Failure Reason:|^Recovery Suggestion:|^--$|^$"

echo "==> Compilando Present (Release)…"
xcodebuild -project Present.xcodeproj -scheme Present -configuration Release \
  -destination "generic/platform=macOS" build SYMROOT=build \
  2> >(grep -vE "$SIM_NOISE" >&2) \
  | grep -E "\.swift.*(error|warning):|^\*\* BUILD" || true

if [ ! -d "build/Release/Present.app" ]; then
  echo "!! La compilación no ha producido build/Release/Present.app" >&2
  exit 1
fi

echo "==> Actualizando ./Present.app"
rm -rf Present.app
cp -R build/Release/Present.app Present.app
# La app se compila aquí mismo, así que no debería tener cuarentena; por si acaso.
xattr -dr com.apple.quarantine Present.app 2>/dev/null || true
touch Present.app

echo "==> Listo: $(pwd)/Present.app"

if [ "${1:-}" = "--open" ]; then
  open Present.app
fi
