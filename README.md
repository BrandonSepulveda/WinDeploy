<div align="center">
  <img src="https://raw.githubusercontent.com/BrandonSepulveda/ToolboxBS/main/logos/windeploy-logo.png" alt="WinDeploy Logo" width="400">
  
  # 🚀 WinDeploy  
  **La Revolución en la Instalación de Windows**  

  [![Versión](https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge)](https://github.com/BrandonSepulveda/ToolboxBS)
  [![Descargas](https://img.shields.io/github/downloads/BrandonSepulveda/ToolboxBS/total?style=for-the-badge)](https://github.com/BrandonSepulveda/ToolboxBS/releases)
  [![Lenguaje Principal](https://img.shields.io/github/languages/top/BrandonSepulveda/ToolboxBS?style=for-the-badge)](https://github.com/BrandonSepulveda/ToolboxBS)
  [![Licencia](https://img.shields.io/github/license/BrandonSepulveda/ToolboxBS?style=for-the-badge)](https://github.com/BrandonSepulveda/ToolboxBS/blob/main/LICENSE)
  [![Estado](https://img.shields.io/badge/STATUS-ACTIVO-success?style=for-the-badge)](https://github.com/BrandonSepulveda/ToolboxBS)
</div>

---

## 📜 Descripción General

**WinDeploy** es un script de **PowerShell** con una interfaz gráfica intuitiva que **automatiza por completo** el proceso de instalación de Windows.

En lugar de depender de **USBs** o herramientas complicadas, **WinDeploy** utiliza una porción de tu disco duro para preparar e iniciar la instalación sin necesidad de medios externos.

---

## ⚡ Ejecución Rápida

Abre **PowerShell como Administrador** y ejecuta:

```powershell
irm https://raw.githubusercontent.com/BrandonSepulveda/ToolboxBS/refs/heads/main/procesos/WinDeploy.ps1 | iex
```

✨ Características Principales
🎯 Interfaz de Usuario Intuitiva

Diseño elegante y fácil de usar que te guía en cada paso.

Selección simple de disco y archivo ISO.

Botones claros para crear o deshacer la partición de arranque.

🤖 Automatización Completa

Reducción de Partición: Calcula el espacio necesario y reduce tu partición principal de forma segura.

Creación y Formato: Genera una nueva partición NTFS lista para la instalación.

Copia de Archivos: Monta el ISO y transfiere los archivos automáticamente.

Configuración del BCD: Crea y configura la entrada de arranque para iniciar el instalador en el próximo reinicio.
