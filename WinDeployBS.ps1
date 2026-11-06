<#
.SYNOPSIS
    Crea una partición de arranque a partir de un archivo ISO para instalar Windows, con opciones avanzadas de automatización.

.DESCRIPTION
    Reduce una partición, copia la ISO de Windows en una partición nueva y agrega una entrada
    de arranque (BCD) para iniciar el instalador. Antes de tocar el disco ejecuta un análisis
    previo; si algo falla a mitad del proceso, revierte solo lo que esta misma ejecución creó.

.PARAMETER DryRun
    Modo simulación: analiza el equipo y muestra lo que haría, sin modificar discos ni BCD.

.PARAMETER IsoPath
    Ruta de una ISO para dejarla ya seleccionada al abrir la ventana.

.NOTES
    Autor: Brandon Sepulveda
    Version: 11.4
    Requiere: Windows PowerShell 5.1, ejecutándose como Administrador.
    IMPORTANTE: guardar este archivo como UTF-8 SIN BOM. Con BOM falla al instalarlo con
    "irm | iex" en PowerShell 5.1. El arranque detecta los acentos dañados y se relanza bien.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$IsoPath, [switch]$TempCopy)

$script:AppVersion = '11.4'
$script:ReleaseUrl = 'https://github.com/BrandonSepulveda/WinDeploy/releases/latest/download/WinDeployBS.ps1'

#region --- Arranque: administrador, 64 bits, Windows PowerShell en STA, texto bien decodificado ---
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$needsAdmin = (-not $script:IsAdmin) -and (-not $DryRun)
$wrongHost = ($PSVersionTable.PSEdition -eq 'Core') -or
             ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') -or
             ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess)
$hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$isCompiled = (Split-Path -Leaf $hostExe) -notin 'powershell.exe', 'pwsh.exe', 'powershell_ise.exe'

if ($isCompiled) {
    # Compilado como .exe (ps2exe o similar)
    if ($needsAdmin) {
        try { Start-Process -FilePath $hostExe -Verb RunAs -ErrorAction Stop }
        catch { Write-Host "No se pudo reiniciar con los permisos necesarios: $($_.Exception.Message)" -ForegroundColor Red }
        exit
    }
} elseif (-not $TempCopy) {
    # Por "irm | iex" no hay archivo para relanzarse, y sin BOM PowerShell 5.1 daña los acentos.
    # Esta letra mide 1 solo si el texto se leyó bien; en ese caso se guarda una copia correcta y se abre esa.
    $badText = 'ó'.Length -ne 1
    if ((-not $PSCommandPath) -or $badText -or $needsAdmin -or $wrongHost) {
        try {
            $launchPath = $PSCommandPath
            $extraArgs = ''
            if ((-not $PSCommandPath) -or $badText) {
                if ($PSCommandPath) {
                    $data = [IO.File]::ReadAllBytes($PSCommandPath)
                } else {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                    $web = New-Object Net.WebClient
                    try { $data = $web.DownloadData($script:ReleaseUrl) } finally { $web.Dispose() }
                }
                $skip = if ($data.Length -ge 3 -and $data[0] -eq 0xEF -and $data[1] -eq 0xBB -and $data[2] -eq 0xBF) { 3 } else { 0 }
                $launchPath = Join-Path $env:TEMP ("WinDeployBS_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
                $stream = [IO.File]::Create($launchPath)
                try {
                    $stream.Write([byte[]](0xEF, 0xBB, 0xBF), 0, 3)
                    $stream.Write($data, $skip, $data.Length - $skip)
                } finally { $stream.Dispose() }
                $extraArgs = ' -TempCopy'
            }
            $psDir = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
            $argLine = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$launchPath`"$extraArgs"
            if ($DryRun) { $argLine += ' -DryRun' }
            if ($IsoPath) { $argLine += " -IsoPath `"$IsoPath`"" }
            $startArgs = @{ FilePath = (Join-Path $env:SystemRoot "$psDir\WindowsPowerShell\v1.0\powershell.exe"); ArgumentList = $argLine; ErrorAction = 'Stop' }
            if ($needsAdmin) { $startArgs.Verb = 'RunAs' }
            Start-Process @startArgs
        } catch {
            Write-Host "No se pudo abrir WinDeploy: $($_.Exception.Message)" -ForegroundColor Red
        }
        # Con "return" y no "exit": bajo iex, exit cerraría la consola del usuario.
        return
    }
}
#endregion

#region --- GUI Definition (XAML) ---
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinDeploy Ultimate by: Brandon Sepulveda" Height="760" Width="1020" MinHeight="640" MinWidth="880"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize" AllowDrop="True"
        Background="#FF0B1220" Foreground="#FFF3F4F6" FontFamily="Segoe UI" FontSize="13">
    <Window.Resources>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#FF3B82F6"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="White"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#FF3B82F6"/>

        <Style TargetType="{x:Type Button}">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#FF374151"/>
            <Setter Property="Margin" Value="0"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Button}">
                        <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#FF93C5FD"/>
                                <Setter TargetName="ButtonBorder" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="#FF1F2937"/>
                                <Setter Property="Foreground" Value="#FF6B7280"/>
                                <Setter Property="Cursor" Value="No"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="Card" TargetType="{x:Type Border}">
            <Setter Property="Background" Value="#FF111827"/>
            <Setter Property="BorderBrush" Value="#FF1F2937"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="14,12"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style x:Key="CardTitle" TargetType="{x:Type TextBlock}">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#FFF3F4F6"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>
        <Style x:Key="Tile" TargetType="{x:Type Border}">
            <Setter Property="Background" Value="#FF1F2937"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="10,8"/>
        </Style>
        <Style x:Key="TileLabel" TargetType="{x:Type TextBlock}">
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Foreground" Value="#FF9CA3AF"/>
        </Style>
        <Style x:Key="TileValue" TargetType="{x:Type TextBlock}">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#FF9CA3AF"/>
            <Setter Property="Margin" Value="0,3,0,0"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>
        <Style TargetType="{x:Type TextBox}">
            <Setter Property="Background" Value="#FF1F2937"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="BorderBrush" Value="#FF374151"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Validation.ErrorTemplate" Value="{x:Null}"/>
        </Style>
        <Style TargetType="{x:Type PasswordBox}">
            <Setter Property="Background" Value="#FF1F2937"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="BorderBrush" Value="#FF374151"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style TargetType="{x:Type ComboBox}">
            <Setter Property="Foreground" Value="Black"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style TargetType="{x:Type ComboBoxItem}">
            <Setter Property="Foreground" Value="Black"/>
            <Style.Triggers>
                <Trigger Property="IsHighlighted" Value="True">
                    <Setter Property="Foreground" Value="White"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="{x:Type CheckBox}">
            <Setter Property="Foreground" Value="#FFE5E7EB"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style TargetType="{x:Type ToolTip}">
            <Setter Property="Background" Value="#FF1F2937"/>
            <Setter Property="Foreground" Value="White"/>
        </Style>
    </Window.Resources>

    <Grid Margin="18,14,18,14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Encabezado -->
        <Grid Grid.Row="0" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock x:Name="HeaderTextBlock" Text="WinDeploy Ultimate" FontSize="22" FontWeight="Bold"/>
                <TextBlock Text="Crea una partición de arranque para formatear e instalar Windows, sin USB." Foreground="#FF9CA3AF"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
                <Border x:Name="ModeBadge" Background="#FF78350F" CornerRadius="6" Padding="10,4" Margin="0,0,8,0" Visibility="Collapsed">
                    <TextBlock Text="SIMULACI&#211;N" FontSize="11" FontWeight="Bold" Foreground="#FFFDE68A"/>
                </Border>
                <Border Background="#FF1F2937" CornerRadius="6" Padding="10,4">
                    <TextBlock x:Name="VersionTextBlock" FontSize="11" Foreground="#FF9CA3AF"/>
                </Border>
            </StackPanel>
        </Grid>

        <!-- Contenido en dos columnas -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Columna izquierda: pasos -->
            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto">
                <StackPanel>
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <TextBlock Style="{StaticResource CardTitle}" Text="1. Unidad a reducir"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <ComboBox x:Name="DiskComboBox" Height="36"/>
                                <Button x:Name="RefreshButton" Grid.Column="1" Content="Actualizar" Height="36" Margin="8,0,0,0" ToolTip="Volver a buscar unidades"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <TextBlock Style="{StaticResource CardTitle}" Text="2. ISO de Windows"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="IsoPathTextBox" Height="36" IsReadOnly="True" AllowDrop="True" ToolTip="También puedes arrastrar la ISO a la ventana"/>
                                <Button x:Name="SelectIsoButton" Grid.Column="1" Content="Buscar ISO..." Height="36" Margin="8,0,0,0" Background="#FF2563EB"/>
                            </Grid>
                            <TextBlock x:Name="IsoInfoTextBlock" Text="Selecciónala o arrástrala a esta ventana." Foreground="#FF9CA3AF" FontSize="12" Margin="2,6,0,0" TextWrapping="Wrap"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <TextBlock Style="{StaticResource CardTitle}" Text="3. Opciones"/>
                            <CheckBox x:Name="AutomateInstallCheckBox" Content="Automatizar y personalizar la instalación"/>
                            <Grid x:Name="AutomationDetailsPanel" Visibility="Collapsed" Margin="0,10,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <TextBlock Text="Usuario" Grid.Row="0" VerticalAlignment="Center" Margin="0,0,12,6"/>
                                <TextBox x:Name="txtUsername" Grid.Row="0" Grid.Column="1" Margin="0,0,0,6" Text="Usuario"/>
                                <TextBlock Text="Contraseña" Grid.Row="1" VerticalAlignment="Center" Margin="0,0,12,6"/>
                                <PasswordBox x:Name="pwdPassword" Grid.Row="1" Grid.Column="1" Margin="0,0,0,6"/>
                                <TextBlock Text="Clave (opcional)" Grid.Row="2" VerticalAlignment="Center" Margin="0,0,12,6"/>
                                <TextBox x:Name="txtProductKey" Grid.Row="2" Grid.Column="1" Margin="0,0,0,6"/>
                                <TextBlock Text="Idioma y región" Grid.Row="3" VerticalAlignment="Center" Margin="0,0,12,6"/>
                                <ComboBox x:Name="cmb_Locale" Grid.Row="3" Grid.Column="1" Margin="0,0,0,6"/>
                                <CheckBox x:Name="chk_BypassTPM" Content="Omitir revisión de TPM 2.0 y CPU" Grid.Row="4" Grid.ColumnSpan="2" Margin="0,4,0,0" IsChecked="True"/>
                                <CheckBox x:Name="chk_BypassSecureBoot" Content="Omitir revisión de Secure Boot" Grid.Row="5" Grid.ColumnSpan="2" Margin="0,5,0,0" IsChecked="True"/>
                                <CheckBox x:Name="chk_SkipWifi" Content="Omitir configuración de Wi-Fi" Grid.Row="6" Grid.ColumnSpan="2" Margin="0,5,0,0" IsChecked="True"/>
                                <CheckBox x:Name="chk_SkipPostInstallOOBE" Content="Omitir configuración final (OOBE) e ir al escritorio" Grid.Row="7" Grid.ColumnSpan="2" Margin="0,5,0,0" IsChecked="True"/>
                            </Grid>
                            <TextBlock x:Name="AutomationWarningTextBlock" Margin="0,10,0,0" Foreground="#FFFBBF24" FontSize="12" TextWrapping="Wrap" Visibility="Collapsed"
                                       Text="Aún deberás elegir el disco de instalación a mano. La contraseña queda codificada (no cifrada) en el disco hasta el primer inicio de sesión, cuando se borra sola; cámbiala después de instalar."/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </ScrollViewer>

            <!-- Columna derecha: diagnóstico y actividad -->
            <Grid Grid.Column="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Style="{StaticResource CardTitle}" Text="Diagnóstico"/>
                        <UniformGrid Columns="2" Rows="2">
                            <Border Style="{StaticResource Tile}" Margin="0,0,4,4">
                                <StackPanel>
                                    <TextBlock Style="{StaticResource TileLabel}" Text="BitLocker"/>
                                    <TextBlock x:Name="DiagBitlocker" Style="{StaticResource TileValue}" Text="-"/>
                                </StackPanel>
                            </Border>
                            <Border Style="{StaticResource Tile}" Margin="4,0,0,4">
                                <StackPanel>
                                    <TextBlock Style="{StaticResource TileLabel}" Text="Puntos de restauración"/>
                                    <TextBlock x:Name="DiagVSS" Style="{StaticResource TileValue}" Text="-"/>
                                </StackPanel>
                            </Border>
                            <Border Style="{StaticResource Tile}" Margin="0,4,4,0">
                                <StackPanel>
                                    <TextBlock Style="{StaticResource TileLabel}" Text="Salud del disco"/>
                                    <TextBlock x:Name="DiagSysDisk" Style="{StaticResource TileValue}" Text="-"/>
                                </StackPanel>
                            </Border>
                            <Border Style="{StaticResource Tile}" Margin="4,4,0,0">
                                <StackPanel>
                                    <TextBlock Style="{StaticResource TileLabel}" Text="Firmware y disco"/>
                                    <TextBlock x:Name="DiagFirmware" Style="{StaticResource TileValue}" Text="-"/>
                                </StackPanel>
                            </Border>
                        </UniformGrid>
                    </StackPanel>
                </Border>

                <Border Grid.Row="1" Style="{StaticResource Card}" Margin="0">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0" Margin="0,0,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock x:Name="StatusTextBlock" Text="Listo. Esperando instrucciones." FontWeight="SemiBold" TextWrapping="Wrap"/>
                            <TextBlock x:Name="PercentTextBlock" Grid.Column="1" Margin="10,0,0,0" Foreground="#FF93C5FD" FontWeight="Bold"/>
                        </Grid>
                        <ProgressBar x:Name="ProgressBar" Grid.Row="1" Height="8" Foreground="#FF3B82F6" Background="#FF1F2937" BorderThickness="0" Margin="0,0,0,10"/>
                        <TextBox x:Name="LogTextBox" Grid.Row="2" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top"
                                 FontFamily="Consolas" FontSize="12" Background="#FF0B1220" Foreground="#FFD1D5DB" BorderThickness="0" MinHeight="120"/>
                        <Button x:Name="OpenLogButton" Grid.Row="3" Content="Ver registro completo" Height="30" FontSize="12" HorizontalAlignment="Right" Margin="0,8,0,0"/>
                    </Grid>
                </Border>
            </Grid>
        </Grid>

        <!-- Acciones -->
        <Grid Grid.Row="2" Margin="0,12,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="CreateButton" Content="Crear arranque de instalación" Height="44" FontSize="15" Background="#FF2563EB"/>
            <Button x:Name="CancelButton" Grid.Column="1" Content="Cancelar" Height="44" Margin="10,0,0,0" Background="#FFB91C1C" Visibility="Collapsed"
                    ToolTip="Detiene el proceso y revierte los cambios"/>
            <Button x:Name="UndoButton" Grid.Column="2" Content="Eliminar arranque y partición" Height="44" Margin="10,0,0,0"/>
        </Grid>
    </Grid>
