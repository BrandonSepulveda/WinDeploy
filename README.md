<div align="center">

# WinDeploy

**Reinstala Windows sin USB, sin PXE y sin salir del equipo.**

Crea una partición temporal en el mismo disco, copia allí el ISO de Windows y agrega una entrada al menú de arranque. Reinicias y entras directo al instalador.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white)](#requisitos)
[![Licencia](https://img.shields.io/badge/licencia-GPLv3-green.svg)](LICENSE)

</div>

---

## Para qué sirve

Cuando toca formatear un equipo remoto o no tienes USB a mano:

- **Sin medios externos.** No necesitas USB booteable ni servidor PXE.
- **Remoto.** Preparas el arranque por sesión remota; solo hace falta que alguien reinicie.
- **Desatendido.** Genera un `autounattend.xml` con usuario, contraseña, clave de producto e idioma, y puede omitir las pantallas de configuración final.
- **Reversible.** Un botón quita la partición y limpia el menú de arranque. Si algo falla o cancelas, revierte solo lo que esa ejecución creó.

## Instalación

Abre PowerShell y ejecuta:

```powershell
irm brandonsepulveda.github.io/WinDeployBS | iex
```

O descarga `WinDeployBS.ps1` del [último release](../../releases/latest) y ejecútalo:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\WinDeployBS.ps1
```

El script pide permisos de administrador y se relanza en Windows PowerShell 5.1 si hace falta. Para ver qué haría sin modificar nada, agrega `-DryRun` al ejecutar el archivo.

## Cómo se usa

1. **Elige la unidad** de la que se tomará el espacio (normalmente `C:`).
2. **Selecciona el ISO** de Windows con **Buscar ISO...** o arrastrándolo a la ventana.
3. *(Opcional)* Marca **Automatizar y personalizar la instalación** y completa usuario, contraseña, clave e idioma.
4. Pulsa **Crear arranque de instalación**. Primero se analiza el equipo y se te muestra el plan; nada cambia hasta que confirmes. Puedes **Cancelar** durante la copia.
5. **Reinicia** cuando te lo ofrezca. El instalador abre solo.
6. En el instalador elige la edición y la partición de Windows. No elijas la partición `WinDeployBS`: ahí está el ISO.
7. Terminada la instalación, vuelve a abrir WinDeploy y pulsa **Eliminar arranque y partición**.

> [!IMPORTANT]
> Reinicia, no apagues. Con Fast Startup activo el equipo puede saltarse el menú de arranque; se desactiva con `powercfg /h off`.

> [!IMPORTANT]
> Las versiones recientes de Windows 11 no se instalan en particiones de menos de 52 GB, y la partición de WinDeploy impide volver a agrandar la unidad desde el instalador. Sumando el tamaño del ISO, `C:` debe tener unos **63 GB** antes de empezar. WinDeploy te avisa si no alcanza.

## Requisitos

| | |
|---|---|
| Sistema | Windows 10 / 11, 64 bits |
| PowerShell | 5.1 (incluido en Windows) |
| Permisos | Administrador |
| Espacio libre | Tamaño del ISO + 2 GB reducibles en la unidad elegida (unos 11 GB con Windows 11) |

## Verificaciones previas

Antes de modificar el disco, WinDeploy comprueba:

- Que el ISO tenga los archivos del instalador y coincida con la arquitectura del equipo.
- Espacio **realmente reducible** con `Get-PartitionSupportedSize`, no solo el espacio libre, y qué lo puede estar bloqueando.
- BitLocker, puntos de restauración y estado de salud del disco.
- Sistema de archivos, disco de solo lectura o fuera de línea, y límite de 4 particiones en MBR.
- Restos de una ejecución anterior.
- Que la unidad no quede por debajo del mínimo del instalador, y si el equipo está con batería.

## Solución de problemas

<details>
<summary><b>El equipo no arranca después de instalar</b></summary>

Arranca desde un USB de recuperación y ejecuta:

```cmd
bootrec /rebuildbcd
bootrec /fixboot
```

Luego, desde Windows ya iniciado, abre WinDeploy y usa **Eliminar arranque y partición** para limpiar los restos.
</details>

<details>
<summary><b>"Windows 11 no se puede instalar en el disco 0 partición..."</b></summary>

La partición tiene menos de 52 GB. Usa **Eliminar arranque y partición**, libera o amplía la unidad hasta unos 63 GB y vuelve a crear el arranque.
</details>

<details>
<summary><b>"No hay suficiente espacio" aunque el disco tiene libre</b></summary>

`hiberfil.sys`, el archivo de paginación, la MFT o los puntos de restauración bloquean la reducción. WinDeploy ofrece eliminar los puntos de restauración; la hibernación se quita con `powercfg /h off`. Luego reintenta.
</details>

<details>
<summary><b>Quedó espacio sin asignar después de Eliminar</b></summary>

Si Windows ya se instaló, su partición de recuperación suele quedar entre `C:` y el espacio liberado, y por eso no se puede sumar a `C:`. WinDeploy no toca esa partición. Puedes crear otra unidad con ese espacio en Administración de discos.
</details>

<details>
<summary><b>No aparece el menú de arranque al reiniciar</b></summary>

Fast Startup está activo. Desactívalo con `powercfg /h off` y **reinicia** en lugar de apagar.
</details>

## Registros

Todo queda en `%ProgramData%\WinDeployBS\WinDeployBS_log.txt`: salida completa de `diskpart`, `bcdedit` y `robocopy`. El botón **Ver registro completo** lo abre directamente.

## Cómo funciona

```
┌─────────────┐   shrink    ┌──────────────┐
│  C: Windows │ ──────────► │  C:  │ WinDeploy │  ← partición temporal NTFS
└─────────────┘             └──────────────┘
                                    │
                                    ├─ contenido del ISO (sin efi\ ni bootmgr)
                                    ├─ autounattend.xml
                                    └─ WinDeploy.log  (datos para deshacer)
                                    │
                              ┌─────▼─────┐
                              │    BCD    │  entrada osloader → ramdisk boot.wim
                              └───────────┘
```

El instalador arranca desde `boot.wim` cargado en RAM, así que la partición temporal puede eliminarse después sin afectar al sistema.

La contraseña del `autounattend.xml` queda codificada (no cifrada) hasta el primer inicio de sesión, cuando WinDeploy borra sus copias. Cámbiala después de instalar.

## Advertencia

Este script modifica particiones y el menú de arranque. **Haz respaldo de tus datos antes de usarlo.** Pruébalo en un equipo de laboratorio antes de llevarlo a producción.

## Para quien modifique el script

Guarda `WinDeployBS.ps1` en **UTF-8 sin BOM**. Con BOM, `irm | iex` falla en PowerShell 5.1. Evita la `Ó` mayúscula literal en el código: en Windows-1252 se convierte en una comilla y rompe la sintaxis.

## Licencia

GPLv3. Ver [LICENSE](LICENSE).

---

<div align="center">

Hecho por **[Brandon Sepúlveda](https://brandonsepulveda.github.io)**

</div>
