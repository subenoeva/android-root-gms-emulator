# Android Root + GMS Emulator

Toolkit reproducible para crear en Windows un Android Virtual Device con:

- Android 16 / API 36, x86_64.
- Imagen Google APIs con Google Play Services y Google Services Framework.
- Magisk 30.7 y root disponible para aplicaciones.
- Cold boot en cada lanzamiento.
- Imagen original de Google intacta y copia de seguridad de la ramdisk.

No se utiliza una imagen `google_apis_playstore`. Las imágenes con Play Store están firmadas para producción y no permiten privilegios elevados; la variante `google_apis` sí incluye los servicios de Google necesarios, pero no la aplicación Play Store.

## Qué queda fijado

Los valores están centralizados en [`config.psd1`](config.psd1):

| Componente | Valor |
|---|---|
| AVD | `Root_GMS_API_36` |
| Android | API 36 / x86_64 |
| Perfil | Pixel 7 |
| Imagen original | `google_apis` |
| Copia parcheada | `google_apis_magisk` |
| Magisk | 30.7 |
| Android Build Tools | 36.0.0 |
| rootAVD | commit `92df40eafa2f117053f56015e3c32ca706a55fa9` |

El APK de Magisk solo se acepta si su SHA-256 es:

```text
E0D32D2123532860F97123D927B1BB86C4E08E6FD8A48BFC6B5BEE0AFAE9EBD5
```

## Requisitos

- Windows 10 u 11 de 64 bits con virtualización habilitada.
- Android Studio o Android SDK Command-Line Tools.
- Git for Windows, incluido Git Bash, requerido por `rootAVD.bat`.
- JDK 17 o superior. Android Studio incluye un JDK compatible en `jbr`.
- PowerShell 5.1 o superior.
- Al menos 12 GB libres en la unidad del SDK.
- Conexión a Internet durante la preparación.

El SDK se busca en este orden:

1. Parámetro `-SdkPath`.
2. `ANDROID_SDK_ROOT`.
3. `ANDROID_HOME`.
4. `%LOCALAPPDATA%\Android\Sdk`.

## Instalación desde cero

Abre PowerShell en la carpeta del repositorio.

### 1. Comprobar el entorno

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Prepare-Avd.ps1 -CheckOnly
```

Este modo no cambia archivos. Debe localizar `sdkmanager`, `avdmanager`, ADB y el emulador.

### 2. Ejecutar la preparación completa

Si las licencias del SDK ya se aceptaron desde Android Studio:

```powershell
.\Setup.cmd
```

Para aceptar las licencias desde el script:

```powershell
.\Setup.cmd -AcceptLicenses
```

La preparación instala o comprueba estos paquetes:

```text
platform-tools
emulator
platforms;android-36
build-tools;36.0.0
system-images;android-36;google_apis;x86_64
```

Después crea `Root_GMS_API_36` y copia la imagen del sistema:

```text
Original: system-images\android-36\google_apis\x86_64
Copia:    system-images\android-36\google_apis_magisk\x86_64
```

La imagen original no se modifica.

Si ya existe un AVD o una copia aislada con esos nombres, el script se detiene. `-Force` no los borra: los mueve a rutas con sufijo `.pre-toolkit-AAAAmmdd-HHMMSS` antes de crear el entorno nuevo.

### 3. Parchear la ramdisk en Magisk

`Setup.cmd` arranca el AVD original y ejecuta el commit fijado de rootAVD. Magisk se abrirá dentro del emulador.

1. Si aparece la pantalla principal, pulsa `Install` junto a Magisk.
2. Elige `Select and Patch a File`.
3. Abre `Downloads` y selecciona `fakeboot.img`.
4. Pulsa `LET'S GO`.
5. Espera hasta ver `All done`.
6. Vuelve a la terminal y pulsa Intro antes de que termine la espera de 300 segundos.

El script solo continúa si se cumplen las tres condiciones:

- Existe `ramdisk.img.backup`.
- Su hash coincide con la ramdisk anterior al parche.
- El hash de la ramdisk activa ha cambiado.

Después cambia `image.sysdir.1` para que el AVD use la copia aislada.

### 4. Completar la instalación de Magisk

El AVD se iniciará otra vez mediante cold boot y se abrirá Magisk.

1. Acepta `Requires additional setup`.
2. Permite que Magisk reinicie el emulador.
3. Espera a que la pantalla principal muestre `Installed 30.7`.
4. Vuelve a la terminal y pulsa Intro.

### 5. Instalar el bridge de `su`

El setup ejecuta automáticamente:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-SuBridge.ps1
```

Si Magisk pregunta por acceso de superusuario para `Shell`, selecciona `Grant`.

La imagen Google APIs contiene `/system/xbin/su`, pero ese binario está restringido a `root:shell` y puede ocultar MagiskSU a las aplicaciones. El módulo incluido monta `/system_ext/bin/su`, que delega en:

```sh
/debug_ramdisk/su
```

Tras el reinicio, `command -v su` debe devolver `/system_ext/bin/su`.

## Verificación

### Comprobar el repositorio

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Toolkit.ps1
```