</Window>
'@
#endregion

#region --- Trabajo en segundo plano (corre en otro runspace; nunca toca la ventana) ---
$script:WorkerScript = {
    param([string]$Operation, [hashtable]$Options, [hashtable]$Sync)

    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    function Write-Log {
        param([string]$Message)
        if (-not $Options.LogFile) { return }
        try {
            $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
            Add-Content -Path $Options.LogFile -Value $line -Encoding UTF8
        } catch { }
    }

    function Set-Status {
        param([string]$Text, [int]$Percent = -1)
        if ($Sync.Cancel) { throw 'Cancelado por el usuario.' }
        $Sync.Status = $Text
        $Sync.Percent = $Percent
        if ($null -ne $Sync.Log) { $Sync.Log.Enqueue($Text) }
        Write-Log $Text
    }

    function Get-NativeTool {
        param([string]$Name)
        if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
            $sysnative = Join-Path $env:SystemRoot "Sysnative\$Name"
            if (Test-Path $sysnative) { return $sysnative }
        }
        return (Join-Path $env:SystemRoot "System32\$Name")
    }

    # Ejecuta un programa capturando su salida. Lee antes de esperar para no bloquearse.
    function Invoke-Native {
        param([string]$FilePath, [string]$Arguments, [scriptblock]$OnTick, [int]$TimeoutMinutes = 60, [switch]$Cancellable)
        $oem = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = $oem
        $psi.StandardErrorEncoding = $oem
        $nativeProcess = [Diagnostics.Process]::Start($psi)
        try {
            $stdoutTask = $nativeProcess.StandardOutput.ReadToEndAsync()
            $stderrTask = $nativeProcess.StandardError.ReadToEndAsync()
            $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
            while (-not $nativeProcess.WaitForExit(500)) {
                if ($OnTick) { & $OnTick }
                # Solo la copia se puede interrumpir: cortar DiskPart a medio camino sería peligroso.
                if ($Cancellable -and $Sync.Cancel) {
                    $nativeProcess.Kill()
                    throw 'Cancelado por el usuario.'
                }
                if ((Get-Date) -gt $deadline) {
                    $nativeProcess.Kill()
                    throw "$([IO.Path]::GetFileName($FilePath)) superó el tiempo límite de $TimeoutMinutes minutos."
                }
            }
            $nativeProcess.WaitForExit()
            return [pscustomobject]@{
                ExitCode = $nativeProcess.ExitCode
                Output   = (($stdoutTask.Result, $stderrTask.Result) -join "`n").Trim()
            }
        } finally {
            $nativeProcess.Dispose()
        }
    }

    function Get-LastLines {
        param([string]$Text, [int]$Count = 6)
        $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim() })
        return (($lines | Select-Object -Last $Count) -join "`n")
    }

    # Copia un archivo grande contando los bytes escritos. Robocopy reserva el tamaño
    # completo al empezar, así que el espacio ocupado no sirve para medir su avance.
    function Copy-LargeFile {
        param([string]$Source, [string]$Destination, [scriptblock]$OnProgress)
        $buffer = New-Object byte[] (8MB)
        $reader = New-Object IO.FileStream($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 1MB, [IO.FileOptions]::SequentialScan)
        try {
            $writer = New-Object IO.FileStream($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 1MB, [IO.FileOptions]::SequentialScan)
            try {
                $writer.SetLength($reader.Length)
                $done = [int64]0
                $lastTick = [Environment]::TickCount
                while (($read = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $writer.Write($buffer, 0, $read)
                    $done += $read
                    if ([Environment]::TickCount - $lastTick -ge 500) {
                        $lastTick = [Environment]::TickCount
                        if ($Sync.Cancel) { throw 'Cancelado por el usuario.' }
                        if ($OnProgress) { & $OnProgress $done }
                    }
                }
                $writer.Flush($true)
            } finally { $writer.Dispose() }
        } finally { $reader.Dispose() }
        return $done
    }

    function Format-Speed {
        param([int64]$Bytes, [double]$Seconds)
        if ($Seconds -lt 0.5) { $Seconds = 0.5 }
        return ('{0:N2} GB en {1:N0} s ({2:N0} MB/s)' -f ($Bytes / 1GB), $Seconds, ($Bytes / 1MB / $Seconds))
    }

    function Invoke-DiskPart {
        param([string[]]$Commands, [string]$Description)
        $scriptFile = [IO.Path]::GetTempFileName()
        try {
            [IO.File]::WriteAllText($scriptFile, (($Commands + 'exit') -join "`r`n"), [Text.Encoding]::ASCII)
            Write-Log "DiskPart ($Description): $($Commands -join ' | ')"
            $run = Invoke-Native -FilePath (Get-NativeTool 'diskpart.exe') -Arguments "/s `"$scriptFile`""
            Write-Log "DiskPart código=$($run.ExitCode) salida:`n$($run.Output)"
            if ($run.ExitCode -ne 0) {
                throw "DiskPart falló al $Description (código $($run.ExitCode)).`n$(Get-LastLines $run.Output)"
            }
            return $run.Output
        } finally {
            Remove-Item $scriptFile -Force -ErrorAction SilentlyContinue
        }
    }

    function Invoke-BcdEdit {
        param([string]$Arguments)
        $run = Invoke-Native -FilePath (Get-NativeTool 'bcdedit.exe') -Arguments $Arguments -TimeoutMinutes 2
        Write-Log "bcdedit $Arguments -> código $($run.ExitCode)"
        if ($run.ExitCode -ne 0) { throw "bcdedit falló ($Arguments): $(Get-LastLines $run.Output)" }
        return $run.Output
    }

    # Reúne TODAS las letras ocupadas: discos, DVD, USB, SUBST y unidades de red.
    function Get-UsedDriveLetters {
        $used = @{}
        foreach ($drive in [IO.DriveInfo]::GetDrives()) { $used[$drive.Name.Substring(0, 1).ToUpper()] = $true }
        try { foreach ($volume in @(Get-Volume)) { if ($volume.DriveLetter) { $used[([string]$volume.DriveLetter).ToUpper()] = $true } } } catch { }
        try { foreach ($psDrive in @(Get-PSDrive -PSProvider FileSystem)) { if ($psDrive.Name.Length -eq 1) { $used[$psDrive.Name.ToUpper()] = $true } } } catch { }
        try { foreach ($mapped in @(Get-ChildItem 'HKCU:\Network' -ErrorAction Stop)) { if ($mapped.PSChildName.Length -eq 1) { $used[$mapped.PSChildName.ToUpper()] = $true } } } catch { }
        return @($used.Keys)
    }

    function Get-FreeDriveLetter {
        param([string[]]$UsedLetters = (Get-UsedDriveLetters))
        foreach ($code in 68..90) {
            $candidate = [string][char]$code
            if ($UsedLetters -notcontains $candidate) { return $candidate }
        }
        throw 'No hay letras de unidad disponibles (D: a Z: están ocupadas).'
    }

    function Get-BitLockerState {
        param([string]$DriveLetter)
        try {
            $volume = Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='${DriveLetter}:'" -ErrorAction Stop
        } catch {
            if ("$($_.Exception.NativeErrorCode)" -eq 'InvalidNamespace') { return 'Inactivo' }
            return 'Desconocido'
        }
        if (-not $volume) { return 'Inactivo' }
        if ($volume.ProtectionStatus -eq 1) { return 'Activo' }
        if ($volume.ProtectionStatus -eq 2) { return 'Desconocido' }
        # ProtectionStatus 0 significa "sin protección": descifrado o suspendido. Hay que distinguirlos.
        try {
            $conversion = (Invoke-CimMethod -InputObject $volume -MethodName GetConversionStatus -ErrorAction Stop).ConversionStatus
        } catch { return 'Desconocido' }
        switch ([int]$conversion) {
            0 { return 'Inactivo' }
            1 { return 'Suspendido' }
            default { return 'EnProceso' }
        }
    }

    function Get-ShadowCopyCount {
        param([string]$DriveLetter)
        try {
            $volume = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='${DriveLetter}:'" -ErrorAction Stop
            return @(Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop | Where-Object { $_.VolumeName -eq $volume.DeviceID }).Count
        } catch { return -1 }
    }

    function Get-DiskHealth {
        param([int]$DiskNumber)
        try {
            $physical = Get-PhysicalDisk -ErrorAction Stop | Where-Object { "$($_.DeviceId)" -eq "$DiskNumber" } | Select-Object -First 1
            if (-not $physical) { return 'Desconocido' }
            switch ("$($physical.HealthStatus)") {
                { $_ -in 'Healthy', '0' }   { return 'Saludable' }
                { $_ -in 'Warning', '1' }   { return 'Advertencia' }
                { $_ -in 'Unhealthy', '2' } { return 'Fallo' }
                default                     { return 'Desconocido' }
            }
        } catch { return 'Desconocido' }
    }

    function Test-IsUefi {
        if ($env:firmware_type) { return ($env:firmware_type -eq 'UEFI') }
        try { return ((Invoke-BcdEdit '/enum {current}') -match '\.efi') } catch { }
        return (Test-Path 'HKLM:\System\CurrentControlSet\Control\SecureBoot\State')
    }

    function Mount-Iso {
        param([string]$Path)
        $alreadyMounted = [bool](Get-DiskImage -ImagePath $Path -ErrorAction Stop).Attached
        if (-not $alreadyMounted) { Mount-DiskImage -ImagePath $Path -StorageType ISO -ErrorAction Stop | Out-Null }
        $isoLetter = $null
        foreach ($attempt in 1..10) {
            $isoLetter = (Get-DiskImage -ImagePath $Path | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
            if ($isoLetter) { break }
            Start-Sleep -Seconds 1
        }
        if (-not $isoLetter) {
            if (-not $alreadyMounted) { Dismount-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue | Out-Null }
            throw 'La ISO se montó, pero Windows no le asignó una letra de unidad.'
        }
        return @{ Letter = [string]$isoLetter; AlreadyMounted = $alreadyMounted; Path = $Path }
    }

    function Dismount-Iso {
        param($Mount)
        if ($Mount -and -not $Mount.AlreadyMounted) {
            Dismount-DiskImage -ImagePath $Mount.Path -ErrorAction SilentlyContinue | Out-Null
        }
    }

    function Get-InstallImagePath {
        param([string]$Root)
        foreach ($name in 'install.wim', 'install.esd', 'install.swm') {
            $candidate = Join-Path $Root "sources\$name"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
        return $null
    }

    function Get-IsoLayoutProblems {
        param([string]$Root)
        $problems = @()
        foreach ($required in 'sources\boot.wim', 'boot\boot.sdi') {
            if (-not (Test-Path -LiteralPath (Join-Path $Root $required))) { $problems += $required }
        }
        if (-not (Get-InstallImagePath $Root)) { $problems += 'sources\install.wim/.esd/.swm' }
        return $problems
    }

    # 0=x86, 9=x64, 12=ARM64 en Get-WindowsImage; devuelve el nombre que usa autounattend.
    function ConvertTo-UnattendArch {
        param($Architecture)
        switch ("$Architecture") {
            { $_ -in '0', 'x86' }   { return 'x86' }
            { $_ -in '9', 'x64' }   { return 'amd64' }
            { $_ -in '12', 'arm64' } { return 'arm64' }
            default                 { return $null }
        }
    }

    function Get-HostArch {
        $raw = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        switch ($raw) { 'AMD64' { return 'amd64' } 'ARM64' { return 'arm64' } default { return 'x86' } }
    }

    function Get-IsoImageInfo {
        param([string]$Root)
        $info = @{ Languages = @(); Arch = $null }
        try {
            $bootImage = Get-WindowsImage -ImagePath (Join-Path $Root 'sources\boot.wim') -Index 1 -ErrorAction Stop
            $info.Arch = ConvertTo-UnattendArch $bootImage.Architecture
        } catch { Write-Log "No se pudo leer boot.wim: $($_.Exception.Message)" }
        try {
            $installImage = Get-WindowsImage -ImagePath (Get-InstallImagePath $Root) -Index 1 -ErrorAction Stop
            $info.Languages = @($installImage.Languages)
        } catch { Write-Log "No se pudo leer la imagen de instalación: $($_.Exception.Message)" }
        return $info
    }

    # El instalador falla si UILanguage no existe en la ISO: se usa un idioma que sí exista.
    function Resolve-UiLanguage {
        param([string]$Locale, [string[]]$IsoLanguages)
        if (-not $IsoLanguages -or $IsoLanguages -contains $Locale) { return $Locale }
        return $IsoLanguages[0]
    }

    function New-UnattendXml {
        param([hashtable]$Settings)
        $esc = { param($value) [Security.SecurityElement]::Escape([string]$value) }
        $arch = if ($Settings.Arch) { $Settings.Arch } else { 'amd64' }
        $locale = & $esc $Settings.Locale
        $uiLanguage = & $esc $(if ($Settings.UiLanguage) { $Settings.UiLanguage } else { $Settings.Locale })
        $componentAttrs = "processorArchitecture=`"$arch`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`" xmlns:wcm=`"http://schemas.microsoft.com/WMIConfig/2002/State`" xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`""

        $labConfig = @()
        if ($Settings.BypassTPM) { $labConfig += 'BypassTPMCheck', 'BypassCPUCheck' }
        if ($Settings.BypassSecureBoot) { $labConfig += 'BypassSecureBootCheck' }

        # Un bloque RunSynchronous vacío puede invalidar el archivo: solo se escribe si hay comandos.
        $runSynchronous = ''
        if ($labConfig.Count -gt 0) {
            $order = 0
            $commands = foreach ($valueName in $labConfig) {
                $order++
                "                <RunSynchronousCommand wcm:action=`"add`"><Order>$order</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v $valueName /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>"
            }
            $runSynchronous = "            <RunSynchronous>`r`n$($commands -join "`r`n")`r`n            </RunSynchronous>"
        }

        $productKey = & $esc $Settings.ProductKey
        $hideWireless = if ($Settings.SkipWifi) { '<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>' } else { '' }

        $oobePass = ''
        if ($Settings.SkipOobe) {
            $user = & $esc $Settings.Username
            # Formato de Windows para no dejar la contraseña legible (se codifica, no es cifrado).
            $pass = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes([string]$Settings.Password + 'Password'))
            # Al primer inicio de sesión se borran las copias del archivo que quedan en el disco.
            $label = if ($Settings.PartitionLabel) { [string]$Settings.PartitionLabel } else { 'WinDeployBS' }
            $cleanupScript = 'Get-Volume | Where-Object { $_.FileSystemLabel -eq ''' + $label + ''' -and $_.DriveLetter } | ForEach-Object { Remove-Item -LiteralPath ($_.DriveLetter + '':\autounattend.xml'') -Force -ErrorAction SilentlyContinue }'
            $cleanupCommand = & $esc ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' + $cleanupScript + '"')
            $oobePass = @"
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" $componentAttrs>
            <InputLocale>$locale</InputLocale>
            <SystemLocale>$locale</SystemLocale>
            <UILanguage>$uiLanguage</UILanguage>
            <UserLocale>$locale</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" $componentAttrs>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>cmd.exe /c del /f /q "%WINDIR%\Panther\unattend-original.xml"</CommandLine>
                    <Description>Borrar copia de la respuesta desatendida</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <CommandLine>$cleanupCommand</CommandLine>
                    <Description>Borrar autounattend de la particion de instalacion</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                $hideWireless
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Password>
                            <Value>$pass</Value>
                            <PlainText>false</PlainText>
                        </Password>
                        <Description>Cuenta de Administrador Local</Description>
                        <DisplayName>$user</DisplayName>
                        <Group>Administrators</Group>
                        <Name>$user</Name>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
        </component>
    </settings>
"@
        } elseif ($Settings.SkipWifi) {
            $oobePass = @"
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" $componentAttrs>
            <OOBE>
                $hideWireless
            </OOBE>
        </component>
    </settings>
"@
        }

        $xmlText = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" $componentAttrs>
            <SetupUILanguage>
                <UILanguage>$uiLanguage</UILanguage>
            </SetupUILanguage>
            <InputLocale>$locale</InputLocale>
            <SystemLocale>$locale</SystemLocale>
            <UILanguage>$uiLanguage</UILanguage>
            <UserLocale>$locale</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" $componentAttrs>
            <UserData>
                <AcceptEula>true</AcceptEula>
                <ProductKey>
                    <Key>$productKey</Key>
                </ProductKey>
            </UserData>
            <ImageInstall>
                <OSImage>
                    <WillShowUI>OnError</WillShowUI>
                </OSImage>
            </ImageInstall>
            <DiskConfiguration>
                <WillShowUI>Always</WillShowUI>
            </DiskConfiguration>
$runSynchronous
        </component>
    </settings>
$oobePass
</unattend>
"@
        [void][xml]$xmlText   # Falla aquí, y no en el instalador, si el XML quedó mal formado.
        return $xmlText
    }

    # Localiza las entradas por su descripción; sirve aunque falte el archivo de registro.
    function Get-WinDeployBcdIdsFromText {
        param([string]$BcdText)
        $ids = @()
        foreach ($block in ($BcdText -split '(\r?\n){2,}')) {
            if ($block -match '(?m)\s(WinDeployBS|WinDeploy)\s*$' -and $block -match '\{[0-9a-fA-F-]{36}\}') {
                $ids += $Matches[0]
            }
        }
        return @($ids | Select-Object -Unique)
    }

    function Remove-BcdEntries {
        param([string[]]$Ids)
        foreach ($id in @($Ids | Where-Object { $_ })) {
            try { [void](Invoke-BcdEdit "/delete $id /f") } catch { Write-Log "No se pudo borrar $id : $($_.Exception.Message)" }
        }
    }

    function Update-StorageView {
        try { Update-HostStorageCache -ErrorAction SilentlyContinue } catch { }
    }

    function Remove-PartitionSafe {
        param([int]$DiskNumber, [int]$PartitionNumber)
        try {
            Remove-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -Confirm:$false -ErrorAction Stop
        } catch {
            Write-Log "Remove-Partition falló ($($_.Exception.Message)); se intenta con DiskPart."
            [void](Invoke-DiskPart -Commands @("select disk $DiskNumber", "select partition $PartitionNumber", 'delete partition override') -Description 'eliminar la partición')
        }
    }

    function Invoke-Diag {
        $partition = Get-Partition -DriveLetter $Options.DriveLetter -ErrorAction SilentlyContinue
        $style = '?'
        if ($partition) { try { $style = "$((Get-Disk -Number $partition.DiskNumber -ErrorAction Stop).PartitionStyle)" } catch { } }
        return @{
            Ok          = $true
            DriveLetter = $Options.DriveLetter
            BitLocker   = Get-BitLockerState $Options.DriveLetter
            Shadows     = Get-ShadowCopyCount $Options.DriveLetter
            Health      = if ($partition) { Get-DiskHealth $partition.DiskNumber } else { 'Desconocido' }
            Firmware    = if (Test-IsUefi) { 'UEFI' } else { 'BIOS' }
            DiskStyle   = $style
        }
    }

    # Análisis previo: solo lee (monta y desmonta la ISO). No modifica discos ni BCD.
    function Invoke-Preflight {
        $letter = $Options.DriveLetter
        $errors = New-Object Collections.ArrayList
        $warnings = New-Object Collections.ArrayList
        $result = @{ Ok = $true; Errors = $errors; Warnings = $warnings; ShrinkBlocked = $false; Shadows = 0 }

        Set-Status 'Analizando la unidad...'
        Update-StorageView
        $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
        $volume = Get-Volume -DriveLetter $letter -ErrorAction Stop

        if ($disk.IsOffline) { [void]$errors.Add("El disco $($disk.Number) está fuera de línea.") }
        if ($disk.IsReadOnly) { [void]$errors.Add("El disco $($disk.Number) es de solo lectura.") }
        if ($volume.FileSystem -ne 'NTFS') { [void]$errors.Add("La unidad ${letter}: usa $($volume.FileSystem). Solo se pueden reducir volúmenes NTFS.") }
        if ("$($partition.Type)" -eq 'Logical') { [void]$errors.Add("${letter}: es una partición lógica; aquí no se puede crear una partición primaria contigua.") }
        if ("$($disk.PartitionStyle)" -eq 'MBR') {
            $primaryCount = @(Get-Partition -DiskNumber $disk.Number | Where-Object { "$($_.Type)" -ne 'Logical' }).Count
            if ($primaryCount -ge 4) { [void]$errors.Add("El disco es MBR y ya tiene $primaryCount particiones primarias (máximo 4). Hay que liberar una o convertirlo a GPT.") }
        }
        $leftovers = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq $Options.PartitionLabel })
        if ($leftovers.Count -gt 0) { [void]$errors.Add("Ya existen $($leftovers.Count) partición(es) '$($Options.PartitionLabel)'. Usa primero 'Eliminar Arranque y Partición'.") }

        $isoBytes = (Get-Item -LiteralPath $Options.IsoPath).Length
        $requiredGB = [Math]::Ceiling($isoBytes / 1GB) + 2
        $requiredBytes = [int64]$requiredGB * 1GB
        $result.RequiredMB = [int]($requiredGB * 1024)
        $result.RequiredGB = $requiredGB
        $result.DiskNumber = $disk.Number

        # La partición de la ISO queda justo después de la reducida, así que el instalador no podrá volver a agrandarla.
        $minInstallGB = 52
        $remainingGB = ([int64]$partition.Size - $requiredBytes) / 1GB
        if ($letter -eq $env:SystemDrive.TrimEnd(':') -and $remainingGB -lt $minInstallGB) {
            [void]$warnings.Add(("${letter}: quedará con {0:N1} GB. Las versiones recientes de Windows 11 no se instalan en una partición de menos de {1} GB: el instalador la rechazará y no podrás agrandarla desde ahí. Para esas versiones necesitas que ${letter}: tenga al menos {2} GB antes de empezar." -f $remainingGB, $minInstallGB, ($minInstallGB + $requiredGB)))
        }

        if ($volume.SizeRemaining -lt $requiredBytes) {
            [void]$errors.Add(("La unidad {0}: tiene {1:N1} GB libres y se necesitan {2} GB." -f $letter, ($volume.SizeRemaining / 1GB), $requiredGB))
        } else {
            Set-Status 'Calculando cuánto se puede reducir (puede tardar un poco)...'
            $result.Shadows = Get-ShadowCopyCount $letter
            try {
                $supported = Get-PartitionSupportedSize -DriveLetter $letter -ErrorAction Stop
                $shrinkable = [int64]$partition.Size - [int64]$supported.SizeMin
                $result.ShrinkableGB = [Math]::Round($shrinkable / 1GB, 1)
                if ($shrinkable -lt $requiredBytes) {
                    $result.ShrinkBlocked = $true
                    $causes = @()
                    if (Test-Path -LiteralPath "${letter}:\pagefile.sys") { $causes += 'archivo de paginación (pagefile.sys)' }
                    if (Test-Path -LiteralPath "${letter}:\hiberfil.sys") { $causes += 'hibernación (hiberfil.sys): se quita con "powercfg /h off"' }
                    if ($result.Shadows -gt 0) { $causes += "$($result.Shadows) punto(s) de restauración" }
                    $causes += 'archivos que no se pueden mover cerca del final del disco'
                    [void]$errors.Add(("Aunque haya espacio libre, Windows solo permite reducir {0:N1} GB de {1}: y se necesitan {2} GB.`nPosibles causas:`n - {3}" -f ($shrinkable / 1GB), $letter, $requiredGB, ($causes -join "`n - ")))
                }
            } catch {
                [void]$warnings.Add("No se pudo calcular el espacio reducible: $($_.Exception.Message)")
            }
        }

        foreach ($target in @($letter, $env:SystemDrive.TrimEnd(':')) | Select-Object -Unique) {
            switch (Get-BitLockerState $target) {
                'Activo'      { [void]$errors.Add("BitLocker está ACTIVO en ${target}:. Cambiar el arranque pediría la clave de recuperación.`nSuspéndelo como administrador con:`n  manage-bde -protectors -disable ${target}: -RebootCount 0`nO descífralo con:`n  manage-bde -off ${target}:") }
                'EnProceso'   { [void]$errors.Add("BitLocker está cifrando o descifrando ${target}:. Espera a que termine (revísalo con: manage-bde -status ${target}:).") }
                'Suspendido'  { [void]$warnings.Add("BitLocker está suspendido en ${target}:. Puede volver a activarse tras reiniciar.") }
                'Desconocido' { [void]$warnings.Add("No se pudo comprobar BitLocker en ${target}:.") }
            }
        }

        $health = Get-DiskHealth $disk.Number
        if ($health -in 'Advertencia', 'Fallo') { [void]$warnings.Add("Windows reporta el disco como '$health'. Respalda tus datos antes de continuar.") }

        try {
            $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
            if ($batteries | Where-Object { $_.BatteryStatus -eq 1 }) { [void]$warnings.Add('El equipo está usando la batería. Conecta el cargador: un apagón durante la reducción puede dañar los datos.') }
        } catch { }

        Set-Status 'Revisando la ISO...'
        $mount = $null
        try {
            $mount = Mount-Iso $Options.IsoPath
            $root = "$($mount.Letter):\"
            $problems = @(Get-IsoLayoutProblems $root)
            if ($problems.Count -gt 0) {
                [void]$errors.Add("La ISO no parece un instalador de Windows. Falta: $($problems -join ', ')")
            } else {
                $isoInfo = Get-IsoImageInfo $root
                $hostArch = Get-HostArch
                if ($isoInfo.Arch -and $isoInfo.Arch -ne $hostArch) {
                    [void]$errors.Add("La ISO es $($isoInfo.Arch) y este equipo es $hostArch; no podría arrancar.")
                }
                if ($Options.Locale -and $isoInfo.Languages.Count -gt 0 -and $isoInfo.Languages -notcontains $Options.Locale) {
                    [void]$warnings.Add("La ISO no incluye el idioma $($Options.Locale). El instalador usará $($isoInfo.Languages[0]); la región seguirá en $($Options.Locale).")
                }
            }
        } catch {
            $message = "No se pudo revisar la ISO: $($_.Exception.Message)"
            if ($Options.IsAdmin) { [void]$errors.Add($message) } else { [void]$warnings.Add($message) }
        } finally {
            Dismount-Iso $mount
        }

        Write-Log "Análisis de ${letter}: $($errors.Count) error(es), $($warnings.Count) aviso(s). $(($errors + $warnings) -join ' || ')"
        return $result
    }

    function Invoke-ClearShadows {
        Set-Status "Eliminando puntos de restauración de $($Options.DriveLetter):..."
        $run = Invoke-Native -FilePath (Get-NativeTool 'vssadmin.exe') -Arguments "delete shadows /for=$($Options.DriveLetter): /all /quiet" -TimeoutMinutes 10
        Write-Log "vssadmin código=$($run.ExitCode) salida: $($run.Output)"
        return @{ Ok = ($run.ExitCode -eq 0); Error = (Get-LastLines $run.Output) }
    }

    function Find-CreatedPartition {
        param([int]$DiskNumber, [uint64[]]$OffsetsBefore)
        Update-StorageView
        return @(Get-Partition -DiskNumber $DiskNumber | Where-Object { $OffsetsBefore -notcontains [uint64]$_.Offset }) | Select-Object -First 1
    }

    function Invoke-Deploy {
        $letter = $Options.DriveLetter
        $mb = [int]$Options.RequiredMB
        $mount = $null
        $bcdIds = New-Object Collections.ArrayList
        $diskNumber = $null
        $offsetsBefore = $null
        $originalSize = $null
        try {
            Set-Status 'Montando la ISO...' 2
            $mount = Mount-Iso $Options.IsoPath
            $sourceRoot = "$($mount.Letter):\"
            $problems = @(Get-IsoLayoutProblems $sourceRoot)
            if ($problems.Count -gt 0) { throw "La ISO no es válida. Falta: $($problems -join ', ')" }
            $isoInfo = Get-IsoImageInfo $sourceRoot

            Update-StorageView
            $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop
            $diskNumber = [int]$partition.DiskNumber
            $originalSize = [uint64]$partition.Size
            $originalOffset = [uint64]$partition.Offset
            $offsetsBefore = [uint64[]]@(Get-Partition -DiskNumber $diskNumber | ForEach-Object { [uint64]$_.Offset })

            $newLetter = Get-FreeDriveLetter
            Write-Log "Letra libre elegida para la partición nueva: ${newLetter}:"

            # minimum= hace que falle si no se logra el tamaño, en vez de reducir menos y quedarse sin espacio al copiar.
            Set-Status "Reduciendo ${letter}: en $mb MB..." 5
            [void](Invoke-DiskPart -Commands @("select volume $letter", "shrink desired=$mb minimum=$mb") -Description "reducir la unidad ${letter}:")

            Update-StorageView
            $shrunk = Get-Partition -DriveLetter $letter -ErrorAction Stop
            if ([uint64]$shrunk.Size -ge $originalSize) { throw "DiskPart terminó sin errores, pero ${letter}: no se redujo." }

            Set-Status 'Creando la partición de instalación...' 10
            $offsetKB = [uint64]([Math]::Ceiling(($originalOffset + [uint64]$shrunk.Size) / 1MB) * 1024)
            $createCommands = @(
                "format fs=ntfs label=`"$($Options.PartitionLabel)`" quick"
                "assign letter=$newLetter"
            )
            try {
                [void](Invoke-DiskPart -Commands (@("select disk $diskNumber", "create partition primary offset=$offsetKB") + $createCommands) -Description 'crear la partición')
            } catch {
                # Algunos discos MBR rechazan offset=. Solo se reintenta si la partición no llegó a crearse.
                if (Find-CreatedPartition $diskNumber $offsetsBefore) { throw }
                Write-Log "Reintento sin offset: $($_.Exception.Message)"
                [void](Invoke-DiskPart -Commands (@("select disk $diskNumber", 'create partition primary') + $createCommands) -Description 'crear la partición')
            }

            $destinationRoot = "${newLetter}:\"
            $ready = $false
            foreach ($attempt in 1..15) {
                if (Test-Path -LiteralPath $destinationRoot) { $ready = $true; break }
                Start-Sleep -Seconds 1
            }
            if (-not $ready) { throw "La partición nueva no apareció como ${newLetter}:." }
            $createdVolume = Get-Volume -DriveLetter $newLetter -ErrorAction Stop
            if ($createdVolume.FileSystemLabel -ne $Options.PartitionLabel) { throw "${newLetter}: no es la partición nueva (etiqueta '$($createdVolume.FileSystemLabel)')." }

            Set-Status 'Copiando archivos de instalación...' 15
            # La imagen de instalación (install.wim/.esd) es casi toda la ISO: se copia aparte
            # para que la barra y la velocidad sean reales. Las imágenes divididas (.swm) van con robocopy.
            $bigImage = Get-InstallImagePath $sourceRoot
            if ($bigImage -and [IO.Path]::GetExtension($bigImage) -eq '.swm') { $bigImage = $null }
            $bigBytes = if ($bigImage) { [int64](Get-Item -LiteralPath $bigImage).Length } else { [int64]0 }
            $sourceBytes = [int64]0
            foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force -ErrorAction SilentlyContinue)) { $sourceBytes += $file.Length }
            if ($sourceBytes -le $bigBytes) { $sourceBytes = [int64](Get-DiskImage -ImagePath $Options.IsoPath).Size }
            $restBytes = [Math]::Max([int64]1, $sourceBytes - $bigBytes)
            $showCopy = {
                param([int64]$CopiedBytes, [double]$Seconds)
                $fraction = [Math]::Min(1.0, [Math]::Max(0.0, $CopiedBytes / [double]$sourceBytes))
                $speed = if ($Seconds -ge 1) { ' - {0:N0} MB/s' -f ($CopiedBytes / 1MB / $Seconds) } else { '' }
                $Sync.Percent = 15 + [int]($fraction * 65)
                $Sync.Status = ('Copiando archivos de instalación... {0:P0}' -f $fraction) + $speed
            }
            $destinationDrive = New-Object IO.DriveInfo $newLetter
            $baselineUsed = $destinationDrive.TotalSize - $destinationDrive.AvailableFreeSpace
            $copyClock = [Diagnostics.Stopwatch]::StartNew()
            $copyTick = {
                $probe = New-Object IO.DriveInfo $newLetter
                $used = [Math]::Min($restBytes, [Math]::Max([int64]0, ($probe.TotalSize - $probe.AvailableFreeSpace) - $baselineUsed))
                & $showCopy $used $copyClock.Elapsed.TotalSeconds
            }
            $exclude = if ($bigImage) { ' /XF ' + [IO.Path]::GetFileName($bigImage) } else { '' }
            # Sin comillas: una ruta "E:\" entre comillas rompe los argumentos de robocopy.
            $copy = Invoke-Native -FilePath (Get-NativeTool 'robocopy.exe') -Arguments "$sourceRoot $destinationRoot /E /R:2 /W:3 /XJ /NP /NFL /NDL /NJH /NJS$exclude" -OnTick $copyTick -TimeoutMinutes 120 -Cancellable
            $restSeconds = $copyClock.Elapsed.TotalSeconds
            Write-Log "robocopy código=$($copy.ExitCode): $(Format-Speed $restBytes $restSeconds)"
            if ($copy.ExitCode -ge 8) { throw "Robocopy falló al copiar (código $($copy.ExitCode)).`n$(Get-LastLines $copy.Output)" }
            if ($bigImage) {
                $imageName = 'sources\' + [IO.Path]::GetFileName($bigImage)
                Write-Log "Copiando $imageName ($('{0:N2}' -f ($bigBytes / 1GB)) GB)..."
                $imageClock = [Diagnostics.Stopwatch]::StartNew()
                $imageProgress = { param([int64]$Done) & $showCopy ($restBytes + $Done) $copyClock.Elapsed.TotalSeconds }
                [void](Copy-LargeFile -Source $bigImage -Destination (Join-Path $destinationRoot $imageName) -OnProgress $imageProgress)
                Write-Log "$imageName copiado: $(Format-Speed $bigBytes $imageClock.Elapsed.TotalSeconds)"
            }
            Write-Log "Copia total: $(Format-Speed $sourceBytes $copyClock.Elapsed.TotalSeconds)"

            Set-Status 'Verificando la copia...' 82
            $missing = @(Get-IsoLayoutProblems $destinationRoot)
            if ($missing.Count -gt 0) { throw "Faltan archivos tras la copia: $($missing -join ', ')" }
            foreach ($relative in 'sources\boot.wim', ((Get-InstallImagePath $sourceRoot).Substring($sourceRoot.Length))) {
                $sourceFile = Get-Item -LiteralPath (Join-Path $sourceRoot $relative)
                $copiedFile = Get-Item -LiteralPath (Join-Path $destinationRoot $relative)
                if ($sourceFile.Length -ne $copiedFile.Length) { throw "$relative quedó incompleto tras la copia." }
            }

            if ($Options.Automation) {
                Set-Status 'Generando autounattend.xml...' 85
                $settings = @{} + $Options.Automation
                $settings.PartitionLabel = $Options.PartitionLabel
                $settings.Arch = if ($isoInfo.Arch) { $isoInfo.Arch } else { Get-HostArch }
                $settings.UiLanguage = Resolve-UiLanguage $settings.Locale $isoInfo.Languages
                $unattend = New-UnattendXml $settings
                [IO.File]::WriteAllText((Join-Path $destinationRoot 'autounattend.xml'), $unattend, (New-Object Text.UTF8Encoding $false))
            }

            Set-Status 'Configurando el arranque (BCD)...' 90
            $isUefi = Test-IsUefi
            $winload = if ($isUefi) { '\windows\system32\boot\winload.efi' } else { '\windows\system32\winload.exe' }
            try {
                $bootEntries = Get-WindowsImageContent -ImagePath (Join-Path $destinationRoot 'sources\boot.wim') -Index 2 -ErrorAction Stop
                $extension = if ($isUefi) { 'efi' } else { 'exe' }
                foreach ($candidate in "windows\system32\boot\winload.$extension", "windows\system32\winload.$extension") {
                    if ($bootEntries -contains $candidate) { $winload = "\$candidate"; break }
                }
            } catch { Write-Log "No se pudo inspeccionar boot.wim; se usa la ruta por defecto: $($_.Exception.Message)" }
            Write-Log "Firmware UEFI=$isUefi; winload=$winload"

            $ramdiskOutput = Invoke-BcdEdit '/create /d "WinDeployBS" /device'
            if ($ramdiskOutput -notmatch '\{[a-fA-F0-9\-]{36}\}') { throw 'No se pudo crear la entrada Ramdisk en BCD.' }
            $ramdiskGuid = $Matches[0]
            [void]$bcdIds.Add($ramdiskGuid)
            [void](Invoke-BcdEdit "/set $ramdiskGuid ramdisksdidevice `"partition=${newLetter}:`"")
            [void](Invoke-BcdEdit "/set $ramdiskGuid ramdisksdipath `"\boot\boot.sdi`"")

            $loaderOutput = Invoke-BcdEdit '/create /d "WinDeploy" /application osloader'
            if ($loaderOutput -notmatch '\{[a-fA-F0-9\-]{36}\}') { throw 'No se pudo crear la entrada OSLoader en BCD.' }
            $loaderGuid = $Matches[0]
            [void]$bcdIds.Add($loaderGuid)
            $ramdiskDevice = "ramdisk=[${newLetter}:]\sources\boot.wim,$ramdiskGuid"
            [void](Invoke-BcdEdit "/set $loaderGuid device `"$ramdiskDevice`"")
            [void](Invoke-BcdEdit "/set $loaderGuid path `"$winload`"")
            [void](Invoke-BcdEdit "/set $loaderGuid osdevice `"$ramdiskDevice`"")
            [void](Invoke-BcdEdit "/set $loaderGuid systemroot `"\windows`"")
            [void](Invoke-BcdEdit "/set $loaderGuid winpe yes")
            [void](Invoke-BcdEdit "/displayorder $loaderGuid /addlast")
            [void](Invoke-BcdEdit "/bootsequence $loaderGuid")
            [void](Invoke-BcdEdit '/timeout 10')

            Set-Status 'Guardando datos para poder deshacer...' 97
            $undoInfo = @{
                OriginalDriveLetter     = $letter
                OriginalPartitionNumber = [int]$partition.PartitionNumber
                DiskNumber              = $diskNumber
                OsLoaderGuid            = $loaderGuid
                RamdiskGuid             = $ramdiskGuid
            } | ConvertTo-Json
            [IO.File]::WriteAllText((Join-Path $destinationRoot $Options.RglFileName), $undoInfo, (New-Object Text.UTF8Encoding $false))

            Set-Status 'Listo.' 100
            return @{ Ok = $true; NewLetter = $newLetter }
        } catch {
            $failure = $_.Exception.Message
            $wasCancelled = [bool]$Sync.Cancel
            $Sync.Cancel = $false
            Write-Log "ERROR: $failure"
            Set-Status 'Revirtiendo los cambios de esta ejecución...'
            $rollbackIssues = @()

            Remove-BcdEntries @($bcdIds)

            # Solo se borra la partición que NO existía antes de empezar, nunca algo elegido por letra.
            $partitionRemoved = $true
            if ($null -ne $offsetsBefore) {
                try {
                    $created = Find-CreatedPartition $diskNumber $offsetsBefore
                    if ($created) {
                        Write-Log "Reversión: se elimina la partición creada (disco $diskNumber, partición $($created.PartitionNumber))."
                        Remove-PartitionSafe $diskNumber ([int]$created.PartitionNumber)
                    }
                } catch {
                    $partitionRemoved = $false
                    $rollbackIssues += "No se pudo eliminar la partición creada: $($_.Exception.Message)"
                }

                if ($partitionRemoved) {
                    try {
                        Update-StorageView
                        $current = Get-Partition -DriveLetter $letter -ErrorAction Stop
                        if ([uint64]$current.Size -lt $originalSize) {
                            Write-Log "Reversión: se devuelve el espacio a ${letter}:."
                            [void](Invoke-DiskPart -Commands @("select volume $letter", 'extend') -Description "extender la unidad ${letter}:")
                        }
                    } catch {
                        $rollbackIssues += "No se pudo devolver el espacio a ${letter}:: $($_.Exception.Message)"
                    }
                }
            }

            foreach ($issue in $rollbackIssues) { Write-Log "REVERSI$([char]0xD3)N INCOMPLETA: $issue" }
            return @{ Ok = $false; Error = $failure; RollbackIssues = $rollbackIssues; Cancelled = $wasCancelled }
        } finally {
            Dismount-Iso $mount
        }
    }

    function Invoke-Undo {
        $issues = New-Object Collections.ArrayList
        Set-Status 'Buscando particiones de instalación...'
        Update-StorageView
        $volumes = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq $Options.PartitionLabel })

        $originalLetter = $null
        $bcdIds = New-Object Collections.ArrayList
        foreach ($volume in $volumes) {
            if (-not $volume.DriveLetter) { continue }
            $infoPath = "$($volume.DriveLetter):\$($Options.RglFileName)"
            if (Test-Path -LiteralPath $infoPath) {
                try {
                    $info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
                    foreach ($id in $info.OsLoaderGuid, $info.RamdiskGuid) { if ($id) { [void]$bcdIds.Add($id) } }
                    if ($info.OriginalDriveLetter) { $originalLetter = [string]$info.OriginalDriveLetter }
                } catch { Write-Log "Registro ilegible en ${infoPath}: $($_.Exception.Message)" }
            }
        }

        Set-Status 'Eliminando entradas de arranque...' 20
        try {
            $bcdText = Invoke-BcdEdit '/enum all /v'
            foreach ($id in (Get-WinDeployBcdIdsFromText $bcdText)) { [void]$bcdIds.Add($id) }
        } catch { Write-Log "No se pudo listar BCD: $($_.Exception.Message)" }
        Remove-BcdEntries @($bcdIds | Select-Object -Unique)

        $targets = @()
        foreach ($volume in $volumes) {
            try {
                $found = $volume | Get-Partition -ErrorAction Stop
                $targets += $found
            } catch { [void]$issues.Add("No se encontró la partición del volumen $($volume.UniqueId).") }
        }

        Set-Status 'Eliminando particiones...' 50
        $extendLetters = New-Object Collections.ArrayList
        foreach ($group in ($targets | Group-Object DiskNumber)) {
            $diskNumber = [int]$group.Name
            $firstOffset = [uint64](($group.Group | Measure-Object Offset -Minimum).Minimum)
            $previous = Get-Partition -DiskNumber $diskNumber |
                Where-Object { [uint64]$_.Offset -lt $firstOffset } |
                Sort-Object { [uint64]$_.Offset } | Select-Object -Last 1
            $adjacent = $previous -and $previous.DriveLetter -and (($firstOffset - ([uint64]$previous.Offset + [uint64]$previous.Size)) -le 2MB)

            $removedAll = $true
            foreach ($target in ($group.Group | Sort-Object { [uint64]$_.Offset } -Descending)) {
                try {
                    Remove-PartitionSafe $diskNumber ([int]$target.PartitionNumber)
                } catch {
                    $removedAll = $false
                    [void]$issues.Add("Disco $diskNumber, partición $($target.PartitionNumber): $($_.Exception.Message)")
                }
            }
            if ($removedAll) {
                if ($adjacent) { [void]$extendLetters.Add([string]$previous.DriveLetter) }
                else {
                    $freedGB = [Math]::Round((($group.Group | Measure-Object Size -Sum).Sum) / 1GB, 1)
                    if ($previous -and "$($previous.Type)" -eq 'Recovery') {
                        [void]$issues.Add("Quedaron $freedGB GB sin asignar en el disco ${diskNumber}: Windows creó su partición de recuperación justo antes y por eso no se pueden sumar a la unidad. No se tocó esa partición; puedes usar ese espacio para crear otra unidad en Administración de discos.")
                    } else {
                        [void]$issues.Add("Quedaron $freedGB GB sin asignar en el disco ${diskNumber}: la partición anterior no es contigua o no tiene letra. Puedes usarlos desde Administración de discos.")
                    }
                }
            }
        }

        Set-Status 'Recuperando el espacio...' 80
        foreach ($target in $extendLetters) {
            if ($originalLetter -and $originalLetter -ne $target) { Write-Log "Aviso: el registro indicaba ${originalLetter}: y la partición contigua es ${target}:." }
            try {
                [void](Invoke-DiskPart -Commands @("select volume $target", 'extend') -Description "extender la unidad ${target}:")
            } catch {
                [void]$issues.Add($_.Exception.Message)
            }
        }

        Set-Status 'Listo.' 100
        return @{ Ok = $true; Removed = $targets.Count; Issues = $issues }
    }

    try {
        switch ($Operation) {
            'Diag'         { Invoke-Diag }
            'Preflight'    { Invoke-Preflight }
            'ClearShadows' { Invoke-ClearShadows }
            'Deploy'       { Invoke-Deploy }
            'Undo'         { Invoke-Undo }
            default        { throw "Operación desconocida: $Operation" }
        }
    } catch {
        Write-Log "ERROR en ${Operation}: $($_.Exception.Message)"
        @{ Ok = $false; Error = $_.Exception.Message }
    }
}
#endregion

#region --- GUI Creation and Variable Initialization ---
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$diskComboBox = $window.FindName("DiskComboBox")
$isoPathTextBox = $window.FindName("IsoPathTextBox")
$selectIsoButton = $window.FindName("SelectIsoButton")
$createButton = $window.FindName("CreateButton")
$undoButton = $window.FindName("UndoButton")
$openLogButton = $window.FindName("OpenLogButton")
$refreshButton = $window.FindName("RefreshButton")
$cancelButton = $window.FindName("CancelButton")
$logTextBox = $window.FindName("LogTextBox")
$percentTextBlock = $window.FindName("PercentTextBlock")
$isoInfoTextBlock = $window.FindName("IsoInfoTextBlock")
$diagFirmware = $window.FindName("DiagFirmware")
$modeBadge = $window.FindName("ModeBadge")
$window.FindName("VersionTextBlock").Text = "v$script:AppVersion"
$statusTextBlock = $window.FindName("StatusTextBlock")
$headerTextBlock = $window.FindName("HeaderTextBlock")
$diagBitlocker = $window.FindName("DiagBitlocker")
$diagVSS = $window.FindName("DiagVSS")
$diagSysDisk = $window.FindName("DiagSysDisk")
$progressBar = $window.FindName("ProgressBar")
$automateInstallCheckBox = $window.FindName("AutomateInstallCheckBox")
$automationWarningTextBlock = $window.FindName("AutomationWarningTextBlock")
$automationDetailsPanel = $window.FindName("AutomationDetailsPanel")
$txtUsername = $window.FindName("txtUsername")
$pwdPassword = $window.FindName("pwdPassword")
$txtProductKey = $window.FindName("txtProductKey")
$chk_BypassTPM = $window.FindName("chk_BypassTPM")
$chk_BypassSecureBoot = $window.FindName("chk_BypassSecureBoot")
$cmb_Locale = $window.FindName("cmb_Locale")
$chk_SkipWifi = $window.FindName("chk_SkipWifi")
$chk_SkipPostInstallOOBE = $window.FindName("chk_SkipPostInstallOOBE")

$script:PartitionLabel = "WinDeployBS"
$script:RglFileName = "WinDeploy.log"
$script:Locales = @("es-ES", "es-MX", "es-CO", "en-US", "fr-FR", "de-DE")
$script:DiskItems = @{}
$script:Tasks = New-Object Collections.ArrayList
$script:Busy = $false
$script:Ctx = $null
$script:MainSync = $null
$script:BrushConverter = New-Object System.Windows.Media.BrushConverter

$script:LogFile = $null
foreach ($logDir in @($(if (-not $TempCopy) { $PSScriptRoot }), (Join-Path $env:ProgramData 'WinDeployBS'), $env:TEMP)) {
    if (-not $logDir) { continue }
    try {
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null }
        $candidateLog = Join-Path $logDir 'WinDeployBS_log.txt'
        Add-Content -Path $candidateLog -Value ("`r`n===== {0} | Equipo={1} | Usuario={2} | v$script:AppVersion{3} =====" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, $env:USERNAME, $(if ($DryRun) { ' | SIMULACION' })) -Encoding UTF8 -ErrorAction Stop
        $script:LogFile = $candidateLog
        break
    } catch { }
}

if ($DryRun) {
    $window.Title += "  [MODO SIMULACI$([char]0xD3)N]"
    $modeBadge.Visibility = "Visible"
    $createButton.Content = "Analizar (simulación)"
}
#endregion

#region --- Helper Functions ---

function Show-MessageBox {
    param(
        [string]$message,
        [string]$title,
        [string]$icon = "Information",
        [string]$buttons = "OK"
    )
    return [System.Windows.MessageBox]::Show($window, $message, $title, $buttons, $icon)
}

function Add-ActivityLine {
    param([string]$Text)
    $logTextBox.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $Text))
    $logTextBox.ScrollToEnd()
}

