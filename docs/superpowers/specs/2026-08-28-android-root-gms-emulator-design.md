# Diseño del toolkit Android Root + GMS

## Objetivo

Crear un repositorio Git para Windows que permita montar desde cero un Android Virtual Device con Android 16/API 36, arquitectura x86_64, Google Play Services y root para aplicaciones mediante Magisk. El proceso debe preservar la imagen original de Google, usar siempre cold boot y producir evidencias verificables de `uid=0` desde una aplicación normal.

## Resultado esperado

- AVD neutro llamado `Root_GMS_API_36`.
- Perfil de hardware `pixel_7`, 2 GB de RAM y partición de datos de 10 GB.
- Imagen `google_apis`, no `google_apis_playstore`: contiene GMS/GSF y permite trabajar con una ramdisk modificable.
- Copia aislada de la imagen en `system-images\android-36\google_apis_magisk\x86_64`.
- Magisk 30.7 instalado, con MagiskSU y Zygisk operativos.
- Bridge Magisk montado en `/system_ext/bin/su` para evitar que `/system/xbin/su` oculte MagiskSU a las aplicaciones.
- Lanzador que utiliza `-no-snapshot-load` y `-no-snapshot-save`, resuelve el serial por nombre de AVD y habilita `adb root` solo sobre ese emulador.
- Verificación de GMS, GSF, red, Magisk y root desde una APK temporal cuyo proceso no sea `shell`.

## Restricciones

- Plataforma objetivo: Windows 10/11 y PowerShell 5.1 o superior.
- Android SDK en `%LOCALAPPDATA%\Android\Sdk` o indicado mediante `ANDROID_SDK_ROOT`.
- No se incluirán imágenes del sistema de Google en Git. Se instalarán con `sdkmanager` y se copiarán localmente.
- No se incluirán APK ni archivos descargados. Magisk y rootAVD se descargarán desde sus repositorios oficiales, con versión/commit fijados y SHA-256 comprobado cuando el proveedor publique un artefacto estable.
- Magisk queda fijado a `v30.7`; su APK debe producir SHA-256 `E0D32D2123532860F97123D927B1BB86C4E08E6FD8A48BFC6B5BEE0AFAE9EBD5`.
- rootAVD queda fijado al commit `92df40eafa2f117053f56015e3c32ca706a55fa9` del fork `galihlasahido/rootAVD`, que declara soporte para API 36.
- El procedimiento no sobrescribirá un AVD existente ni borrará imágenes, datos o copias de seguridad salvo que el operador use expresamente `-Force` sobre el nombre exacto.
- Los pasos visuales inevitables de Magisk se documentarán con el texto exacto esperado; los scripts se detendrán y pedirán confirmación antes de continuar.

## Alternativas consideradas

### Scripts por etapas — elegida

Se separan preparación, parche, finalización, lanzamiento y verificación. Es más fácil reanudar después de un reinicio de Magisk, diagnosticar fallos y repetir solo una etapa.

### Script monolítico

Reduciría el número de comandos iniciales, pero combinaría descargas, copia de varios gigabytes, interacción gráfica y reinicios en una ejecución difícil de recuperar.

### Imagen preconstruida dentro del repositorio

Sería más rápida, pero ocuparía varios gigabytes, redistribuiría componentes de Google y ocultaría el proceso de construcción. Queda descartada.

## Estructura prevista

```text
android-root-gms-emulator/
├── README.md
├── LICENSE
├── .gitignore
├── config.psd1
├── Launch-Cold-Boot.cmd
├── Setup.cmd
├── scripts/
│   ├── Common.ps1
│   ├── Setup.ps1
│   ├── Prepare-Avd.ps1
│   ├── Patch-Magisk.ps1
│   ├── Install-SuBridge.ps1
│   ├── Launch-Cold-Boot.ps1
│   ├── Verify-Emulator.ps1
│   ├── Verify-Toolkit.ps1
│   └── Restore-OriginalRamdisk.ps1
├── assets/
│   └── magisk-module/
│       ├── module.prop
│       └── system/system_ext/bin/su
├── tests/
│   └── root-probe/
│       ├── AndroidManifest.xml
│       ├── RootProbeActivity.java
│       └── Build-And-Run.ps1
└── docs/
    ├── troubleshooting.md
    └── superpowers/specs/2026-08-28-android-root-gms-emulator-design.md
```

## Responsabilidades

### Configuración

`config.psd1` será la única fuente de versiones, nombres, URL, hashes y rutas relativas. Los scripts no duplicarán esos valores.

### Funciones compartidas

`Common.ps1` localizará el SDK, validará ejecutables, resolverá el serial exacto de un AVD, esperará el arranque, calculará hashes y ejecutará procesos comprobando su código de salida.

