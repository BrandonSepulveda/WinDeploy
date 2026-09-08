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
- **Desatendido.** Genera un `autounattend.xml` con usuario, contraseña, idioma, zona horaria y nombre de equipo.
- **Reversible.** Un botón devuelve el espacio al disco y limpia el menú de arranque.

## Instalación

Abre PowerShell **como administrador** y ejecuta:

```powershell
irm brandonsepulveda.github.io/WinDeployBS | iex
```

O descarga `WinDeployBS.ps1` del [último release](../../releases/latest) y ejecútalo:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\WinDeployBS.ps1
```

El script se eleva solo y se relanza en Windows PowerShell 5.1 si hace falta.

## Cómo se usa

1. **Elige la partición** de la que se tomará el espacio (normalmente `C:`).
2. **Selecciona el ISO** de Windows. Se verifica su integridad antes de tocar el disco.
3. *(Opcional)* Marca **instalación desatendida** y completa usuario, contraseña, idioma y nombre de equipo.
4. Pulsa **Crear Arranque** y espera. El progreso se muestra paso a paso.
5. **Reinicia** con el botón de la ventana y elige *WinDeploy* en el menú de arranque.
6. Terminada la instalación, vuelve a abrir WinDeploy y pulsa **Eliminar Arranque y Partición**.

> [!IMPORTANT]
> Reinicia, no apagues. Con Fast Startup activo el equipo puede saltarse el menú de arranque. El script ofrece desactivarlo por ti.

## Requisitos

| | |
|---|---|
| Sistema | Windows 10 / 11, 64 bits |
| PowerShell | 5.1 (incluido en Windows) |
| Permisos | Administrador |
| Espacio libre | 12 GB reducibles en la partición elegida |
| RAM | 4 GB o más |

## Verificaciones previas

Antes de modificar el disco, WinDeploy comprueba y avisa:

- Integridad del ISO: `setup.exe`, `boot.wim`, `boot.sdi`, `install.wim`/`install.esd` y sus tamaños.
- Espacio **realmente reducible** con `Get-PartitionSupportedSize`, no solo el espacio libre.
- BitLocker, instantáneas VSS y estado SMART del disco.
- Firmware UEFI o Legacy y coherencia con el esquema GPT/MBR.
- Reinicio pendiente de Windows Update, RAM disponible y si el equipo está con batería.

## Solución de problemas

<details>
<summary><b>El equipo no arranca después de instalar</b></summary>

Arranca desde un USB de recuperación y ejecuta:

```cmd
bootrec /rebuildbcd
bootrec /fixboot
```

Luego, desde Windows ya iniciado, abre WinDeploy y usa **Eliminar Arranque y Partición** para limpiar los restos.
</details>

<details>
<summary><b>"No hay suficiente espacio" aunque el disco tiene libre</b></summary>

`hiberfil.sys`, el archivo de paginación, la MFT o las instantáneas de VSS bloquean la reducción. Marca la casilla **Desactivar hibernación**, desactiva Protección del Sistema y reintenta.
</details>

<details>
<summary><b>No aparece el menú de arranque al reiniciar</b></summary>

Fast Startup está activo. Desactívalo con `powercfg /h off` o usa la casilla del script, y **reinicia** en lugar de apagar.
</details>

<details>
<summary><b>La ventana no abre o los acentos se ven mal</b></summary>

El archivo se corrompió al descargarlo. Bájalo del release en `.zip` y verifica el tamaño antes de ejecutarlo.
</details>

## Registros

Todo queda en `%ProgramData%\WinDeployBS\WinDeployBS.log`: salida completa de `diskpart`, `bcdedit` y `robocopy`. También se copia a la partición de instalación. El botón **Ver log** lo abre directamente.

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

## Advertencia

Este script modifica particiones y el menú de arranque. **Haz respaldo de tus datos antes de usarlo.** Pruébalo en un equipo de laboratorio antes de llevarlo a producción.

## Licencia

GPLv3. Ver [LICENSE](LICENSE).

---

<div align="center">

Hecho por **[Brandon Sepúlveda](https://brandonsepulveda.github.io)**

</div>