function Set-IsoPath {
    # Devuelve $true si la ruta es una ISO existente y quedó seleccionada.
    param([string]$Path)
    if (-not $Path -or [IO.Path]::GetExtension($Path) -ne '.iso' -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $isoPathTextBox.Text = $Path
    $file = Get-Item -LiteralPath $Path
    $needGB = [Math]::Ceiling($file.Length / 1GB) + 2
    $isoInfoTextBlock.Text = "{0} - {1:N2} GB. Se reducirán {2} GB de la unidad elegida." -f $file.Name, ($file.Length / 1GB), $needGB
    $isoInfoTextBlock.Foreground = $script:BrushConverter.ConvertFromString('#FF93C5FD')
    return $true
}

function Set-DiagText {
    param($Control, [string]$Text, [string]$Color)
    $Control.Text = $Text
    $Control.Foreground = $script:BrushConverter.ConvertFromString($Color)
}

function Reset-DiagPanel {
    foreach ($control in $diagBitlocker, $diagVSS, $diagSysDisk, $diagFirmware) { Set-DiagText $control '-' '#FF9CA3AF' }
}

function Set-Busy {
    param([bool]$IsBusy)
    $script:Busy = $IsBusy
    $enabled = -not $IsBusy
    $diskComboBox.IsEnabled = $enabled
    $refreshButton.IsEnabled = $enabled
    $selectIsoButton.IsEnabled = $enabled
    $createButton.IsEnabled = $enabled
    $automateInstallCheckBox.IsEnabled = $enabled
    $automationDetailsPanel.IsEnabled = $enabled
    if ($IsBusy) {
        $undoButton.IsEnabled = $false
        $progressBar.IsIndeterminate = $true
    } else {
        Update-UndoButtonState
        $progressBar.IsIndeterminate = $false
        $percentTextBlock.Text = ''
        $cancelButton.Visibility = 'Collapsed'
    }
}

function Update-UndoButtonState {
    try {
        $found = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq $script:PartitionLabel })
    } catch { $found = @() }
    if ($found.Count -gt 0) {
        $undoButton.IsEnabled = -not $DryRun
        $undoButton.ToolTip = "Se encontraron $($found.Count) partición(es) de instalación."
    } else {
        $undoButton.IsEnabled = $false
        $undoButton.ToolTip = "No se encontró una partición de instalación existente."
    }
}

