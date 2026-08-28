# Resolución de problemas

## `Permission denied` al ejecutar `su`

Comprueba qué binario se está resolviendo:

```powershell
adb -s emulator-5554 shell command -v su
adb -s emulator-5554 shell su -v
```

El resultado esperado es:

```text
/system_ext/bin/su
30.7:MAGISKSU
```

Si aparece `/system/xbin/su`, el binario AOSP está ocultando MagiskSU. Reinstala el bridge:

```powershell
.\scripts\Install-SuBridge.ps1
```

## Magisk no concede root a la APK de prueba

Abre Magisk, entra en `Superuser` y comprueba que `Root Probe` está permitido. La respuesta automática recomendada es `Prompt`, para que cada aplicación requiera una decisión explícita.

Si se denegó una solicitud anterior, desinstala la APK y vuelve a ejecutar:

```powershell
.\tests\root-probe\Build-And-Run.ps1
```

## ADB indica que hay más de un emulador

No uses `adb -e`. Lista los dispositivos:

```powershell
adb devices -l
```

El toolkit consulta `adb -s SERIAL emu avd name` y solo utiliza el serial cuyo nombre sea `Root_GMS_API_36`. Si dos instancias informan el mismo nombre, detén ambas antes de continuar.

## rootAVD termina antes de completar el selector de Magisk

El commit fijado espera 60 segundos de origen. `Patch-Magisk.ps1` cambia únicamente ese bloque a 300 segundos y verifica que el texto sea el revisado.

Si el script rechaza el bloque:

1. Elimina solo `.cache\tools\rootAVD-COMMIT` o usa `-RefreshDownloads`.
2. Comprueba que `config.psd1` mantiene el commit soportado.
3. No apliques una sustitución manual sobre una versión distinta sin revisar el código.

## No aparece `fakeboot.img`

En el selector de Android abre el menú lateral, entra en `Downloads` y selecciona:

```text
/sdcard/Download/fakeboot.img
```

Si no existe, rootAVD no llegó a crear el boot temporal. Revisa que el AVD esté iniciado contra la imagen original y que Git Bash y ADB estén disponibles.

## Magisk muestra `Requires additional setup` repetidamente

Acepta el diálogo y espera a que el reinicio termine por completo. No cierres el emulador durante el proceso. Después abre Magisk y confirma:

```text
Installed 30.7
Ramdisk Yes
Zygisk Yes
```

Si sigue apareciendo, restaura la ramdisk aislada y repite el parche desde una copia limpia.

## `avdmanager` dice que falta `google_apis_magisk`

Es esperado después del parche. `google_apis_magisk` es una copia local aislada y no un paquete registrado en el catálogo de `sdkmanager`.

El emulador puede iniciarla porque `config.ini` contiene una ruta directa. Usa `Launch-Cold-Boot.cmd` para arrancarla y `Prepare-Avd.ps1 -CheckOnly` para inspeccionarla.

## El AVD no arranca después del parche

1. Cierra todos los procesos del emulador objetivo.
2. Comprueba que existen `ramdisk.img` y `ramdisk.img.backup` en la imagen aislada.
3. Restaura con:

```powershell
.\scripts\Restore-OriginalRamdisk.ps1 -Confirm
```

4. Inicia de nuevo con `Launch-Cold-Boot.cmd`.

La restauración conserva una copia timestamped de la ramdisk parcheada.

## Falla el hash de Magisk

No continúes. El fichero descargado no es el artefacto fijado.

Elimina la caché mediante:

```powershell
.\Setup.cmd -RefreshDownloads
```

Si vuelve a fallar, contrasta la release oficial y actualiza conscientemente versión, URL y SHA-256 en `config.psd1`.

## No aparecen Google Play Services

Ejecuta:

```powershell
adb -s emulator-5554 shell pm path com.google.android.gms
adb -s emulator-5554 shell pm path com.google.android.gsf
```

Ambos comandos deben devolver una ruta `package:`. Si no lo hacen, se creó el AVD con una imagen AOSP en lugar de `google_apis`.

## El launcher carga un snapshot

No debe ocurrir. Comprueba que `scripts\Launch-Cold-Boot.ps1` conserve ambos argumentos:

```text
-no-snapshot-load
-no-snapshot-save
```

El primero fuerza un arranque completo y el segundo impide guardar un snapshot nuevo al cerrar.

## PowerShell no encuentra `Import-PowerShellDataFile`

`Common.ps1` carga explícitamente `Microsoft.PowerShell.Utility` desde `$PSHOME`. Esto evita que Windows PowerShell herede por error una instalación del módulo destinada a PowerShell 7.

Ejecuta siempre los wrappers o usa:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Toolkit.ps1
```
