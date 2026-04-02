# GitHub Setup Instructions

Para subir esta versión mejorada de Present a tu GitHub, sigue estos pasos:

## 1. Crear un Fork (si aún no lo has hecho)

Ve a https://github.com/simonw/present y haz click en "Fork"

O simplemente crea un nuevo repositorio en tu GitHub con el nombre "present"

## 2. Clonar tu repositorio local

Si aún no has hecho git init en este directorio:

```bash
cd ~/Documents/GitHub/present
git init
git config user.name "Tu Nombre"
git config user.email "tu@email.com"
```

## 3. Agregar el remote de GitHub

```bash
git remote add origin https://github.com/JLMirallesB/present.git
```

## 4. Agregar todos los cambios

```bash
git add .
```

## 5. Hacer el primer commit

```bash
git commit -m "Enhanced fork with display names, multiple presentation lists, and improved navigation

- Add custom display names for slides
- Multiple presentation lists management
- Safe editing modal for slides
- Improved keyboard navigation (Cmd+↑/↓)
- Better organization and persistence"
```

## 6. Hacer push a GitHub

```bash
git branch -M main
git push -u origin main
```

## 7. Crear un Release en GitHub

```bash
# Crear el tag
git tag -a v1.0 -m "Release v1.0 - Enhanced fork with new features"

# Push el tag
git push origin v1.0

# Crear el release en GitHub
gh release create v1.0 \
  --title "Present 1.0 - Enhanced Fork" \
  --notes-file RELEASE_NOTES.md \
  Present-1.0.dmg
```

O manualmente en GitHub:
1. Ve a tu repositorio
2. Click en "Releases" (en la columna derecha)
3. Click en "Create a new release"
4. Tag: `v1.0`
5. Title: `Present 1.0 - Enhanced Fork`
6. Description: Copia el contenido de RELEASE_NOTES.md
7. Adjunta el archivo `Present-1.0.dmg`
8. Click en "Publish release"

## 8. Actualizar la descripción del repositorio

En los settings del repositorio en GitHub:
- **Description**: "A macOS SwiftUI app for presentations with display names, multiple lists, and improved navigation. Enhanced fork of simonw/present"
- **Website**: (opcional, tu sitio web)
- **Topics**: macOS, presentations, swift, swiftui, app

## Archivos incluidos

- `Present-1.0.dmg` - Instalador listo para distribuir
- `README.md` - Actualizado con nuevas funciones
- `RELEASE_NOTES.md` - Notas detalladas de la versión
- `icon_present.png` - Icono de la app
- Código fuente mejorado

## Después del Release

1. Usuarios pueden descargar el DMG desde la página de releases
2. Los cambios estarán disponibles en el repositorio
3. Se recomienda agregar un badge al README:

```markdown
![Release](https://img.shields.io/badge/Release-v1.0-blue)
![macOS](https://img.shields.io/badge/macOS-14.0+-brightgreen)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange)
```

## Notas importantes

- El usuario deberá abrir la app con Right-Click > Open la primera vez (no está firmada)
- Los datos de presentaciones se almacenan localmente
- Es un fork del original: https://github.com/simonw/present

¡Listo para compartir!