function Load-Disks {
    try {
        $previous = $null
        if ($diskComboBox.SelectedItem) { $previous = $script:DiskItems[[string]$diskComboBox.SelectedItem] }
        $diskComboBox.Items.Clear()
        $script:DiskItems = @{}

        $disks = @(Get-Disk | Where-Object { $_.BusType -notin 'USB', 'File Backed Virtual' -and $_.PartitionStyle -ne 'RAW' -and -not $_.IsOffline })
        if ($disks.Count -eq 0) {
            Show-MessageBox "No se detectaron discos internos." "Error Crítico" "Error"
            return
        }

        $systemLetter = $env:SystemDrive.TrimEnd(':')
        $toSelect = $null
        foreach ($disk in $disks) {
            $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and "$($_.Type)" -ne 'Recovery' })
            foreach ($partition in $partitions) {
                $letter = [string]$partition.DriveLetter
                $volume = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
                if (-not $volume -or $volume.FileSystemLabel -eq $script:PartitionLabel) { continue }
                $tag = if ($letter -eq $systemLetter) { ' [Windows]' } else { '' }
                $item = "{0}:\{1} ({2:N2} GB) - {3:N2} GB libres" -f $letter, $tag, ($partition.Size / 1GB), ($volume.SizeRemaining / 1GB)
                $script:DiskItems[$item] = $letter
                [void]$diskComboBox.Items.Add($item)
                if ($letter -eq $previous -or (-not $toSelect -and $letter -eq $systemLetter)) { $toSelect = $item }
            }
        }

        if ($diskComboBox.Items.Count -eq 0) {
            Show-MessageBox "No se encontraron particiones con letra de unidad en los discos internos." "No se encontraron particiones" "Warning"
            return
        }
        if ($toSelect) { $diskComboBox.SelectedItem = $toSelect }
    } catch {
        Show-MessageBox "Ocurrió un error al cargar los discos: $($_.Exception.Message)" "Error de Carga" "Error"
    }
}