Valida sintaxis, contratos, finales de línea del módulo, ausencia de binarios descargados en Git y limpieza de la autoría de los commits.

### Comprobar el emulador

Con el AVD iniciado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Emulator.ps1
```

Comprueba:

- `sys.boot_completed=1`.
- Nombre exacto del AVD.
- Magisk `30.7:MAGISK:R`.
- MagiskSU `30.7:MAGISKSU`.
- `su -c id` con `uid=0(root)` y contexto `u:r:magisk:s0`.
- APK de Google Play Services.
- APK de Google Services Framework.
- Conectividad de red.

### Demostrar root desde una aplicación

La comprobación anterior usa el UID de `shell`. Para demostrar que una aplicación normal puede obtener root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\root-probe\Build-And-Run.ps1
```

El script compila y firma una APK temporal sin Gradle, la instala y abre. Concede la solicitud en Magisk. Si no aparece un diálogo, entra en `Magisk > Superuser`, habilita `Root Probe`, vuelve a abrir la sonda y pulsa Intro en la terminal. La prueba exige:

```text
exit=0
uid=0(root)
```

También comprueba que el paquete se ejecutaba con un UID Android de aplicación, igual o superior a 10000. Al terminar desinstala la APK y elimina sus artefactos. Usa `-KeepArtifacts` únicamente si necesitas inspeccionarlos.

## Lanzamiento con cold boot

Haz doble clic en:

```text
Launch-Cold-Boot.cmd
```

O ejecútalo desde PowerShell:

```powershell
.\Launch-Cold-Boot.cmd
```

El lanzador:

1. Detiene solo una instancia activa de `Root_GMS_API_36`.
2. Ejecuta el emulador con `-no-snapshot-load -no-snapshot-save`.
3. Resuelve el serial consultando el nombre del AVD, aunque haya un teléfono físico conectado.
4. Espera el arranque completo.
5. Habilita `adb root` sobre ese serial concreto.
6. Verifica MagiskSU.

No usa `adb -e`, por lo que no queda ambiguo cuando ADB detecta varios dispositivos.

## Restaurar la ramdisk original

Cierra el AVD y ejecuta:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-OriginalRamdisk.ps1 -Confirm
```

El script conserva primero otra copia de la ramdisk parcheada y luego restaura `ramdisk.img.backup`. Comprueba los hashes antes de terminar.

Esto elimina Magisk de la ramdisk aislada. No modifica la imagen original descargada por `sdkmanager`.

## Actualizar Magisk o rootAVD

No sustituyas archivos descargados manualmente dentro de `.cache`.

1. Cambia versión, URL y hash en `config.psd1`.
2. Cambia el commit y la URL fijada de rootAVD si procede.
3. Revisa si el bloque de timeout de `rootAVD.sh` sigue siendo idéntico.
4. Ejecuta las verificaciones estáticas.
5. Prepara un AVD nuevo o restaura la ramdisk antes de volver a parchear.
6. Usa `-RefreshDownloads` para reconstruir la caché:

```powershell
.\Setup.cmd -RefreshDownloads
```

El script se detendrá si el hash de Magisk no coincide o si el código fijado de rootAVD ya no contiene el bloque revisado.

## Archivos principales

| Archivo | Responsabilidad |
|---|---|
| `config.psd1` | Versiones, nombres, URL y hashes |
| `Setup.cmd` | Entrada para la instalación completa |
| `scripts/Prepare-Avd.ps1` | SDK, AVD y copia aislada |
| `scripts/Patch-Magisk.ps1` | Descarga verificada y parche rootAVD |
| `scripts/Install-SuBridge.ps1` | Módulo que expone MagiskSU a aplicaciones |
| `Launch-Cold-Boot.cmd` | Lanzamiento diario con cold boot |
| `scripts/Verify-Emulator.ps1` | Verificación runtime |
| `tests/root-probe/Build-And-Run.ps1` | Verificación desde UID de aplicación |
| `scripts/Restore-OriginalRamdisk.ps1` | Recuperación reversible |
| `docs/troubleshooting.md` | Diagnóstico de errores conocidos |

## Fuentes

- [Crear y administrar AVD](https://developer.android.com/studio/run/managing-avds)
- [Iniciar el emulador desde línea de comandos](https://developer.android.com/studio/run/emulator-commandline)
- [avdmanager](https://developer.android.com/tools/avdmanager)
- [Magisk](https://github.com/topjohnwu/Magisk)
- [rootAVD](https://github.com/galihlasahido/rootAVD)

Magisk y rootAVD conservan sus propias licencias y condiciones. Este repositorio no redistribuye sus artefactos ni las imágenes de Google.