### Preparación

`Prepare-Avd.ps1` instalará o comprobará `platform-tools`, `emulator`, `cmdline-tools` y `system-images;android-36;google_apis;x86_64`. Creará el AVD contra la imagen original, lo arrancará una vez y copiará la imagen a un directorio aislado sin alterar el paquete descargado por Google.

### Parche Magisk

`Patch-Magisk.ps1` descargará el commit fijado de rootAVD y Magisk 30.7 en `.cache`, verificará identidades y hashes, ampliará de forma localizada el tiempo de espera del selector de archivos y ejecutará `rootAVD.bat` con `FAKEBOOTIMG` contra la ramdisk aislada. Antes de modificarla conservará `ramdisk.img.backup` y verificará que el original y la copia coinciden.

El operador seleccionará `fakeboot.img` en Magisk y esperará el mensaje `All done`. El script no asumirá éxito: comprobará que el hash de la ramdisk aislada cambió y que la copia de seguridad conserva el hash original.

### Finalización y bridge de su

Tras cambiar `image.sysdir.1` a la imagen aislada, el AVD arrancará en frío. El operador aceptará `Requires additional setup` en Magisk y esperará el reinicio. `Install-SuBridge.ps1` instalará un módulo Magisk mínimo cuyo ejecutable `/system_ext/bin/su` delega en `/debug_ramdisk/su`. Esto sitúa MagiskSU antes del `su` AOSP restringido a `root:shell`.

### Lanzamiento

`Launch-Cold-Boot.ps1` cerrará solo una instancia activa del AVD objetivo, iniciará `emulator.exe -avd Root_GMS_API_36 -no-snapshot-load -no-snapshot-save`, resolverá su serial consultando `adb emu avd name`, esperará `sys.boot_completed=1` y ejecutará `adb root` sobre ese serial. `Launch-Cold-Boot.cmd` será un wrapper para doble clic.

### Verificación

`Verify-Toolkit.ps1` validará sintaxis PowerShell, archivos requeridos, ausencia de secretos/binarios descargados y coherencia de valores con `config.psd1`.

`Verify-Emulator.ps1` comprobará:

1. Nombre exacto del AVD y arranque completo.
2. `magisk -v` igual a `30.7:MAGISK:R`.
3. `su -v` igual a `30.7:MAGISKSU`.
4. `su -c id` con `uid=0(root)` y contexto `u:r:magisk:s0`.
5. Presencia de `com.google.android.gms` y `com.google.android.gsf`.
6. Resolución y conectividad de red.

La prueba `tests/root-probe` construirá una APK mínima con las herramientas del SDK, ejecutará `ProcessBuilder("su", "-c", "id")`, permitirá conceder el permiso en Magisk y exigirá `exit=0` más `uid=0(root)`. Después desinstalará la APK y retirará sus temporales.

## Seguridad y recuperación

- Toda ruta destructiva se normalizará y deberá permanecer dentro del AVD exacto o de `.cache`.
- Las descargas usarán HTTPS y versiones fijadas.
- La imagen `google_apis` original no se modificará.
- `ramdisk.img.backup` permanecerá junto a la imagen aislada.
- `Restore-OriginalRamdisk.ps1` detendrá solo el AVD objetivo, comprobará rutas y hashes y restaurará la copia tras confirmación explícita.
- `.gitignore` excluirá `.cache`, APK, keystores, logs, clases, DEX y artefactos generados.

## Documentación

El `README.md` estará en español y cubrirá requisitos, espacio en disco, instalación automática, pasos visuales de Magisk, comprobación, cold boot, actualización de versiones, restauración y resolución de fallos. `docs/troubleshooting.md` recogerá los fallos observados: selector de Magisk agotando el tiempo, ADB ambiguo con varios dispositivos, `su` AOSP devolviendo permiso denegado y AVD no reconocido por `avdmanager` al usar una imagen aislada.

## Criterios de aceptación

- Un clon limpio contiene todos los scripts, fuentes, módulo y documentación necesarios; solo requiere descargar dependencias externas declaradas.
- El verificador estático termina con código 0.
- La preparación detecta el AVD actual sin sobrescribirlo y ofrece un modo de comprobación no destructivo.
- El lanzador completa un cold boot real con código 0 aun cuando exista un dispositivo físico conectado por ADB.
- Una app temporal obtiene `uid=0(root)` mediante el diálogo de Magisk.
- GMS y GSF permanecen instalados y hay conectividad.
- No aparece ninguna referencia al proyecto Android de origen en nombres, contenidos ni rutas generadas por el toolkit.
- El repositorio no modifica el proyecto Android desde el que se creó.