function Start-BackgroundTask {
    param([string]$Operation, [hashtable]$Options, [scriptblock]$OnComplete, [bool]$Quiet = $false)
    $Options.LogFile = $script:LogFile
    $Options.PartitionLabel = $script:PartitionLabel
    $Options.RglFileName = $script:RglFileName
    $Options.IsAdmin = $script:IsAdmin

    $sync = [hashtable]::Synchronized(@{ Status = $null; Percent = -1; Cancel = $false })
    $sync.Log = [Collections.Queue]::Synchronized((New-Object Collections.Queue))
    if (-not $Quiet) { $script:MainSync = $sync }
    $sessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $sessionState.ExecutionPolicy = 'Bypass'
    $runspace = [runspacefactory]::CreateRunspace($sessionState)
    $runspace.Open()
    $shell = [powershell]::Create()
    $shell.Runspace = $runspace
    [void]$shell.AddScript($script:WorkerScript.ToString()).
        AddParameter('Operation', $Operation).
        AddParameter('Options', $Options).
        AddParameter('Sync', $sync)
    $handle = $shell.BeginInvoke()
    [void]$script:Tasks.Add(@{ Shell = $shell; Runspace = $runspace; Handle = $handle; Sync = $sync; OnComplete = $OnComplete; Quiet = $Quiet })
    if (-not $script:Timer.IsEnabled) { $script:Timer.Start() }
}

function Invoke-TaskTick {
    foreach ($task in @($script:Tasks)) {
        if (-not $task.Quiet) {
            while ($task.Sync.Log.Count -gt 0) { Add-ActivityLine ([string]$task.Sync.Log.Dequeue()) }
        }
        if (-not $task.Quiet -and $task.Sync.Status) {
            $statusTextBlock.Text = $task.Sync.Status
            $percent = [int]$task.Sync.Percent
            if ($percent -ge 0) {
                $progressBar.IsIndeterminate = $false
                $progressBar.Value = $percent
                $percentTextBlock.Text = "$percent %"
            } else {
                $progressBar.IsIndeterminate = $true
                $percentTextBlock.Text = ''
            }
        }
        if (-not $task.Handle.IsCompleted) { continue }

        $script:Tasks.Remove($task)
        $result = $null
        try {
            $output = $task.Shell.EndInvoke($task.Handle)
            $result = @($output | Where-Object { $_ -is [hashtable] }) | Select-Object -Last 1
            if (-not $result) {
                $streamError = $task.Shell.Streams.Error | Select-Object -First 1
                $result = @{ Ok = $false; Error = $(if ($streamError) { "$streamError" } else { 'La operación terminó sin devolver un resultado.' }) }
            }
        } catch {
            $result = @{ Ok = $false; Error = $_.Exception.Message }
        } finally {
            $task.Shell.Dispose()
            $task.Runspace.Dispose()
        }
        try {
            & $task.OnComplete $result
        } catch {
            Set-Busy $false
            $statusTextBlock.Text = "Error inesperado."
            Show-MessageBox "Error inesperado: $($_.Exception.Message)`n`nRegistro: $script:LogFile" "Error" "Error"
        }
    }
    if ($script:Tasks.Count -eq 0) { $script:Timer.Stop() }
}

function Get-ValidationError {
    # Devuelve el texto del problema, o $null si los datos de automatización son válidos.
    param([string]$Username, [string]$ProductKey, [bool]$SkipOobe)
    if ($SkipOobe) {
        $name = $Username.Trim()
        if (-not $name) { return "Escribe un nombre de usuario." }
        if ($name.Length -gt 20) { return "El nombre de usuario admite máximo 20 caracteres." }
        if ($name -match '["/\\\[\]:;|=,+*?<>@]' -or $name.EndsWith('.')) { return "El nombre de usuario tiene caracteres no permitidos (por ejemplo / \ [ ] : ; | = , + * ? < > @ o un punto final)." }
        if ($name -in 'Administrator', 'Administrador', 'Guest', 'Invitado', 'DefaultAccount', 'SYSTEM') { return "'$name' es un nombre reservado por Windows; elige otro." }
    }
    if ($ProductKey.Trim() -and $ProductKey.Trim() -notmatch '^([A-Za-z0-9]{5}-){4}[A-Za-z0-9]{5}$') {
        return "La clave de producto debe tener el formato XXXXX-XXXXX-XXXXX-XXXXX-XXXXX."
    }
    return $null
}

function Start-Preflight {
    Set-Busy $true
    $statusTextBlock.Text = "Analizando el equipo..."
    Start-BackgroundTask -Operation 'Preflight' -Options @{
        DriveLetter = $script:Ctx.DriveLetter
        IsoPath     = $script:Ctx.IsoPath
        Locale      = $(if ($script:Ctx.Automation) { $script:Ctx.Automation.Locale } else { $null })
    } -OnComplete { param($r) Complete-Preflight $r }
}

function Complete-Preflight {
    param($Result)
    Set-Busy $false
    $progressBar.Value = 0
    if (-not $Result.Ok) {
        $statusTextBlock.Text = "No se pudo analizar el equipo."
        Show-MessageBox "No se pudo completar el análisis:`n$($Result.Error)`n`nRegistro: $script:LogFile" "Error" "Error"
        return
    }

    $letter = $script:Ctx.DriveLetter
    $errors = @($Result.Errors)
    $warnings = @($Result.Warnings)
    foreach ($line in $errors) { Add-ActivityLine ("PROBLEMA: " + ($line -replace '\s*\r?\n\s*', ' ')) }
    foreach ($line in $warnings) { Add-ActivityLine ("AVISO: " + ($line -replace '\s*\r?\n\s*', ' ')) }

    # El bloqueo se resuelve eliminando puntos de restauración solo si son lo único corregible aquí.
    if ($Result.ShrinkBlocked -and $Result.Shadows -gt 0 -and -not $script:Ctx.ShadowsCleared -and -not $DryRun) {
        $answer = Show-MessageBox ("Windows no puede reducir {0}: lo suficiente y hay {1} punto(s) de restauración que pueden estar bloqueándolo.`n`n¿Eliminar esos puntos de restauración y volver a analizar?`n`nEsta acción no se puede deshacer." -f $letter, $Result.Shadows) "Espacio bloqueado" "Warning" "YesNo"
        if ("$answer" -eq 'Yes') {
            $script:Ctx.ShadowsCleared = $true
            Set-Busy $true
            Start-BackgroundTask -Operation 'ClearShadows' -Options @{ DriveLetter = $letter } -OnComplete {
                param($r)
                Set-Busy $false
                if ($r.Ok) {
                    Start-Preflight
                } else {
                    $statusTextBlock.Text = "No se pudieron eliminar los puntos de restauración."
                    Show-MessageBox "vssadmin no pudo eliminarlos:`n$($r.Error)" "Error" "Error"
                }
            }
            return
        }
    }

    if ($errors.Count -gt 0) {
        $statusTextBlock.Text = "Análisis terminado: hay que resolver $($errors.Count) problema(s). No se modificó nada."
        Show-MessageBox ("No se puede continuar (no se modificó nada):`n`n" + ($errors -join "`n`n")) "Revisión previa" "Warning"
        return
    }

    $plan = @(
        "Se reducirá {0}: en {1} GB." -f $letter, $Result.RequiredGB
        "Se creará la partición '$script:PartitionLabel' con la ISO."
        "Se agregará una entrada al menú de arranque."
    )
    $warningText = if ($warnings.Count -gt 0) { "`n`nAvisos:`n - " + ($warnings -join "`n - ") } else { '' }

    if ($DryRun) {
        $statusTextBlock.Text = "Simulación terminada. No se modificó nada."
        Show-MessageBox ("SIMULACI$([char]0xD3)N: el equipo pasó el análisis.`n`nSin este modo, haría lo siguiente:`n - " + ($plan -join "`n - ") + $warningText) "Modo simulación" "Information"
        return
    }

    $confirm = Show-MessageBox ("ADVERTENCIA: se va a modificar tu disco y el menú de arranque. Asegúrate de tener un respaldo.`n`n - " + ($plan -join "`n - ") + $warningText + "`n`n¿Deseas continuar?") "Confirmación Final" "Warning" "YesNo"
    if ("$confirm" -ne 'Yes') {
        $statusTextBlock.Text = "Operación cancelada por el usuario."
        return
    }

    Set-Busy $true
    $cancelButton.Visibility = 'Visible'
    $cancelButton.IsEnabled = $true
    $statusTextBlock.Text = "Iniciando proceso..."
    Start-BackgroundTask -Operation 'Deploy' -Options @{
        DriveLetter = $letter
        IsoPath     = $script:Ctx.IsoPath
        RequiredMB  = $Result.RequiredMB
        Automation  = $script:Ctx.Automation
    } -OnComplete { param($r) Complete-Deploy $r }
}

function Complete-Deploy {
    param($Result)
    $script:Ctx = $null
    Set-Busy $false
    Load-Disks
    if ($Result.Ok) {
        $progressBar.Value = 100
        $statusTextBlock.Text = "¡Éxito! Reinicia para comenzar la instalación."
        $answer = Show-MessageBox "¡Arranque creado en $($Result.NewLetter):!`n`n¿Reiniciar ahora para abrir el instalador de Windows?" "Proceso Finalizado" "Information" "YesNo"
        if ("$answer" -eq 'Yes') { Restart-Computer -Force }
    } else {
        $progressBar.Value = 0
        $issues = @($Result.RollbackIssues)
        if ($Result.Cancelled -and $issues.Count -eq 0) {
            $statusTextBlock.Text = "Cancelado. Los cambios fueron revertidos."
            Add-ActivityLine $statusTextBlock.Text
        } elseif ($issues.Count -gt 0) {
            $statusTextBlock.Text = "El proceso falló y la reversión quedó incompleta."
            Show-MessageBox ("El proceso falló:`n$($Result.Error)`n`nATENCI$([char]0xD3)N, no se pudo revertir todo:`n - " + ($issues -join "`n - ") + "`n`nRegistro: $script:LogFile") "Error Crítico" "Error"
        } else {
            $statusTextBlock.Text = "El proceso falló. Los cambios fueron revertidos."
            Show-MessageBox "El proceso falló:`n$($Result.Error)`n`nLos cambios de esta ejecución fueron revertidos.`n`nRegistro: $script:LogFile" "Error" "Error"
        }
    }
}

function Complete-Undo {
    param($Result)
    Set-Busy $false
    Load-Disks
    if ($Result.Ok) {
        $progressBar.Value = 100
        $issues = @($Result.Issues)
        if ($issues.Count -gt 0) {
            $statusTextBlock.Text = "Eliminación terminada con avisos."
            Show-MessageBox ("Se terminó con avisos:`n - " + ($issues -join "`n - ") + "`n`nRegistro: $script:LogFile") "Aviso" "Warning"
        } else {
            $statusTextBlock.Text = "Listo. Cambios deshechos."
            Show-MessageBox "La partición y el arranque fueron eliminados correctamente." "Éxito" "Information"
        }
    } else {
        $progressBar.Value = 0
        $statusTextBlock.Text = "Falló el proceso de eliminación."
        Show-MessageBox "Ocurrió un error: $($Result.Error)`n`nRegistro: $script:LogFile" "Error" "Error"
    }
}

function Complete-Diag {
    param($Result)
    if (-not $Result.Ok -or -not $diskComboBox.SelectedItem) { return }
    # Ignora resultados de una unidad que ya no está seleccionada.
    if ($script:DiskItems[[string]$diskComboBox.SelectedItem] -ne $Result.DriveLetter) { return }

    switch ($Result.BitLocker) {
        'Activo'      { Set-DiagText $diagBitlocker '[!] Activo' '#FFFBBF24' }
        'Suspendido'  { Set-DiagText $diagBitlocker '[!] Suspendido' '#FFFBBF24' }
        'EnProceso'   { Set-DiagText $diagBitlocker '[!] En proceso' '#FFFBBF24' }
        'Inactivo'    { Set-DiagText $diagBitlocker '[OK] Inactivo' '#FF4ADE80' }
        default       { Set-DiagText $diagBitlocker '[?] Desconocido' '#FF9CA3AF' }
    }
    if ($Result.Shadows -lt 0) { Set-DiagText $diagVSS '[?] Desconocido' '#FF9CA3AF' }
    elseif ($Result.Shadows -gt 0) { Set-DiagText $diagVSS "[i] $($Result.Shadows) punto(s)" '#FFFBBF24' }
    else { Set-DiagText $diagVSS '[OK] Ninguno' '#FF4ADE80' }
    switch ($Result.Health) {
        'Saludable'   { Set-DiagText $diagSysDisk '[OK] Saludable' '#FF4ADE80' }
        'Advertencia' { Set-DiagText $diagSysDisk '[!] Advertencia' '#FFFBBF24' }
        'Fallo'       { Set-DiagText $diagSysDisk '[X] Con fallos' '#FFEF4444' }
        default       { Set-DiagText $diagSysDisk '[?] Sin datos' '#FF9CA3AF' }
    }
    Set-DiagText $diagFirmware ("{0} / {1}" -f $Result.Firmware, $Result.DiskStyle) '#FF93C5FD'
}
#endregion

#region --- Event Handlers ---

$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:Timer.Add_Tick({ Invoke-TaskTick })

$window.Add_SourceInitialized({
    foreach ($locale in $script:Locales) { [void]$cmb_Locale.Items.Add($locale) }
    $currentCulture = [Globalization.CultureInfo]::CurrentUICulture.Name
    $cmb_Locale.SelectedItem = if ($script:Locales -contains $currentCulture) { $currentCulture } else { 'es-ES' }
    Load-Disks
    Update-UndoButtonState
    if ($DryRun) { $statusTextBlock.Text = "Modo simulación: nada se modificará." }
    if ($IsoPath -and -not (Set-IsoPath $IsoPath)) { Add-ActivityLine "No se pudo usar la ISO indicada: $IsoPath" }
    Add-ActivityLine "WinDeploy v$script:AppVersion listo. Registro: $script:LogFile"
})

$refreshButton.Add_Click({
    Load-Disks
    Update-UndoButtonState
    Add-ActivityLine 'Lista de unidades actualizada.'
})

$cancelButton.Add_Click({
    if ($script:MainSync) {
        $script:MainSync.Cancel = $true
        $cancelButton.IsEnabled = $false
        Add-ActivityLine 'Cancelando: se detendrá en cuanto sea seguro y se revertirán los cambios...'
    }
})

# Arrastrar la ISO a cualquier parte de la ventana
$dragHandler = {
    param($dragSource, $e)
    $e.Effects = if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop) -and -not $script:Busy) { 'Copy' } else { 'None' }
    $e.Handled = $true
}
$window.Add_PreviewDragOver($dragHandler)
$window.Add_PreviewDragEnter($dragHandler)
$window.Add_PreviewDrop({
    param($dragSource, $e)
    $e.Handled = $true
    if ($script:Busy) { return }
    $dropped = @($e.Data.GetData([System.Windows.DataFormats]::FileDrop))
    if ($dropped.Count -eq 0) { return }
    if (Set-IsoPath ([string]$dropped[0])) {
        Add-ActivityLine "ISO seleccionada: $($dropped[0])"
    } else {
        Show-MessageBox "Eso no es un archivo .iso válido." "Archivo no válido" "Warning" | Out-Null
    }
})

$window.Add_Closing({
    param($closingSource, $e)
    if ($script:Busy) {
        Show-MessageBox "Hay una operación en curso. Cerrar ahora podría dejar el disco a medio modificar. Espera a que termine." "Operación en curso" "Warning" | Out-Null
        $e.Cancel = $true
    }
})

$diskComboBox.Add_SelectionChanged({
    Reset-DiagPanel
    $selected = $diskComboBox.SelectedItem
    if ($selected -and $script:DiskItems.ContainsKey([string]$selected)) {
        Start-BackgroundTask -Operation 'Diag' -Options @{ DriveLetter = $script:DiskItems[[string]$selected] } -Quiet $true -OnComplete { param($r) Complete-Diag $r }
    }
})

$automateInstallCheckBox.Add_Checked({
    $automationWarningTextBlock.Visibility = "Visible"
    $automationDetailsPanel.Visibility = "Visible"
})

$automateInstallCheckBox.Add_Unchecked({
    $automationWarningTextBlock.Visibility = "Collapsed"
    $automationDetailsPanel.Visibility = "Collapsed"
})

$openLogButton.Add_Click({
    if ($script:LogFile -and (Test-Path -LiteralPath $script:LogFile)) {
        Start-Process notepad.exe -ArgumentList "`"$script:LogFile`""
    } else {
        Show-MessageBox "Todavía no hay un registro disponible." "Registro" "Information" | Out-Null
    }
})

$selectIsoButton.Add_Click({
    $openFileDialog = New-Object Microsoft.Win32.OpenFileDialog
    $openFileDialog.Filter = "Archivos ISO (*.iso)|*.iso"
    $openFileDialog.Title = "Seleccionar archivo ISO de Windows"
    if ($openFileDialog.ShowDialog($window) -eq $true) {
        if (Set-IsoPath $openFileDialog.FileName) { Add-ActivityLine "ISO seleccionada: $($openFileDialog.FileName)" }
    }
})

$createButton.Add_Click({
    if (-not $diskComboBox.SelectedItem) {
        Show-MessageBox "Por favor, selecciona una unidad de la lista." "Selección Requerida" "Warning" | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($isoPathTextBox.Text) -or -not (Test-Path -LiteralPath $isoPathTextBox.Text)) {
        Show-MessageBox "Por favor, selecciona un archivo ISO válido." "Archivo Requerido" "Warning" | Out-Null
        return
    }

    $automation = $null
    if ($automateInstallCheckBox.IsChecked) {
        $skipOobe = [bool]$chk_SkipPostInstallOOBE.IsChecked
        $problem = Get-ValidationError -Username $txtUsername.Text -ProductKey $txtProductKey.Text -SkipOobe $skipOobe
        if ($problem) {
            Show-MessageBox $problem "Revisa los datos" "Warning" | Out-Null
            return
        }
        $automation = @{
            Username         = $txtUsername.Text.Trim()
            Password         = $pwdPassword.Password
            ProductKey       = $txtProductKey.Text.Trim().ToUpper()
            Locale           = [string]$cmb_Locale.SelectedItem
            BypassTPM        = [bool]$chk_BypassTPM.IsChecked
            BypassSecureBoot = [bool]$chk_BypassSecureBoot.IsChecked
            SkipWifi         = [bool]$chk_SkipWifi.IsChecked
            SkipOobe         = $skipOobe
        }
    }

    $script:Ctx = @{
        DriveLetter    = $script:DiskItems[[string]$diskComboBox.SelectedItem]
        IsoPath        = $isoPathTextBox.Text
        Automation     = $automation
        ShadowsCleared = $false
    }
    Start-Preflight
})

$undoButton.Add_Click({
    $found = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq $script:PartitionLabel })
    if ($found.Count -eq 0) {
        Show-MessageBox "No se encontró ninguna partición '$script:PartitionLabel' para eliminar." "No Encontrado" "Information" | Out-Null
        Update-UndoButtonState
        return
    }
    $answer = Show-MessageBox ("Se eliminarán {0} partición(es) '{1}' y sus entradas de arranque, y el espacio volverá a la unidad contigua. ¿Estás seguro?" -f $found.Count, $script:PartitionLabel) "Confirmar Eliminación" "Warning" "YesNo"
    if ("$answer" -ne 'Yes') { return }

    Set-Busy $true
    $statusTextBlock.Text = "Eliminando partición y arranque..."
    Start-BackgroundTask -Operation 'Undo' -Options @{} -OnComplete { param($r) Complete-Undo $r }
})

#endregion

# --- Show Window ---
$window.ShowDialog() | Out-Null

if ($TempCopy -and $PSCommandPath) { Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue }
