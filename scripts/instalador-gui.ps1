
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $script:Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = $script:Utf8NoBomEncoding
} catch {
    $script:Utf8NoBomEncoding = [System.Text.Encoding]::UTF8
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$script:OutputBaseFolder = $env:FOROACTIVO_INSTALLER_OUTPUT_BASE_DIR
if ([string]::IsNullOrWhiteSpace($script:OutputBaseFolder)) {
    $script:OutputBaseFolder = $root
}
$script:OutputFolder = $env:FOROACTIVO_INSTALLER_OUTPUT_DIR
if ([string]::IsNullOrWhiteSpace($script:OutputFolder)) {
    $script:OutputFolder = Join-Path $root "_installer_bootstrap"
}
try {
    if (-not (Test-Path $script:OutputFolder)) {
        New-Item -ItemType Directory -Path $script:OutputFolder -Force | Out-Null
    }
} catch {}
$script:LogPath = Join-Path $script:OutputFolder "INSTALADOR_FOROACTIVO_LOG.txt"
try {
    Set-Content -LiteralPath $script:LogPath -Value ("Inicio del instalador: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8
} catch {}
$script:InstallerProcessIds = New-Object System.Collections.Generic.List[int]
$script:InstallerIsClosing = $false
$script:CloudflareWhoamiOutput = ""
$script:LastCloudflareAuthOpenAt = [DateTime]::MinValue
$script:CloudflareAuthOpenWindowSeconds = 90
$script:InstalledDataLoaded = $false

function Get-DialogButtonText([string]$buttonKey) {
    $texts = @{
        "ES" = @{ "OK" = "Aceptar"; "Yes" = "Sí"; "No" = "No" }
        "EN" = @{ "OK" = "OK"; "Yes" = "Yes"; "No" = "No" }
        "PT" = @{ "OK" = "Aceitar"; "Yes" = "Sim"; "No" = "Não" }
        "IT" = @{ "OK" = "Conferma"; "Yes" = "Sì"; "No" = "No" }
        "RU" = @{ "OK" = "ОК"; "Yes" = "Да"; "No" = "Нет" }
        "FR" = @{ "OK" = "Valider"; "Yes" = "Oui"; "No" = "Non" }
        "DE" = @{ "OK" = "Bestätigen"; "Yes" = "Ja"; "No" = "Nein" }
        "RO" = @{ "OK" = "Confirmă"; "Yes" = "Da"; "No" = "Nu" }
        "NL" = @{ "OK" = "OK"; "Yes" = "Ja"; "No" = "Nee" }
    }

    $lang = $script:CurrentLanguage
    if ([string]::IsNullOrWhiteSpace($lang) -or -not $texts.ContainsKey($lang)) {
        $lang = "ES"
    }
    return $texts[$lang][$buttonKey]
}

function Get-DialogTitleText([string]$titleKey) {
    $texts = @{
        "ES" = @{ "Error" = "Error"; "Info" = "Información"; "Warning" = "Aviso" }
        "EN" = @{ "Error" = "Error"; "Info" = "Information"; "Warning" = "Warning" }
        "PT" = @{ "Error" = "Erro"; "Info" = "Informação"; "Warning" = "Aviso" }
        "IT" = @{ "Error" = "Errore"; "Info" = "Informazione"; "Warning" = "Avviso" }
        "RU" = @{ "Error" = "Ошибка"; "Info" = "Информация"; "Warning" = "Предупреждение" }
        "FR" = @{ "Error" = "Erreur"; "Info" = "Information"; "Warning" = "Avertissement" }
        "DE" = @{ "Error" = "Fehler"; "Info" = "Information"; "Warning" = "Warnung" }
        "RO" = @{ "Error" = "Eroare"; "Info" = "Informații"; "Warning" = "Avertisment" }
        "NL" = @{ "Error" = "Fout"; "Info" = "Informatie"; "Warning" = "Waarschuwing" }
    }

    $lang = $script:CurrentLanguage
    if ([string]::IsNullOrWhiteSpace($lang) -or -not $texts.ContainsKey($lang)) {
        $lang = "ES"
    }
    return $texts[$lang][$titleKey]
}

function Show-AppDialog(
    [string]$message,
    [string]$title,
    [ValidateSet("OK", "YesNo")] [string]$buttons = "OK",
    [ValidateSet("Information", "Warning", "Error")] [string]$icon = "Information",
    [System.Windows.Forms.Form]$owner = $null
) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $title
    $dialog.StartPosition = "CenterParent"
    $dialog.ClientSize = New-Object System.Drawing.Size(560, 230)
    $dialog.MinimumSize = New-Object System.Drawing.Size(520, 220)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.BackColor = [System.Drawing.Color]::White
    $dialog.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    if ($script:UiSurface) {
        $dialog.BackColor = $script:UiSurface
    }
    if ($script:UiText) {
        $dialog.ForeColor = $script:UiText
    }
    if ($iconPath -and (Test-Path $iconPath)) {
        try { $dialog.Icon = New-Object System.Drawing.Icon($iconPath) } catch {}
    }

    $systemIcon = switch ($icon) {
        "Error" { [System.Drawing.SystemIcons]::Error }
        "Warning" { [System.Drawing.SystemIcons]::Warning }
        default { [System.Drawing.SystemIcons]::Information }
    }

    $iconBox = New-Object System.Windows.Forms.PictureBox
    $iconBox.Image = $systemIcon.ToBitmap()
    $iconBox.Location = New-Object System.Drawing.Point(28, 38)
    $iconBox.Size = New-Object System.Drawing.Size(48, 48)
    $iconBox.SizeMode = "CenterImage"
    $dialog.Controls.Add($iconBox)

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Text = $message
    $messageLabel.Location = New-Object System.Drawing.Point(96, 28)
    $messageLabel.Size = New-Object System.Drawing.Size(430, 118)
    $messageLabel.AutoEllipsis = $true
    $messageLabel.ForeColor = if ($script:UiText) { $script:UiText } else { [System.Drawing.Color]::FromArgb(27, 39, 53) }
    $dialog.Controls.Add($messageLabel)

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = "Bottom"
    $footer.Height = 70
    $footer.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)
    $dialog.Controls.Add($footer)

    $result = [System.Windows.Forms.DialogResult]::None
    if ($buttons -eq "YesNo") {
        $yesButton = New-Object System.Windows.Forms.Button
        $yesButton.Text = Get-DialogButtonText "Yes"
        $yesButton.Size = New-Object System.Drawing.Size(104, 34)
        $yesButton.Location = New-Object System.Drawing.Point(320, 18)
        $yesButton.FlatStyle = "Flat"
        if ($script:UiBlue) {
            $yesButton.BackColor = $script:UiBlue
            $yesButton.ForeColor = [System.Drawing.Color]::White
            $yesButton.FlatAppearance.BorderSize = 0
        }
        $yesButton.Add_Click({
            $script:DialogResultValue = [System.Windows.Forms.DialogResult]::Yes
            $dialog.Close()
        })
        $footer.Controls.Add($yesButton)

        $noButton = New-Object System.Windows.Forms.Button
        $noButton.Text = Get-DialogButtonText "No"
        $noButton.Size = New-Object System.Drawing.Size(104, 34)
        $noButton.Location = New-Object System.Drawing.Point(438, 18)
        $noButton.FlatStyle = "Flat"
        $noButton.Add_Click({
            $script:DialogResultValue = [System.Windows.Forms.DialogResult]::No
            $dialog.Close()
        })
        $footer.Controls.Add($noButton)
        $dialog.AcceptButton = $yesButton
        $dialog.CancelButton = $noButton
    }
    else {
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = Get-DialogButtonText "OK"
        $okButton.Size = New-Object System.Drawing.Size(112, 34)
        $okButton.Location = New-Object System.Drawing.Point(420, 18)
        $okButton.FlatStyle = "Flat"
        if ($script:UiBlue) {
            $okButton.BackColor = $script:UiBlue
            $okButton.ForeColor = [System.Drawing.Color]::White
            $okButton.FlatAppearance.BorderSize = 0
        }
        $okButton.Add_Click({
            $script:DialogResultValue = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        })
        $footer.Controls.Add($okButton)
        $dialog.AcceptButton = $okButton
        $dialog.CancelButton = $okButton
    }

    $script:DialogResultValue = [System.Windows.Forms.DialogResult]::None
    if ($owner) {
        [void]$dialog.ShowDialog($owner)
    }
    else {
        [void]$dialog.ShowDialog()
    }
    $result = $script:DialogResultValue
    $script:DialogResultValue = [System.Windows.Forms.DialogResult]::None
    return $result
}

function Show-Error([string]$message) {
    Show-AppDialog $message (Get-DialogTitleText "Error") "OK" "Error" | Out-Null
}

function Show-Info([string]$message) {
    Show-AppDialog $message (Get-DialogTitleText "Info") "OK" "Information" | Out-Null
}

function Show-InstallationResult([string]$workerUrl, [string]$installFolder) {
    $resultForm = New-Object System.Windows.Forms.Form
    $resultForm.Text = Get-UiText "resultTitle"
    $resultForm.StartPosition = "CenterParent"
    $resultForm.ClientSize = New-Object System.Drawing.Size(720, 420)
    $resultForm.MinimumSize = New-Object System.Drawing.Size(720, 420)
    $resultForm.BackColor = [System.Drawing.Color]::White
    $resultForm.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    if (Test-Path $iconPath) {
        try {
            $resultForm.Icon = New-Object System.Drawing.Icon($iconPath)
        } catch {}
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = Get-UiText "resultTitle"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(0, 91, 156)
    $title.Location = New-Object System.Drawing.Point(24, 22)
    $title.Size = New-Object System.Drawing.Size(650, 34)
    $resultForm.Controls.Add($title)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = Get-UiText "resultIntro"
    $intro.Location = New-Object System.Drawing.Point(28, 70)
    $intro.Size = New-Object System.Drawing.Size(650, 48)
    $intro.ForeColor = [System.Drawing.Color]::FromArgb(27, 39, 53)
    $resultForm.Controls.Add($intro)

    $urlLabel = New-Object System.Windows.Forms.Label
    $urlLabel.Text = Get-UiText "resultUrlLabel"
    $urlLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $urlLabel.Location = New-Object System.Drawing.Point(28, 132)
    $urlLabel.AutoSize = $true
    $resultForm.Controls.Add($urlLabel)

    $urlBox = New-Object System.Windows.Forms.TextBox
    $urlBox.Text = $workerUrl
    $urlBox.ReadOnly = $true
    $urlBox.Location = New-Object System.Drawing.Point(28, 158)
    $urlBox.Size = New-Object System.Drawing.Size(510, 28)
    $urlBox.BorderStyle = "FixedSingle"
    $resultForm.Controls.Add($urlBox)

    $copyButton = New-Object System.Windows.Forms.Button
    $copyButton.Text = Get-UiText "copyUrl"
    $copyButton.Location = New-Object System.Drawing.Point(554, 156)
    $copyButton.Size = New-Object System.Drawing.Size(120, 32)
    $copyButton.BackColor = [System.Drawing.Color]::FromArgb(0, 119, 199)
    $copyButton.ForeColor = [System.Drawing.Color]::White
    $copyButton.FlatStyle = "Flat"
    $copyButton.FlatAppearance.BorderSize = 0
    $resultForm.Controls.Add($copyButton)

    $warning = New-Object System.Windows.Forms.Label
    $warning.Text = Get-UiText "resultWarning"
    $warning.Location = New-Object System.Drawing.Point(28, 205)
    $warning.Size = New-Object System.Drawing.Size(646, 42)
    $warning.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
    $warning.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
    $resultForm.Controls.Add($warning)

    $filesText = New-Object System.Windows.Forms.Label
    $filesText.Text = Get-UiText "resultFiles"
    $filesText.Location = New-Object System.Drawing.Point(28, 262)
    $filesText.Size = New-Object System.Drawing.Size(646, 58)
    $filesText.ForeColor = [System.Drawing.Color]::FromArgb(83, 96, 112)
    $resultForm.Controls.Add($filesText)

    $openFolderButton = New-Object System.Windows.Forms.Button
    $openFolderButton.Text = Get-UiText "openFiles"
    $openFolderButton.Location = New-Object System.Drawing.Point(28, 342)
    $openFolderButton.Size = New-Object System.Drawing.Size(220, 38)
    $openFolderButton.BackColor = [System.Drawing.Color]::FromArgb(0, 119, 199)
    $openFolderButton.ForeColor = [System.Drawing.Color]::White
    $openFolderButton.FlatStyle = "Flat"
    $openFolderButton.FlatAppearance.BorderSize = 0
    $resultForm.Controls.Add($openFolderButton)

    $closeResult = New-Object System.Windows.Forms.Button
    $closeResult.Text = Get-UiText "finish"
    $closeResult.Location = New-Object System.Drawing.Point(554, 342)
    $closeResult.Size = New-Object System.Drawing.Size(120, 38)
    $closeResult.FlatStyle = "Flat"
    $closeResult.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(211, 220, 230)
    $resultForm.Controls.Add($closeResult)

    $copyButton.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($urlBox.Text)) {
            [System.Windows.Forms.Clipboard]::SetText($urlBox.Text)
            $copyButton.Text = Get-UiText "urlCopied"
        }
    })

    $openFolderButton.Add_Click({
        if (Test-Path $installFolder) {
            Start-Process explorer.exe $installFolder
        }
    })

    $closeResult.Add_Click({
        $resultForm.Close()
    })

    [void]$resultForm.ShowDialog($form)
}

function Append-Log([string]$message) {
    $logBox.AppendText($message + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    try {
        Add-Content -LiteralPath $script:LogPath -Value $message -Encoding UTF8
    } catch {}
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-LogText([string]$key) {
    $texts = @{
        "ES" = @{
            "nodeAlreadyPrepared" = "Node.js LTS ya se preparó durante esta ejecución."
            "preparingNodeLts" = "Preparando Node.js LTS automáticamente..."
            "wingetMissing" = "No se encontró Windows Package Manager (winget). Instala Node.js LTS manualmente y vuelve a ejecutar el instalador."
            "nodePathMissing" = "Node.js se instaló, pero Windows todavía no reconoce las rutas. Reinicia Windows y vuelve a ejecutar el instalador."
            "nodePrepared" = "Node.js LTS preparado correctamente."
            "nodeMissing" = "Node.js no está instalado."
            "nodeDetected" = "Node.js detectado: {0}"
            "existingNodeKept" = "Node.js ya está disponible. Se usará la instalación existente."
            "forceLts" = "Se forzará el paquete Node.js LTS para evitar versiones no estables o instalaciones dañadas."
            "repairLts" = "Reparando o cambiando Node.js a LTS aunque ya exista una instalación previa."
            "npmMissing" = "Node.js está instalado, pero npm o npx no están disponibles. Repara o reinstala Node.js LTS."
            "npmDetected" = "npm detectado: {0}"
            "npxDetected" = "npx detectado: {0}"
            "projectNameInvalid" = "El nombre técnico del proyecto debe contener al menos una letra o número. Usa un nombre como scheduler o theme-programmer."
            "projectNameNormalized" = "Nombre técnico normalizado para Cloudflare: {0} -> {1}"
            "projectNameWarningTitle" = "Nombre técnico del Worker corregido"
            "projectNameWarning" = "Cloudflare Worker solo acepta nombres técnicos en minúsculas, números y guiones. El instalador cambiará '{0}' por '{1}' para evitar el error de Wrangler. Ejemplos válidos: scheduler, theme-programmer, foroactivo-scheduler."
            "preparingDeps" = "Preparando dependencias..."
            "cloudflareSession" = "Comprobando sesión de Cloudflare..."
            "cloudflareLogin" = "Se abrirá el navegador para autorizar Cloudflare..."
            "deployWorker" = "Publicando el Worker..."
            "preparingD1" = "Preparando base de datos D1..."
            "d1Found" = "D1 existente encontrada: {0}"
            "d1Creating" = "Creando nueva D1: {0} en jurisdicción EU"
            "d1Created" = "D1 creada y vinculada: {0}"
            "d1LimitReached" = "Cloudflare indica que la cuenta autenticada en Wrangler ya alcanzó el máximo de bases D1. Borrar el Worker no borra necesariamente las bases D1: revisa Cloudflare en Storage & Databases > D1, no solo Workers. Si allí no aparece ninguna D1, comprueba que Wrangler esté conectado a la misma cuenta de Cloudflare y espera unos minutos por si Cloudflare aún no liberó la cuota. No se ha publicado nada para evitar una instalación incompleta."
            "d1NoneFound" = "Wrangler no ha encontrado una D1 existente con ese nombre. Se intentará crear una nueva."
            "d1Retry" = "Cloudflare D1 ha tardado demasiado. Reintentando operación D1 ({0}/{1}) en {2} segundos..."
            "d1RetryFinal" = "Cloudflare D1 sigue agotando el tiempo tras varios intentos. Vuelve a ejecutar el instalador dentro de unos minutos; si el Worker y la D1 ya se crearon, usa Mantenimiento para guardar foros y cuentas."
            "d1Migrations" = "Aplicando migraciones de D1..."
            "migrationConfirm" = "La confirmación de la migración se responderá automáticamente."
            "savingSecrets" = "Guardando secretos..."
            "deployFinal" = "Publicando la configuración final..."
            "installDoneLog" = "INSTALACIÓN TERMINADA"
            "updateDoneLog" = "ACTUALIZACIÓN TERMINADA"
            "errorPrefix" = "ERROR: "
        }
        "EN" = @{
            "nodeAlreadyPrepared" = "Node.js LTS has already been prepared during this run."
            "preparingNodeLts" = "Preparing Node.js LTS automatically..."
            "wingetMissing" = "Windows Package Manager (winget) was not found. Install Node.js LTS manually and run the installer again."
            "nodePathMissing" = "Node.js was installed, but Windows still does not recognize the paths. Restart Windows and run the installer again."
            "nodePrepared" = "Node.js LTS prepared successfully."
            "nodeMissing" = "Node.js is not installed."
            "nodeDetected" = "Node.js detected: {0}"
            "existingNodeKept" = "Node.js is already available. The existing installation will be used."
            "forceLts" = "The Node.js LTS package will be forced to avoid unstable versions or damaged installations."
            "repairLts" = "Repairing or switching Node.js to LTS even though a previous installation exists."
            "npmMissing" = "Node.js is installed, but npm or npx are not available. Repair or reinstall Node.js LTS."
            "npmDetected" = "npm detected: {0}"
            "npxDetected" = "npx detected: {0}"
            "projectNameInvalid" = "The technical project name must contain at least one letter or number. Use a name like scheduler or theme-programmer."
            "projectNameNormalized" = "Technical name normalized for Cloudflare: {0} -> {1}"
            "projectNameWarningTitle" = "Worker technical name corrected"
            "projectNameWarning" = "Cloudflare Worker only accepts technical names with lowercase letters, numbers and hyphens. The installer will change '{0}' to '{1}' to avoid the Wrangler error. Valid examples: scheduler, theme-programmer, forumotion-scheduler."
            "preparingDeps" = "Preparing dependencies..."
            "cloudflareSession" = "Checking Cloudflare session..."
            "cloudflareLogin" = "The browser will open to authorize Cloudflare..."
            "deployWorker" = "Deploying the Worker..."
            "preparingD1" = "Preparing D1 database..."
            "d1Found" = "Existing D1 database found: {0}"
            "d1Creating" = "Creating new D1 database: {0} in EU jurisdiction"
            "d1Created" = "D1 database created and linked: {0}"
            "d1LimitReached" = "Cloudflare says the account authenticated in Wrangler has reached the maximum number of D1 databases. Deleting the Worker does not necessarily delete D1 databases: check Cloudflare under Storage & Databases > D1, not only Workers. If no D1 database appears there, verify that Wrangler is connected to the same Cloudflare account and wait a few minutes in case Cloudflare has not released the quota yet. Nothing was deployed to avoid an incomplete installation."
            "d1NoneFound" = "Wrangler did not find an existing D1 database with that name. A new one will be created."
            "d1Retry" = "Cloudflare D1 took too long. Retrying D1 operation ({0}/{1}) in {2} seconds..."
            "d1RetryFinal" = "Cloudflare D1 is still timing out after several attempts. Run the installer again in a few minutes; if the Worker and D1 were already created, use Maintenance to save forums and accounts."
            "d1Migrations" = "Applying D1 migrations..."
            "migrationConfirm" = "Migration confirmation will be answered automatically."
            "savingSecrets" = "Saving secrets..."
            "deployFinal" = "Deploying final configuration..."
            "installDoneLog" = "INSTALLATION FINISHED"
            "updateDoneLog" = "UPDATE FINISHED"
            "errorPrefix" = "ERROR: "
        }
    }

    $lang = $script:CurrentLanguage
    if (-not $texts.ContainsKey($lang)) { $lang = "EN" }
    if ($texts[$lang].ContainsKey($key)) { return $texts[$lang][$key] }
    return $texts["EN"][$key]
}

function Set-InstallStep([int]$number, [string]$text, [string]$state = "working") {
    $symbols = @{
        "waiting" = "○"
        "working" = "●"
        "ok" = "✓"
        "error" = "✕"
    }

    if (-not $stepsList -or $number -lt 1 -or $number -gt $stepsList.Items.Count) {
        return
    }

    $item = $stepsList.Items[$number - 1]
    $item.SubItems[0].Text = $symbols[$state]
    $item.SubItems[1].Text = $text

    if ($state -eq "ok") {
        $item.ForeColor = [System.Drawing.Color]::FromArgb(22, 128, 62)
    }
    elseif ($state -eq "error") {
        $item.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
    }
    elseif ($state -eq "working") {
        $item.ForeColor = $script:UiBlue
    }
    else {
        $item.ForeColor = $script:UiMuted
    }

    $installProgress.Value = [Math]::Min(
        100,
        [Math]::Max(0, [int](($number - 1) * 100 / $stepsList.Items.Count))
    )
    $progressTitle.Text = $text
    [System.Windows.Forms.Application]::DoEvents()
}

function Complete-InstallStep([int]$number, [string]$text) {
    Set-InstallStep $number $text "ok"
    if ($stepsList) {
        $installProgress.Value = [Math]::Min(
            100,
            [int]($number * 100 / $stepsList.Items.Count)
        )
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Reset-InstallProgress {
    if (-not $stepsList) { return }

    for ($i = 0; $i -lt $stepsList.Items.Count; $i++) {
        $stepsList.Items[$i].SubItems[0].Text = "○"
        $stepsList.Items[$i].ForeColor = $script:UiMuted
    }

    $installProgress.Value = 0
    $progressTitle.Text = Get-UiText "ready"
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-ProgressStepList([string[]]$names, [string]$title) {
    if (-not $stepsList) { return }

    $stepsList.Items.Clear()

    foreach ($stepName in $names) {
        $item = New-Object System.Windows.Forms.ListViewItem("○")
        $item.SubItems.Add($stepName) | Out-Null
        $item.ForeColor = $script:UiMuted
        $stepsList.Items.Add($item) | Out-Null
    }

    $installProgress.Value = 0
    $progressTitle.Text = $title
    [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
    $userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
    $env:Path = $machinePath + ";" + $userPath
}

function Resolve-Executable([string[]]$names) {
    foreach ($name in $names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    return $null
}

function Install-NodeAutomatically([string]$reason = "") {
    if ($script:NodeLtsPrepared) {
        Append-Log(Get-LogText "nodeAlreadyPrepared")
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        Append-Log($reason)
    }
    Append-Log(Get-LogText "preparingNodeLts")

    $winget = Resolve-Executable @("winget.exe", "winget")
    if (-not $winget) {
        throw (Get-LogText "wingetMissing")
    }

    Run-Command $winget ("install --id OpenJS.NodeJS.LTS --exact " +
                         "--accept-package-agreements --accept-source-agreements " +
                         "--silent --disable-interactivity")

    Refresh-Path
    Start-Sleep -Seconds 2

    $script:NodeCommand = Resolve-Executable @("node.exe", "node")
    $script:NpmCommand = Resolve-Executable @("npm.cmd", "npm.exe", "npm")
    $script:NpxCommand = Resolve-Executable @("npx.cmd", "npx.exe", "npx")

    if (-not $script:NodeCommand -or -not $script:NpmCommand -or -not $script:NpxCommand) {
        throw (Get-LogText "nodePathMissing")
    }
    $script:NodeLtsPrepared = $true
    Append-Log(Get-LogText "nodePrepared")
}

function Ensure-NodeTools {
    Refresh-Path
    $script:NodeCommand = Resolve-Executable @("node.exe", "node")
    $script:NpmCommand = Resolve-Executable @("npm.cmd", "npm.exe", "npm")
    $script:NpxCommand = Resolve-Executable @("npx.cmd", "npx.exe", "npx")

    if (-not $script:NodeCommand) {
        Install-NodeAutomatically (Get-LogText "nodeMissing")
    }

    Refresh-Path
    $script:NodeCommand = Resolve-Executable @("node.exe", "node")
    $script:NpmCommand = Resolve-Executable @("npm.cmd", "npm.exe", "npm")
    $script:NpxCommand = Resolve-Executable @("npx.cmd", "npx.exe", "npx")

    if (-not $script:NpmCommand -or -not $script:NpxCommand) {
        Install-NodeAutomatically (Get-LogText "npmMissing")
        Refresh-Path
        $script:NodeCommand = Resolve-Executable @("node.exe", "node")
        $script:NpmCommand = Resolve-Executable @("npm.cmd", "npm.exe", "npm")
        $script:NpxCommand = Resolve-Executable @("npx.cmd", "npx.exe", "npx")
    }

    if (-not $script:NodeCommand -or -not $script:NpmCommand -or -not $script:NpxCommand) {
        throw (Get-LogText "nodePathMissing")
    }

    Append-Log(([string]::Format((Get-LogText "nodeDetected"), $script:NodeCommand)))
    Append-Log(([string]::Format((Get-LogText "npmDetected"), $script:NpmCommand)))
    Append-Log(([string]::Format((Get-LogText "npxDetected"), $script:NpxCommand)))
    if (-not $script:NodeLtsPrepared) {
        Append-Log(Get-LogText "existingNodeKept")
    }
}


function Remove-ConsoleControlSequences([string]$text) {
    if ($null -eq $text) { return "" }

    $escape = [string][char]27
    return [Regex]::Replace($text, "$escape\[[0-?]*[ -/]*[@-~]", "")
}

function Register-InstallerProcess([int]$processId) {
    if ($processId -le 0) { return }
    if (-not $script:InstallerProcessIds.Contains($processId)) {
        $script:InstallerProcessIds.Add($processId)
    }
}

function Get-ChildProcessIds([int[]]$parentIds) {
    $found = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]

    foreach ($parentId in @($parentIds)) {
        if ($parentId -gt 0) {
            $queue.Enqueue($parentId)
        }
    }

    while ($queue.Count -gt 0) {
        $currentParent = $queue.Dequeue()

        try {
            $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$currentParent" -ErrorAction SilentlyContinue
        } catch {
            $children = @()
        }

        foreach ($child in @($children)) {
            $childId = [int]$child.ProcessId
            if ($childId -le 0 -or $found.Contains($childId)) { continue }

            $found.Add($childId)
            $queue.Enqueue($childId)
        }
    }

    return @($found)
}

function Stop-InstallerProcessTree([int]$processId) {
    if ($processId -le 0) { return }

    $childIds = @(Get-ChildProcessIds @($processId))
    foreach ($childId in ($childIds | Sort-Object -Descending)) {
        try {
            Stop-Process -Id $childId -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    try {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Stop-InstallerChildProcesses {
    $ids = @($script:InstallerProcessIds | Select-Object -Unique)
    foreach ($processId in $ids) {
        Stop-InstallerProcessTree $processId
    }

    Stop-InstallerRelatedNodeProcesses
}

function Stop-InstallerRelatedNodeProcesses {
    $rootPattern = [Regex]::Escape([string]$root)
    $runtimePattern = "\.foroactivo_installer_runtime"

    try {
        $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessId -ne $PID -and
                $_.Name -in @("node.exe", "cmd.exe", "npm.cmd", "npx.cmd") -and
                (
                    ([string]$_.CommandLine -match $rootPattern) -or
                    ([string]$_.CommandLine -match $runtimePattern) -or
                    ([string]$_.CommandLine -match "(?i)\bwrangler\b")
                )
            }

        foreach ($process in @($processes)) {
            try {
                Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    } catch {}
}

function Run-Command([string]$file, [string]$arguments, [string]$inputText = "") {
    Append-Log("> $file $arguments")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8"
    $psi.EnvironmentVariables["NO_COLOR"] = "1"
    $psi.EnvironmentVariables["FORCE_COLOR"] = "0"

    try {
        $psi.StandardOutputEncoding = $script:Utf8NoBomEncoding
        $psi.StandardErrorEncoding = $script:Utf8NoBomEncoding
    } catch {}

    try {
        $psi.StandardInputEncoding = $script:Utf8NoBomEncoding
    } catch {}

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $processOutput = New-Object Text.StringBuilder

    $null = $process.Start()
    Register-InstallerProcess $process.Id

    if ($inputText -ne "") {
        $process.StandardInput.WriteLine($inputText)
        $process.StandardInput.Close()
    }

    while (-not $process.HasExited) {
        if ($script:InstallerIsClosing) {
            Stop-InstallerProcessTree $process.Id
            try {
                [void]$process.WaitForExit(1500)
            } catch {}
            break
        }

        while (-not $process.StandardOutput.EndOfStream) {
            $line = Remove-ConsoleControlSequences ($process.StandardOutput.ReadLine())
            Append-Log($line)
            $null = $processOutput.AppendLine($line)
        }

        while (-not $process.StandardError.EndOfStream) {
            $line = Remove-ConsoleControlSequences ($process.StandardError.ReadLine())
            Append-Log($line)
            $null = $processOutput.AppendLine($line)
        }

        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.Application]::DoEvents()
    }

    while (-not $process.StandardOutput.EndOfStream) {
        $line = Remove-ConsoleControlSequences ($process.StandardOutput.ReadLine())
        Append-Log($line)
        $null = $processOutput.AppendLine($line)
    }

    while (-not $process.StandardError.EndOfStream) {
        $line = Remove-ConsoleControlSequences ($process.StandardError.ReadLine())
        Append-Log($line)
        $null = $processOutput.AppendLine($line)
    }

    if ($script:InstallerIsClosing) {
        return $processOutput.ToString()
    }

    if ($process.ExitCode -ne 0) {
        $fullOutput = $processOutput.ToString()
        $outputLines = $fullOutput -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $lastOutput = ($outputLines | Select-Object -Last 12) -join [Environment]::NewLine

        $message = (
            "El comando falló con código $($process.ExitCode)." +
            [Environment]::NewLine +
            [Environment]::NewLine +
            "Comando:" + [Environment]::NewLine +
            "$file $arguments" +
            [Environment]::NewLine +
            [Environment]::NewLine
        )

        if (-not [string]::IsNullOrWhiteSpace($lastOutput)) {
            $message += (
                "Última salida del comando:" +
                [Environment]::NewLine +
                $lastOutput +
                [Environment]::NewLine +
                [Environment]::NewLine
            )
        }

        if ($fullOutput -match "workers/onboarding" -or
            $fullOutput -match "register a workers\.dev subdomain") {
            $message = "WORKERS_DEV_SUBDOMAIN_MISSING" +
                [Environment]::NewLine +
                [Environment]::NewLine +
                $fullOutput +
                [Environment]::NewLine +
                [Environment]::NewLine +
                (Get-UiText "logComplete") + ": $script:LogPath"
            throw $message
        }

        if ($lastOutput -match "Timed out waiting for authorization code" -or
            $lastOutput -match "localhost:\d+" -or
            $lastOutput -match "authorization code") {
            $message =
                (Get-UiText "cloudflareAuthFailed") +
                [Environment]::NewLine +
                [Environment]::NewLine +
                (Get-UiText "logComplete") + ": $script:LogPath"
            throw $message
        }

        if ($process.ExitCode -eq -1073740791) {
            $message += (
                "Ese código suele indicar un bloqueo nativo de Windows en el programa ejecutado. " +
                "Si ocurre usando npm/npx/wrangler, instala o repara Node.js LTS y vuelve a ejecutar el instalador." +
                [Environment]::NewLine +
                [Environment]::NewLine
            )
        }

        $message += "Log completo: $script:LogPath"
        throw $message
    }

    return $processOutput.ToString()
}

function Show-CloudflareBrowserSwitchStep {
    Show-AppDialog `
        (Get-UiText "cloudflareSwitchAccountMessage") `
        (Get-UiText "cloudflareSwitchAccountTitle") `
        "OK" `
        "Information" | Out-Null
}

function Get-DefaultBrowserExecutable {
    try {
        $userChoice = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice" -ErrorAction Stop
        $progId = [string]$userChoice.ProgId
        if ([string]::IsNullOrWhiteSpace($progId)) { return "" }

        $commandPath = "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command"
        $command = (Get-ItemProperty -Path $commandPath -ErrorAction Stop)."(default)"
        if ([string]::IsNullOrWhiteSpace($command)) { return "" }

        $match = [Regex]::Match($command, '"(?<path>[^"]+\.exe)"|(?<path>[A-Za-z]:\\[^\s]+\.exe)')
        if ($match.Success -and (Test-Path -LiteralPath $match.Groups["path"].Value)) {
            return $match.Groups["path"].Value
        }
    } catch {}

    return ""
}

function Get-PrivateBrowserArguments([string]$browserPath, [string]$url) {
    $name = [IO.Path]::GetFileName($browserPath).ToLowerInvariant()
    $fullPath = ([string]$browserPath).ToLowerInvariant()

    switch ($name) {
        "msedge.exe"   { return @("--new-window", $url) }
        "chrome.exe"   { return @("--new-window", $url) }
        "brave.exe"    { return @("--new-window", $url) }
        "vivaldi.exe"  { return @("--new-window", $url) }
        "chromium.exe" { return @("--new-window", $url) }
        "firefox.exe"  { return @("-new-window", $url) }
        "librewolf.exe" { return @("-new-window", $url) }
        "waterfox.exe" { return @("-new-window", $url) }
        "palemoon.exe" { return @("-new-window", $url) }
        "opera.exe"    { return @("--new-window", $url) }
        "launcher.exe" {
            if ($fullPath -match "opera") {
                return @("--new-window", $url)
            }
        }
    }

    return $null
}

function Join-OptionalPath([string]$basePath, [string]$childPath) {
    if ([string]::IsNullOrWhiteSpace($basePath)) { return "" }
    return (Join-Path $basePath $childPath)
}

function Get-PrivateBrowserCandidates {
    $programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)

    $paths = New-Object System.Collections.Generic.List[string]
    $defaultBrowser = Get-DefaultBrowserExecutable
    if (-not [string]::IsNullOrWhiteSpace($defaultBrowser)) {
        $paths.Add($defaultBrowser)
    }

    foreach ($path in @(
        (Join-OptionalPath $programFiles "Microsoft\Edge\Application\msedge.exe"),
        (Join-OptionalPath $programFilesX86 "Microsoft\Edge\Application\msedge.exe"),
        (Join-OptionalPath $programFiles "Google\Chrome\Application\chrome.exe"),
        (Join-OptionalPath $programFilesX86 "Google\Chrome\Application\chrome.exe"),
        (Join-OptionalPath $localAppData "Google\Chrome\Application\chrome.exe"),
        (Join-OptionalPath $programFiles "Mozilla Firefox\firefox.exe"),
        (Join-OptionalPath $programFilesX86 "Mozilla Firefox\firefox.exe"),
        (Join-OptionalPath $localAppData "Mozilla Firefox\firefox.exe"),
        (Join-OptionalPath $programFiles "BraveSoftware\Brave-Browser\Application\brave.exe"),
        (Join-OptionalPath $programFilesX86 "BraveSoftware\Brave-Browser\Application\brave.exe"),
        (Join-OptionalPath $localAppData "BraveSoftware\Brave-Browser\Application\brave.exe"),
        (Join-OptionalPath $programFiles "Vivaldi\Application\vivaldi.exe"),
        (Join-OptionalPath $programFilesX86 "Vivaldi\Application\vivaldi.exe"),
        (Join-OptionalPath $localAppData "Vivaldi\Application\vivaldi.exe"),
        (Join-OptionalPath $localAppData "Programs\Opera\launcher.exe"),
        (Join-OptionalPath $localAppData "Programs\Opera GX\launcher.exe"),
        (Join-OptionalPath $programFiles "Opera\launcher.exe"),
        (Join-OptionalPath $programFiles "Opera GX\launcher.exe"),
        (Join-OptionalPath $programFiles "LibreWolf\librewolf.exe"),
        (Join-OptionalPath $programFilesX86 "LibreWolf\librewolf.exe"),
        (Join-OptionalPath $localAppData "LibreWolf\librewolf.exe"),
        (Join-OptionalPath $programFiles "Waterfox\waterfox.exe"),
        (Join-OptionalPath $programFilesX86 "Waterfox\waterfox.exe"),
        (Join-OptionalPath $programFiles "Chromium\Application\chrome.exe"),
        (Join-OptionalPath $programFilesX86 "Chromium\Application\chrome.exe")
    )) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $paths.Add($path)
        }
    }

    return @(
        $paths |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } |
            Select-Object -Unique
    )
}

function Open-CloudflareLoginUrl([string]$url) {
    $secondsSinceLastOpen = ([DateTime]::UtcNow - $script:LastCloudflareAuthOpenAt).TotalSeconds
    if ($secondsSinceLastOpen -lt $script:CloudflareAuthOpenWindowSeconds) {
        Append-Log("Cloudflare authorization window was already opened recently. Ignoring repeated authorization URL.")
        return
    }

    foreach ($browserPath in (Get-PrivateBrowserCandidates)) {
        $arguments = Get-PrivateBrowserArguments $browserPath $url
        if ($null -eq $arguments) { continue }

        try {
            $browserProcess = Start-Process -FilePath $browserPath -ArgumentList $arguments -PassThru
            if ($null -ne $browserProcess) {
                Register-InstallerProcess $browserProcess.Id
            }
            $script:LastCloudflareAuthOpenAt = [DateTime]::UtcNow
            Append-Log("Opened Cloudflare authorization in the normal browser profile: $browserPath")
            return
        } catch {
            Append-Log("Could not open browser '$browserPath': $($_.Exception.Message)")
        }
    }

    throw (Get-UiText "cloudflareNoPrivateBrowser")
}


function Stop-ProcessUsingTcpPort([int]$port) {
    try {
        $connections = @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue)
        foreach ($connection in $connections) {
            $processId = [int]$connection.OwningProcess
            if ($processId -le 0 -or $processId -eq $PID) { continue }

            try {
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($null -eq $process) { continue }

                if ($process.ProcessName -match "^(node|npx|npm|cmd|powershell|pwsh)$") {
                    Append-Log("Closing previous local callback process on port ${port}: $($process.ProcessName) [$processId]")
                    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    } catch {}
}
function Invoke-WranglerLoginClean {
    Append-Log(Get-LogText "cloudflareLogin")
    Append-Log("Opening Cloudflare authorization in the normal browser profile.")

    Stop-ProcessUsingTcpPort 8976

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:NpxCommand
    $psi.Arguments = "wrangler login --browser=false"
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8"
    $psi.EnvironmentVariables["NO_COLOR"] = "1"
    $psi.EnvironmentVariables["FORCE_COLOR"] = "0"

    try {
        $psi.StandardOutputEncoding = $script:Utf8NoBomEncoding
        $psi.StandardErrorEncoding = $script:Utf8NoBomEncoding
    } catch {}

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $processOutput = New-Object Text.StringBuilder
    $openedBrowser = $false

    $null = $process.Start()
    Register-InstallerProcess $process.Id

    while (-not $process.HasExited) {
        if ($script:InstallerIsClosing) {
            Stop-InstallerProcessTree $process.Id
            try { [void]$process.WaitForExit(1500) } catch {}
            break
        }

        while (-not $process.StandardOutput.EndOfStream) {
            $line = Remove-ConsoleControlSequences ($process.StandardOutput.ReadLine())
            Append-Log($line)
            $null = $processOutput.AppendLine($line)

            if (-not $openedBrowser) {
                $match = [Regex]::Match($line, "https://dash\.cloudflare\.com/\S+")
                if ($match.Success) {
                    $openedBrowser = $true
                    Open-CloudflareLoginUrl $match.Value
                }
            }
        }

        while (-not $process.StandardError.EndOfStream) {
            $line = Remove-ConsoleControlSequences ($process.StandardError.ReadLine())
            Append-Log($line)
            $null = $processOutput.AppendLine($line)

            if (-not $openedBrowser) {
                $match = [Regex]::Match($line, "https://dash\.cloudflare\.com/\S+")
                if ($match.Success) {
                    $openedBrowser = $true
                    Open-CloudflareLoginUrl $match.Value
                }
            }
        }

        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.Application]::DoEvents()
    }

    $output = $processOutput.ToString()
    if (-not $script:InstallerIsClosing -and $process.ExitCode -ne 0) {
        throw (Get-UiText "cloudflarePrivateLoginFailed")
    }
}

function Invoke-CloudflareLogin([bool]$ForceNewSession = $false) {
    Append-Log(Get-LogText "cloudflareSession")

    if (-not $ForceNewSession -and
        -not [string]::IsNullOrWhiteSpace($script:CloudflareWhoamiOutput)) {
        Append-Log("Using Cloudflare Wrangler session already verified during this run.")
        return $script:CloudflareWhoamiOutput
    }

    if ($ForceNewSession) {
        Append-Log("New installation requested: closing any previous Wrangler session before authorization...")
        $script:CloudflareWhoamiOutput = ""
        try {
            Run-Command $script:NpxCommand "wrangler logout"
        } catch {
            Append-Log("No previous Wrangler session could be closed, or it was already closed.")
        }

    }
    else {
        try {
            $existingSession = Run-Command $script:NpxCommand "wrangler whoami"
            if (-not [string]::IsNullOrWhiteSpace($existingSession)) {
                $script:CloudflareWhoamiOutput = $existingSession
                Append-Log("Using existing Cloudflare Wrangler session.")
                return $existingSession
            }
        } catch {
            Append-Log("No active Wrangler session found. Authorization is required.")
        }
    }

    Invoke-WranglerLoginClean
    $script:CloudflareWhoamiOutput = Run-Command $script:NpxCommand "wrangler whoami"
    return $script:CloudflareWhoamiOutput
}
function Sql-Text([string]$value) {
    return "'" + $value.Replace("'", "''") + "'"
}

function Normalize-Key([string]$value) {
    $normalized = $value.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object Text.StringBuilder

    foreach ($char in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)

        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            $null = $builder.Append($char)
        }
    }

    $result = $builder.ToString().ToUpperInvariant()
    $result = [Regex]::Replace($result, "[^A-Z0-9]+", "_")
    $result = $result.Trim("_")

    return $result
}

function Normalize-ProjectName([string]$value) {
    $clean = $value.Trim().ToLowerInvariant()
    $clean = [Regex]::Replace($clean, "[^a-z0-9-]+", "-")
    $clean = [Regex]::Replace($clean, "-+", "-").Trim("-")
    return $clean
}

function Prompt-WorkersDevSubdomain([string]$suggestedName, [string]$lastError = "") {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-UiText "workersSubdomainTitle"
    $dialog.StartPosition = "CenterParent"
    $dialog.ClientSize = New-Object System.Drawing.Size(520, 230)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $dialog.BackColor = [System.Drawing.Color]::White

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(18, 18)
    $label.Size = New-Object System.Drawing.Size(480, 80)
    $label.Text = Get-UiText "workersSubdomainHelp"
    $dialog.Controls.Add($label)

    if (-not [string]::IsNullOrWhiteSpace($lastError)) {
        $errorLabel = New-Object System.Windows.Forms.Label
        $errorLabel.Location = New-Object System.Drawing.Point(18, 92)
        $errorLabel.Size = New-Object System.Drawing.Size(480, 36)
        $errorLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 30, 30)
        $errorLabel.Text = Get-UiText "workersSubdomainError"
        $dialog.Controls.Add($errorLabel)
    }

    $input = New-Object System.Windows.Forms.TextBox
    $input.Location = New-Object System.Drawing.Point(20, 135)
    $input.Size = New-Object System.Drawing.Size(475, 28)
    $input.Text = $suggestedName
    $dialog.Controls.Add($input)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = Get-UiText "startupContinue"
    $ok.Size = New-Object System.Drawing.Size(120, 34)
    $ok.Location = New-Object System.Drawing.Point(245, 180)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.AcceptButton = $ok
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = Get-DialogButtonText "No"
    $cancel.Size = New-Object System.Drawing.Size(120, 34)
    $cancel.Location = New-Object System.Drawing.Point(375, 180)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.CancelButton = $cancel
    $dialog.Controls.Add($cancel)

    $result = $dialog.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return ""
    }

    return Normalize-ProjectName $input.Text
}

function Register-WorkersDevSubdomain([string]$subdomain) {
    if ([string]::IsNullOrWhiteSpace($subdomain)) { return $false }

    Append-Log("Intentando registrar el subdominio workers.dev: $subdomain")
    try {
        Run-Command $script:NpxCommand "wrangler subdomain `"$subdomain`""
        Append-Log("Subdominio workers.dev registrado o ya disponible: $subdomain.workers.dev")
        return $true
    }
    catch {
        Append-Log("No se pudo registrar el subdominio workers.dev '$subdomain': $($_.Exception.Message)")
        return $false
    }
}

function Invoke-DeployWithWorkersDevSubdomain([string]$project) {
    try {
        return Run-Command $script:NpxCommand "wrangler deploy"
    }
    catch {
        $message = $_.Exception.Message
        if ($message -notmatch "WORKERS_DEV_SUBDOMAIN_MISSING") {
            throw
        }

        Append-Log("La cuenta no tiene subdominio workers.dev. El instalador intentará reservarlo automáticamente.")

        $candidate = Normalize-ProjectName $project
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $candidate = "foroactivo"
        }

        if (-not (Register-WorkersDevSubdomain $candidate)) {
            $candidate = Prompt-WorkersDevSubdomain $candidate $message
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                throw (Get-UiText "workersDevSubdomainMissing")
            }

            if (-not (Register-WorkersDevSubdomain $candidate)) {
                $candidate = Prompt-WorkersDevSubdomain ($candidate + "-1") $message
                if ([string]::IsNullOrWhiteSpace($candidate) -or
                    -not (Register-WorkersDevSubdomain $candidate)) {
                    throw (Get-UiText "workersDevSubdomainMissing")
                }
            }
        }

        Append-Log("Reintentando publicar el Worker tras registrar workers.dev...")
        return Run-Command $script:NpxCommand "wrangler deploy"
    }
}

function Test-D1TransientError([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) { return $false }

    return (
        $message -match "code:\s*7429" -or
        $message -match "storage operation exceeded timeout" -or
        $message -match "object to be reset" -or
        $message -match "D1.*timeout" -or
        $message -match "Cloudflare API.*query failed"
    )
}

function Execute-Sql([string]$sql) {
    $maxAttempts = 5
    $delaySeconds = 4
    $target = if ([string]::IsNullOrWhiteSpace($script:D1ExecuteTarget)) { "DB" } else { [string]$script:D1ExecuteTarget }

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            return Run-Command $script:NpxCommand "wrangler d1 execute `"$target`" --remote --command `"$sql`""
        }
        catch {
            $message = $_.Exception.Message

            if (($attempt -lt $maxAttempts) -and (Test-D1TransientError $message)) {
                Append-Log([string]::Format((Get-LogText "d1Retry"), $attempt, $maxAttempts, $delaySeconds))
                Start-Sleep -Seconds $delaySeconds
                $delaySeconds = [Math]::Min(20, $delaySeconds * 2)
                continue
            }

            if (Test-D1TransientError $message) {
                $friendly = Get-LogText "d1RetryFinal"
                Append-Log($friendly)
                throw ($friendly + [Environment]::NewLine + [Environment]::NewLine + $message)
            }

            throw
        }
    }
}

function Get-D1Rows([string]$sql) {
    $maxAttempts = 5
    $delaySeconds = 4
    $target = if ([string]::IsNullOrWhiteSpace($script:D1ExecuteTarget)) { "DB" } else { [string]$script:D1ExecuteTarget }

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $output = Run-Command $script:NpxCommand "wrangler d1 execute `"$target`" --remote --json --command `"$sql`""

            try {
                $jsonText = $output.Trim()
                $firstBracket = $jsonText.IndexOf("[")
                $firstBrace = $jsonText.IndexOf("{")
                $start = -1

                if ($firstBracket -ge 0 -and ($firstBrace -lt 0 -or $firstBracket -lt $firstBrace)) {
                    $start = $firstBracket
                } elseif ($firstBrace -ge 0) {
                    $start = $firstBrace
                }

                if ($start -gt 0) {
                    $jsonText = $jsonText.Substring($start)
                }

                $parsed = $jsonText | ConvertFrom-Json
                $rows = New-Object System.Collections.ArrayList

                foreach ($item in @($parsed)) {
                    if ($item.PSObject.Properties["results"] -and $null -ne $item.results) {
                        foreach ($result in @($item.results)) {
                            [void]$rows.Add($result)
                        }
                    }
                }

                return @($rows)
            } catch {
                throw "No se pudo leer la respuesta de D1 como JSON. Última salida: $output"
            }
        } catch {
            $message = $_.Exception.Message

            if (($attempt -lt $maxAttempts) -and (Test-D1TransientError $message)) {
                Append-Log([string]::Format((Get-LogText "d1Retry"), $attempt, $maxAttempts, $delaySeconds))
                Start-Sleep -Seconds $delaySeconds
                $delaySeconds = [Math]::Min(20, $delaySeconds * 2)
                continue
            }

            if (Test-D1TransientError $message) {
                $friendly = Get-LogText "d1RetryFinal"
                Append-Log($friendly)
                throw ($friendly + [Environment]::NewLine + [Environment]::NewLine + $message)
            }

            throw
        }
    }
}

function Put-Secret([string]$name, [string]$value) {
    Run-Command $script:NpxCommand "wrangler secret put $name" $value
}

function Remove-SecretIfExists([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    try {
        Run-Command $script:NpxCommand "wrangler secret delete $name" "y"
        Append-Log("Secret eliminado: $name")
    }
    catch {
        Append-Log("No se pudo eliminar el secret '$name'. Puede que ya no exista. Detalle: " + $_.Exception.Message)
    }
}

function New-StringSet {
    return New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
}

function Get-Sha256Hex([string]$value) {
    $normalized = $value.Normalize([Text.NormalizationForm]::FormC)
    $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
    $sha = [Security.Cryptography.SHA256]::Create()

    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha.Dispose()
    }
}

function Set-AdminKeyHashInD1([string]$plainKey) {
    $hash = Get-Sha256Hex $plainKey

    Execute-Sql (
        "CREATE TABLE IF NOT EXISTS admin_settings (" +
        "setting_key TEXT PRIMARY KEY, " +
        "setting_value TEXT NOT NULL, " +
        "updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP" +
        ");"
    )

    Execute-Sql (
        "INSERT INTO admin_settings " +
        "(setting_key, setting_value, updated_at) VALUES " +
        "('admin_key_hash', " + (Sql-Text $hash) + ", CURRENT_TIMESTAMP) " +
        "ON CONFLICT(setting_key) DO UPDATE SET " +
        "setting_value = excluded.setting_value, " +
        "updated_at = CURRENT_TIMESTAMP;"
    )
}

function Get-D1IdFromJsonValue($value, [string]$databaseName) {
    if ($null -eq $value) { return "" }

    if ($value -is [System.Array]) {
        foreach ($item in $value) {
            $found = Get-D1IdFromJsonValue $item $databaseName
            if (-not [string]::IsNullOrWhiteSpace($found)) { return $found }
        }
        return ""
    }

    $name = ""
    $id = ""

    foreach ($propertyName in @("name", "database_name")) {
        if ($value.PSObject.Properties[$propertyName]) {
            $name = [string]$value.$propertyName
            break
        }
    }

    foreach ($propertyName in @("uuid", "id", "database_id")) {
        if ($value.PSObject.Properties[$propertyName]) {
            $id = [string]$value.$propertyName
            break
        }
    }

    if ($name -eq $databaseName -and -not [string]::IsNullOrWhiteSpace($id)) {
        return $id
    }

    foreach ($property in $value.PSObject.Properties) {
        if ($property.Value -is [System.Management.Automation.PSCustomObject] -or
            $property.Value -is [System.Array]) {
            $found = Get-D1IdFromJsonValue $property.Value $databaseName
            if (-not [string]::IsNullOrWhiteSpace($found)) { return $found }
        }
    }

    return ""
}

function Get-D1IdFromText([string]$text, [string]$databaseName) {
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }

    try {
        $json = $text | ConvertFrom-Json
        $id = Get-D1IdFromJsonValue $json $databaseName
        if (-not [string]::IsNullOrWhiteSpace($id)) { return $id }
    } catch {
    }

    $escapedName = [Regex]::Escape($databaseName)
    $nearName = [Regex]::Match(
        $text,
        "(?is)$escapedName.{0,500}?(?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
    )

    if ($nearName.Success) {
        return $nearName.Groups["id"].Value
    }

    $anyId = [Regex]::Match(
        $text,
        "(?i)(?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
    )

    if ($anyId.Success) {
        return $anyId.Groups["id"].Value
    }

    return ""
}

function Save-WranglerConfig($config, [string]$configPath) {
    $config | ConvertTo-Json -Depth 20 | Set-Content $configPath -Encoding UTF8
}

function Get-CloudflareAccountIdFromText([string]$text) {
    $matches = [Regex]::Matches([string]$text, "(?i)\b[0-9a-f]{32}\b")
    if ($matches.Count -eq 1) { return $matches[0].Value.ToLowerInvariant() }
    if ($matches.Count -gt 1) {
        $ids = @($matches | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique)
        if ($ids.Count -eq 1) { return $ids[0] }
    }
    return ""
}

function Set-WranglerAccountBinding($config, $identity) {
    $accountId = ""
    if ($null -ne $identity -and $identity.PSObject.Properties["account_id"]) {
        $accountId = ([string]$identity.account_id).Trim().ToLowerInvariant()
    }

    if ([string]::IsNullOrWhiteSpace($accountId)) { return }
    $config | Add-Member -NotePropertyName "account_id" -NotePropertyValue $accountId -Force
}

function Ensure-CloudflareSessionForIdentity($identity) {
    if ($null -eq $identity -or -not $identity.PSObject.Properties["account_id"]) { return }

    $expectedAccountId = ([string]$identity.account_id).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($expectedAccountId)) { return }

    $currentOutput = $script:CloudflareWhoamiOutput
    if ([string]::IsNullOrWhiteSpace($currentOutput)) {
        try {
            $currentOutput = Run-Command $script:NpxCommand "wrangler whoami"
            $script:CloudflareWhoamiOutput = $currentOutput
        } catch {
            Append-Log("No se pudo leer la cuenta activa de Wrangler antes de validar la instalación.")
            $currentOutput = ""
        }
    }

    $currentAccountId = Get-CloudflareAccountIdFromText $currentOutput
    if ($currentAccountId -eq $expectedAccountId) {
        Append-Log("La sesión de Wrangler coincide con la cuenta Cloudflare vinculada: $expectedAccountId")
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($currentAccountId)) {
        Append-Log("La sesión activa de Wrangler no coincide. Activa: $currentAccountId. Esperada: $expectedAccountId")
    }
    else {
        Append-Log("No se pudo identificar de forma segura la cuenta activa de Wrangler. Se forzará una nueva autorización.")
    }

    $script:CloudflareWhoamiOutput = ""
    $newOutput = Invoke-CloudflareLogin $true
    $newAccountId = Get-CloudflareAccountIdFromText $newOutput

    if ($newAccountId -ne $expectedAccountId) {
        if ([string]::IsNullOrWhiteSpace($newAccountId)) {
            throw "No se pudo identificar de forma segura la cuenta activa de Cloudflare.`n`nEsta instalación está vinculada a la cuenta ID: $expectedAccountId`nWorker vinculado: $($identity.worker_url)`nD1 vinculada: $($identity.d1_database_name)"
        }

        throw "La sesión activa de Cloudflare no corresponde a esta instalación.`n`nCuenta activa: $newAccountId`nCuenta esperada: $expectedAccountId`nWorker vinculado: $($identity.worker_url)`nD1 vinculada: $($identity.d1_database_name)`n`nCierra sesión en Cloudflare y autoriza la cuenta correcta."
    }

    Append-Log("La nueva sesión de Wrangler coincide con la cuenta Cloudflare vinculada: $expectedAccountId")
}

function Get-InstallationIdentityFileName {
    return ".foroactivo-installation.json"
}

function Get-InstallationIdentityPath {
    return (Join-Path $script:OutputFolder (Get-InstallationIdentityFileName))
}

function Add-SearchFolder($folders, [string]$folder) {
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    $folders.Add($folder)
}

function Get-InstallationSearchFolders {
    $folders = New-Object System.Collections.Generic.List[string]

    foreach ($folder in @($script:OutputFolder, $script:OutputBaseFolder, $root)) {
        Add-SearchFolder $folders $folder
    }

    $baseParents = New-Object System.Collections.Generic.List[string]
    foreach ($folder in @($script:OutputFolder, $script:OutputBaseFolder, $root)) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        try {
            $parent = Split-Path -Parent $folder
            Add-SearchFolder $baseParents $parent
        } catch {}
    }

    foreach ($parent in ($baseParents | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        Add-SearchFolder $folders $parent

        foreach ($langKey in @("ES","EN","PT","IT","RU","FR","DE","RO","NL")) {
            Add-SearchFolder $folders (Join-Path $parent (Get-OutputFolderName $langKey))
        }

        try {
            Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -match "FOROACTIVO|FORUMOTION|FORUMEIROS|FORUMATTIVO|FORUM2X2|FORUMACTIF|FORUMIEREN|FORUMGRATUIT|ACTIEFORUM|INSTALAR|INSTALL|INSTALLER|INSTALARE"
                } |
                Select-Object -First 30 |
                ForEach-Object { Add-SearchFolder $folders $_.FullName }
        } catch {}
    }

    return @(
        $folders |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function Get-InstallationIdentityCandidatePaths {
    $fileName = Get-InstallationIdentityFileName

    return @(
        Get-InstallationSearchFolders |
            ForEach-Object { Join-Path $_ $fileName }
    )
}

function Get-InstructionCandidatePaths {
    $names = @(
        "INSTRUCCIONES_DE_INSTALACION.txt",
        "INSTALLATION_INSTRUCTIONS.txt",
        "INSTRUCOES_DE_INSTALACAO.txt",
        "ISTRUZIONI_DI_INSTALLAZIONE.txt",
        "ИНСТРУКЦИИ_ПО_УСТАНОВКЕ.txt",
        "INSTRUCTIONS_D_INSTALLATION.txt",
        "INSTALLATIONSANLEITUNG.txt",
        "INSTRUCTIUNI_DE_INSTALARE.txt"
    )

    return @(
        foreach ($folder in (Get-InstallationSearchFolders)) {
            foreach ($name in $names) {
                Join-Path $folder $name
            }

            try {
                Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Extension -in @(".txt", ".html", ".json", ".jsonc") -and
                        $_.Name -match "INSTRU|INSTRUCT|INSTALL|INSTAL|FORMULARIO|FORM|PANEL|CONTROL|PAINEL|PANNELLO|PLANUNGS|PROGRAM|FOROACTIVO"
                    } |
                    ForEach-Object { $_.FullName }
            } catch {}
        }
    )
}

function Get-WorkerUrlFromInstructionFiles {
    foreach ($path in (Get-InstructionCandidatePaths)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $text = Get-Content -LiteralPath $path -Raw
        $match = [Regex]::Match($text, "https://[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9-]+\.workers\.dev/?")
        if ($match.Success) {
            return $match.Value.TrimEnd("/")
        }
    }

    return ""
}

function Get-WorkerNameFromWorkerUrl([string]$workerUrl) {
    $match = [Regex]::Match([string]$workerUrl, "^https://(?<name>[A-Za-z0-9][A-Za-z0-9-]*)\.[A-Za-z0-9-]+\.workers\.dev/?$")
    if ($match.Success) {
        return $match.Groups["name"].Value
    }
    return ""
}

function Get-D1DatabaseNameFromFiles([string]$workerName) {
    foreach ($path in (Get-InstallationIdentityCandidatePaths)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $identity = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            if ($identity.PSObject.Properties["d1_database_name"] -and
                -not [string]::IsNullOrWhiteSpace([string]$identity.d1_database_name)) {
                return [string]$identity.d1_database_name
            }
        } catch {}
    }

    foreach ($path in (Get-InstructionCandidatePaths)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $text = Get-Content -LiteralPath $path -Raw
            $match = [Regex]::Match($text, "(?im)^\s*(?:D1\s*(?:DATABASE|BASE)|BASE\s+D1|DATABASE\s+D1|NOMBRE\s+D1|D1\s+NAME)\s*:?\s*$\s*^\s*(?<name>[A-Za-z0-9][A-Za-z0-9_-]*)\s*$")
            if ($match.Success) {
                return $match.Groups["name"].Value
            }
        } catch {}
    }

    foreach ($path in @(
        (Join-Path $root "wrangler.jsonc"),
        (Join-Path $root "wrangler.json"),
        (Join-Path $root "wrangler.toml")
    )) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $text = Get-Content -LiteralPath $path -Raw
            $configName = ""
            $nameMatch = [Regex]::Match($text, '(?im)"name"\s*:\s*"(?<name>[^"]+)"')
            if ($nameMatch.Success) {
                $configName = $nameMatch.Groups["name"].Value
            }

            $match = [Regex]::Match($text, '(?im)"database_name"\s*:\s*"(?<name>[^"]+)"')
            if ($match.Success) {
                $name = $match.Groups["name"].Value
                if ($configName -eq $workerName -or $name -eq "$workerName-db") {
                    return $name
                }
            }

            $match = [Regex]::Match($text, '(?im)^\s*database_name\s*=\s*"(?<name>[^"]+)"')
            if ($match.Success) {
                $name = $match.Groups["name"].Value
                if ($configName -eq $workerName -or $name -eq "$workerName-db") {
                    return $name
                }
            }
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($workerName)) {
        return "$workerName-db"
    }

    return ""
}

function New-InstallationIdentityFromWorkerUrl([string]$workerUrl) {
    $workerName = Get-WorkerNameFromWorkerUrl $workerUrl
    if ([string]::IsNullOrWhiteSpace($workerName)) {
        throw "No se pudo reconstruir el nombre del Worker desde la URL guardada: $workerUrl"
    }

    $databaseName = Get-D1DatabaseNameFromFiles $workerName
    if ([string]::IsNullOrWhiteSpace($databaseName)) {
        throw "No se pudo reconstruir el nombre de la base D1 para el Worker guardado: $workerUrl"
    }

    return [pscustomobject]@{
        account_id       = ""
        worker_name      = $workerName
        worker_url       = $workerUrl
        d1_database_name = $databaseName
        d1_database_id   = ""
    }
}

function Save-InstallationIdentity(
    [string]$accountId,
    [string]$workerName,
    [string]$workerUrl,
    [string]$databaseName,
    [string]$databaseId
) {
    if ([string]::IsNullOrWhiteSpace($workerName) -or
        [string]::IsNullOrWhiteSpace($workerUrl) -or
        [string]::IsNullOrWhiteSpace($databaseName)) {
        throw "No se pudo guardar la identidad completa de la instalación."
    }

    $identityJson = [ordered]@{
        schema_version   = 1
        account_id       = $accountId
        worker_name      = $workerName
        worker_url       = $workerUrl
        d1_database_name = $databaseName
        d1_database_id   = $databaseId
        saved_at_utc     = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json -Depth 5

    $paths = @(
        (Get-InstallationIdentityPath),
        (Join-Path $script:OutputBaseFolder (Get-InstallationIdentityFileName))
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($path in $paths) {
        $folder = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        $identityJson | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

function Load-InstallationIdentity {
    $identityPath = Get-InstallationIdentityCandidatePaths |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($identityPath) -or
        -not (Test-Path -LiteralPath $identityPath)) {
        $workerUrl = Get-WorkerUrlFromInstructionFiles
        if (-not [string]::IsNullOrWhiteSpace($workerUrl)) {
            Append-Log("Installation identity was not found. Rebuilding it from the saved Worker URL...")
            return New-InstallationIdentityFromWorkerUrl $workerUrl
        }

        throw "No se encontró la identidad de esta instalación ni una URL de Worker en los archivos de instrucciones. Usa la carpeta de archivos generada por el instalador o realiza una instalación completa una vez."
    }

    try {
        $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
    } catch {
        $workerUrl = Get-WorkerUrlFromInstructionFiles
        if (-not [string]::IsNullOrWhiteSpace($workerUrl)) {
            Append-Log("Installation identity is damaged. Rebuilding it from the saved Worker URL...")
            return New-InstallationIdentityFromWorkerUrl $workerUrl
        }

        throw "El archivo de identidad de la instalación está dañado y no se encontró una URL de Worker en los archivos de instrucciones: $identityPath"
    }

    foreach ($property in @("worker_name", "worker_url", "d1_database_name")) {
        if (-not $identity.PSObject.Properties[$property] -or
            [string]::IsNullOrWhiteSpace([string]$identity.$property)) {
            throw "El archivo de identidad de la instalación está incompleto: falta '$property'."
        }
    }
    if (-not $identity.PSObject.Properties["account_id"]) {
        $identity | Add-Member -NotePropertyName "account_id" -NotePropertyValue "" -Force
    }
    if (-not $identity.PSObject.Properties["d1_database_id"]) {
        $identity | Add-Member -NotePropertyName "d1_database_id" -NotePropertyValue "" -Force
    }
    return $identity
}

function Update-InstallationIdentityDatabaseId($identity, [string]$databaseId) {
    if ($null -eq $identity -or [string]::IsNullOrWhiteSpace($databaseId)) { return }

    if (-not $identity.PSObject.Properties["d1_database_id"]) {
        $identity | Add-Member -NotePropertyName "d1_database_id" -NotePropertyValue $databaseId -Force
    } else {
        $identity.d1_database_id = $databaseId
    }

    Save-InstallationIdentity `
        ([string]$identity.account_id) `
        ([string]$identity.worker_name) `
        ([string]$identity.worker_url) `
        ([string]$identity.d1_database_name) `
        $databaseId
}

function Reconcile-D1DatabaseBinding($identity, $config, [string]$configPath) {
    $databaseName = [string]$identity.d1_database_name
    if ([string]::IsNullOrWhiteSpace($databaseName)) { return "" }

    Append-Log("Verificando D1 vinculada por nombre en Cloudflare: $databaseName")

    try {
        $listOutput = Run-Command $script:NpxCommand "wrangler d1 list --json"
        $databaseId = Get-D1IdFromText $listOutput $databaseName

        if ([string]::IsNullOrWhiteSpace($databaseId)) {
            Append-Log("No se encontró ninguna D1 llamada '$databaseName' en la cuenta activa.")
            return ""
        }

        $config.d1_databases[0].database_name = $databaseName
        $config.d1_databases[0] | Add-Member -NotePropertyName "database_id" -NotePropertyValue $databaseId -Force
        Save-WranglerConfig $config $configPath
        Update-InstallationIdentityDatabaseId $identity $databaseId

        Append-Log("D1 reconciliada correctamente: $databaseName ($databaseId)")
        return $databaseId
    }
    catch {
        Append-Log("No se pudo reconciliar la D1 por nombre: $($_.Exception.Message)")
        return ""
    }
}

function Ensure-D1Database($config, [string]$configPath, [string]$databaseName) {
    Append-Log(Get-LogText "preparingD1")

    $existingId = ""

    try {
        $listOutput = Run-Command $script:NpxCommand "wrangler d1 list --json"
        $existingId = Get-D1IdFromText $listOutput $databaseName
    } catch {
        Append-Log($_.Exception.Message)
    }

    if (-not [string]::IsNullOrWhiteSpace($existingId)) {
        $config.d1_databases[0] | Add-Member -NotePropertyName "database_id" -NotePropertyValue $existingId -Force
        Save-WranglerConfig $config $configPath
        Run-Command $script:NpxCommand "wrangler d1 execute DB --remote --command `"SELECT 1;`""
        Append-Log([string]::Format((Get-LogText "d1Found"), $databaseName))
        return $existingId
    }

    Append-Log(Get-LogText "d1NoneFound")
    Append-Log([string]::Format((Get-LogText "d1Creating"), $databaseName))

    try {
        $createOutput = Run-Command $script:NpxCommand "wrangler d1 create `"$databaseName`" --jurisdiction eu"
        $newId = Get-D1IdFromText $createOutput $databaseName

        if ([string]::IsNullOrWhiteSpace($newId)) {
            throw "Wrangler created the D1 database but did not return a database_id."
        }

        $config.d1_databases[0] | Add-Member -NotePropertyName "database_id" -NotePropertyValue $newId -Force
        Save-WranglerConfig $config $configPath
        Run-Command $script:NpxCommand "wrangler d1 execute DB --remote --command `"SELECT 1;`""
        Append-Log([string]::Format((Get-LogText "d1Created"), $databaseName))
        return $newId
    } catch {
        $message = $_.Exception.Message

        if ($message -match "maximum number of D1 databases" -or
            $message -match "maximum.*D1" -or
            $message -match "reached.*D1") {
            throw (Get-LogText "d1LimitReached")
        }

        throw
    }
}

$script:UiBlue = [System.Drawing.Color]::FromArgb(0, 119, 199)
$script:UiBlueDark = [System.Drawing.Color]::FromArgb(0, 91, 156)
$script:UiBlueSoft = [System.Drawing.Color]::FromArgb(232, 247, 255)
$script:UiSurface = [System.Drawing.Color]::FromArgb(246, 249, 252)
$script:UiText = [System.Drawing.Color]::FromArgb(27, 39, 53)
$script:UiMuted = [System.Drawing.Color]::FromArgb(83, 96, 112)
$script:UiBorder = [System.Drawing.Color]::FromArgb(211, 220, 230)

function Style-TextBox([System.Windows.Forms.TextBox]$textBox) {
    $textBox.BorderStyle = "FixedSingle"
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $textBox.ForeColor = $script:UiText
    if (-not $textBox.ReadOnly) {
        $textBox.BackColor = [System.Drawing.Color]::FromArgb(253, 254, 255)
    }
}

function Get-IanaTimeZones {
    return @(
        "Africa/Abidjan",
        "Africa/Accra",
        "Africa/Addis_Ababa",
        "Africa/Algiers",
        "Africa/Asmara",
        "Africa/Bamako",
        "Africa/Bangui",
        "Africa/Banjul",
        "Africa/Bissau",
        "Africa/Blantyre",
        "Africa/Brazzaville",
        "Africa/Bujumbura",
        "Africa/Cairo",
        "Africa/Casablanca",
        "Africa/Ceuta",
        "Africa/Conakry",
        "Africa/Dakar",
        "Africa/Dar_es_Salaam",
        "Africa/Djibouti",
        "Africa/Douala",
        "Africa/El_Aaiun",
        "Africa/Freetown",
        "Africa/Gaborone",
        "Africa/Johannesburg",
        "Africa/Juba",
        "Africa/Kampala",
        "Africa/Khartoum",
        "Africa/Kigali",
        "Africa/Kinshasa",
        "Africa/Lagos",
        "Africa/Libreville",
        "Africa/Lome",
        "Africa/Luanda",
        "Africa/Lubumbashi",
        "Africa/Lusaka",
        "Africa/Malabo",
        "Africa/Maputo",
        "Africa/Maseru",
        "Africa/Mbabane",
        "Africa/Mogadishu",
        "Africa/Monrovia",
        "Africa/Nairobi",
        "Africa/Ndjamena",
        "Africa/Niamey",
        "Africa/Nouakchott",
        "Africa/Ouagadougou",
        "Africa/Porto-Novo",
        "Africa/Sao_Tome",
        "Africa/Tripoli",
        "Africa/Tunis",
        "Africa/Windhoek",
        "America/Adak",
        "America/Anchorage",
        "America/Anguilla",
        "America/Antigua",
        "America/Araguaina",
        "America/Argentina/Buenos_Aires",
        "America/Argentina/Catamarca",
        "America/Argentina/Cordoba",
        "America/Argentina/Jujuy",
        "America/Argentina/La_Rioja",
        "America/Argentina/Mendoza",
        "America/Argentina/Rio_Gallegos",
        "America/Argentina/Salta",
        "America/Argentina/San_Juan",
        "America/Argentina/San_Luis",
        "America/Argentina/Tucuman",
        "America/Argentina/Ushuaia",
        "America/Aruba",
        "America/Asuncion",
        "America/Atikokan",
        "America/Bahia",
        "America/Bahia_Banderas",
        "America/Barbados",
        "America/Belem",
        "America/Belize",
        "America/Blanc-Sablon",
        "America/Boa_Vista",
        "America/Bogota",
        "America/Boise",
        "America/Cambridge_Bay",
        "America/Campo_Grande",
        "America/Cancun",
        "America/Caracas",
        "America/Cayenne",
        "America/Cayman",
        "America/Chicago",
        "America/Chihuahua",
        "America/Ciudad_Juarez",
        "America/Costa_Rica",
        "America/Cuiaba",
        "America/Curacao",
        "America/Danmarkshavn",
        "America/Dawson",
        "America/Dawson_Creek",
        "America/Denver",
        "America/Detroit",
        "America/Dominica",
        "America/Edmonton",
        "America/Eirunepe",
        "America/El_Salvador",
        "America/Fort_Nelson",
        "America/Fortaleza",
        "America/Glace_Bay",
        "America/Goose_Bay",
        "America/Grand_Turk",
        "America/Grenada",
        "America/Guadeloupe",
        "America/Guatemala",
        "America/Guayaquil",
        "America/Guyana",
        "America/Halifax",
        "America/Havana",
        "America/Hermosillo",
        "America/Indiana/Indianapolis",
        "America/Indiana/Knox",
        "America/Indiana/Marengo",
        "America/Indiana/Petersburg",
        "America/Indiana/Tell_City",
        "America/Indiana/Vevay",
        "America/Indiana/Vincennes",
        "America/Indiana/Winamac",
        "America/Inuvik",
        "America/Iqaluit",
        "America/Jamaica",
        "America/Juneau",
        "America/Kentucky/Louisville",
        "America/Kentucky/Monticello",
        "America/Kralendijk",
        "America/La_Paz",
        "America/Lima",
        "America/Los_Angeles",
        "America/Lower_Princes",
        "America/Maceio",
        "America/Managua",
        "America/Manaus",
        "America/Marigot",
        "America/Martinique",
        "America/Matamoros",
        "America/Mazatlan",
        "America/Menominee",
        "America/Merida",
        "America/Metlakatla",
        "America/Mexico_City",
        "America/Miquelon",
        "America/Moncton",
        "America/Monterrey",
        "America/Montevideo",
        "America/Montserrat",
        "America/Nassau",
        "America/New_York",
        "America/Nome",
        "America/Noronha",
        "America/North_Dakota/Beulah",
        "America/North_Dakota/Center",
        "America/North_Dakota/New_Salem",
        "America/Nuuk",
        "America/Ojinaga",
        "America/Panama",
        "America/Paramaribo",
        "America/Phoenix",
        "America/Port-au-Prince",
        "America/Port_of_Spain",
        "America/Porto_Velho",
        "America/Puerto_Rico",
        "America/Punta_Arenas",
        "America/Rankin_Inlet",
        "America/Recife",
        "America/Regina",
        "America/Resolute",
        "America/Rio_Branco",
        "America/Santarem",
        "America/Santiago",
        "America/Santo_Domingo",
        "America/Sao_Paulo",
        "America/Scoresbysund",
        "America/Sitka",
        "America/St_Barthelemy",
        "America/St_Johns",
        "America/St_Kitts",
        "America/St_Lucia",
        "America/St_Thomas",
        "America/St_Vincent",
        "America/Swift_Current",
        "America/Tegucigalpa",
        "America/Thule",
        "America/Tijuana",
        "America/Toronto",
        "America/Tortola",
        "America/Vancouver",
        "America/Whitehorse",
        "America/Winnipeg",
        "America/Yakutat",
        "Antarctica/Casey",
        "Antarctica/Davis",
        "Antarctica/DumontDUrville",
        "Antarctica/Macquarie",
        "Antarctica/Mawson",
        "Antarctica/McMurdo",
        "Antarctica/Palmer",
        "Antarctica/Rothera",
        "Antarctica/Syowa",
        "Antarctica/Troll",
        "Antarctica/Vostok",
        "Arctic/Longyearbyen",
        "Asia/Aden",
        "Asia/Almaty",
        "Asia/Amman",
        "Asia/Aqtobe",
        "Asia/Aqtau",
        "Asia/Ashgabat",
        "Asia/Atyrau",
        "Asia/Baghdad",
        "Asia/Bahrain",
        "Asia/Baku",
        "Asia/Bangkok",
        "Asia/Beirut",
        "Asia/Bishkek",
        "Asia/Brunei",
        "Asia/Chita",
        "Asia/Colombo",
        "Asia/Damascus",
        "Asia/Dhaka",
        "Asia/Dili",
        "Asia/Dubai",
        "Asia/Dushanbe",
        "Asia/Famagusta",
        "Asia/Gaza",
        "Asia/Hebron",
        "Asia/Ho_Chi_Minh",
        "Asia/Hong_Kong",
        "Asia/Hovd",
        "Asia/Irkutsk",
        "Asia/Jakarta",
        "Asia/Jayapura",
        "Asia/Jerusalem",
        "Asia/Kabul",
        "Asia/Karachi",
        "Asia/Kathmandu",
        "Asia/Khandyga",
        "Asia/Kolkata",
        "Asia/Kuala_Lumpur",
        "Asia/Kuching",
        "Asia/Kuwait",
        "Asia/Macau",
        "Asia/Magadan",
        "Asia/Makassar",
        "Asia/Manila",
        "Asia/Muscat",
        "Asia/Nicosia",
        "Asia/Novokuznetsk",
        "Asia/Novosibirsk",
        "Asia/Omsk",
        "Asia/Oral",
        "Asia/Phnom_Penh",
        "Asia/Pontianak",
        "Asia/Pyongyang",
        "Asia/Qatar",
        "Asia/Qostanay",
        "Asia/Qyzylorda",
        "Asia/Riyadh",
        "Asia/Sakhalin",
        "Asia/Samarkand",
        "Asia/Seoul",
        "Asia/Shanghai",
        "Asia/Singapore",
        "Asia/Srednekolymsk",
        "Asia/Taipei",
        "Asia/Tashkent",
        "Asia/Tbilisi",
        "Asia/Tehran",
        "Asia/Thimphu",
        "Asia/Tokyo",
        "Asia/Ulaanbaatar",
        "Asia/Urumqi",
        "Asia/Ust-Nera",
        "Asia/Vientiane",
        "Asia/Vladivostok",
        "Asia/Yakutsk",
        "Asia/Yangon",
        "Asia/Yerevan",
        "Atlantic/Azores",
        "Atlantic/Bermuda",
        "Atlantic/Canary",
        "Atlantic/Cape_Verde",
        "Atlantic/Faroe",
        "Atlantic/Madeira",
        "Atlantic/Reykjavik",
        "Atlantic/South_Georgia",
        "Atlantic/Stanley",
        "Atlantic/St_Helena",
        "Australia/Adelaide",
        "Australia/Brisbane",
        "Australia/Broken_Hill",
        "Australia/Darwin",
        "Australia/Eucla",
        "Australia/Hobart",
        "Australia/Lindeman",
        "Australia/Lord_Howe",
        "Australia/Melbourne",
        "Australia/Perth",
        "Australia/Sydney",
        "Europe/Amsterdam",
        "Europe/Andorra",
        "Europe/Athens",
        "Europe/Belgrade",
        "Europe/Berlin",
        "Europe/Bratislava",
        "Europe/Brussels",
        "Europe/Bucharest",
        "Europe/Budapest",
        "Europe/Busingen",
        "Europe/Chisinau",
        "Europe/Copenhagen",
        "Europe/Dublin",
        "Europe/Gibraltar",
        "Europe/Guernsey",
        "Europe/Helsinki",
        "Europe/Isle_of_Man",
        "Europe/Istanbul",
        "Europe/Jersey",
        "Europe/Kaliningrad",
        "Europe/Kirov",
        "Europe/Kyiv",
        "Europe/Lisbon",
        "Europe/Ljubljana",
        "Europe/London",
        "Europe/Luxembourg",
        "Europe/Madrid",
        "Europe/Malta",
        "Europe/Mariehamn",
        "Europe/Minsk",
        "Europe/Monaco",
        "Europe/Moscow",
        "Europe/Oslo",
        "Europe/Paris",
        "Europe/Podgorica",
        "Europe/Prague",
        "Europe/Riga",
        "Europe/Rome",
        "Europe/Samara",
        "Europe/San_Marino",
        "Europe/Sarajevo",
        "Europe/Saratov",
        "Europe/Simferopol",
        "Europe/Skopje",
        "Europe/Sofia",
        "Europe/Stockholm",
        "Europe/Tallinn",
        "Europe/Tirane",
        "Europe/Ulyanovsk",
        "Europe/Vaduz",
        "Europe/Vatican",
        "Europe/Vienna",
        "Europe/Vilnius",
        "Europe/Volgograd",
        "Europe/Warsaw",
        "Europe/Zagreb",
        "Europe/Zurich",
        "Indian/Antananarivo",
        "Indian/Chagos",
        "Indian/Christmas",
        "Indian/Cocos",
        "Indian/Comoro",
        "Indian/Kerguelen",
        "Indian/Mahe",
        "Indian/Maldives",
        "Indian/Mauritius",
        "Indian/Mayotte",
        "Indian/Reunion",
        "Pacific/Apia",
        "Pacific/Auckland",
        "Pacific/Bougainville",
        "Pacific/Chatham",
        "Pacific/Chuuk",
        "Pacific/Easter",
        "Pacific/Efate",
        "Pacific/Fakaofo",
        "Pacific/Fiji",
        "Pacific/Funafuti",
        "Pacific/Galapagos",
        "Pacific/Gambier",
        "Pacific/Guadalcanal",
        "Pacific/Guam",
        "Pacific/Honolulu",
        "Pacific/Kanton",
        "Pacific/Kiritimati",
        "Pacific/Kosrae",
        "Pacific/Kwajalein",
        "Pacific/Majuro",
        "Pacific/Marquesas",
        "Pacific/Midway",
        "Pacific/Nauru",
        "Pacific/Niue",
        "Pacific/Norfolk",
        "Pacific/Noumea",
        "Pacific/Pago_Pago",
        "Pacific/Palau",
        "Pacific/Pitcairn",
        "Pacific/Pohnpei",
        "Pacific/Port_Moresby",
        "Pacific/Rarotonga",
        "Pacific/Saipan",
        "Pacific/Tahiti",
        "Pacific/Tarawa",
        "Pacific/Tongatapu",
        "Pacific/Wake",
        "Pacific/Wallis"
    )
}

function Style-ComboBox([System.Windows.Forms.ComboBox]$comboBox) {
    $comboBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $comboBox.ForeColor = $script:UiText
    $comboBox.BackColor = [System.Drawing.Color]::FromArgb(253, 254, 255)
    $comboBox.FlatStyle = "Flat"
}

function Style-Grid([System.Windows.Forms.DataGridView]$grid) {
    $grid.EditMode = "EditOnEnter"
    $grid.SelectionMode = "CellSelect"
    $grid.MultiSelect = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.BorderStyle = "FixedSingle"
    $grid.GridColor = [System.Drawing.Color]::FromArgb(226, 233, 241)
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersHeight = 36
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $script:UiBlue
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $grid.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $grid.DefaultCellStyle.ForeColor = $script:UiText
    $grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(214, 238, 251)
    $grid.DefaultCellStyle.SelectionForeColor = $script:UiText
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(249, 251, 253)
    $grid.RowTemplate.Height = 32
}

function Style-Button([System.Windows.Forms.Button]$button, [bool]$primary) {
    $button.FlatStyle = "Flat"
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    if ($primary) {
        $button.BackColor = $script:UiBlue
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatAppearance.BorderSize = 0
        $button.FlatAppearance.MouseOverBackColor = $script:UiBlueDark
        $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(0, 72, 124)
    }
    else {
        $button.BackColor = [System.Drawing.Color]::White
        $button.ForeColor = $script:UiText
        $button.FlatAppearance.BorderColor = $script:UiBorder
        $button.FlatAppearance.MouseOverBackColor = $script:UiBlueSoft
        $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(224, 235, 244)
    }
}

$script:CurrentLanguage = "ES"
$script:InstallerText = @{
    "ES" = @{
        "languageName" = "Español"
        "windowTitle" = "Programador de temas para Foroactivo"
        "subtitle" = "Instalador y configuración del sistema de publicación programada"
        "productBadge" = "  INSTALADOR SEGURO  "
        "tabProject" = "⚙  Proyecto"
        "tabForums" = "🌐  Foros"
        "tabAccounts" = "👤  Cuentas adicionales"
        "tabProgress" = "▶  Progreso"
        "legalTitle" = "Autoría y condiciones de uso"
        "generalTitle" = "Datos generales del proyecto"
        "securityTitle" = "Acceso al panel de control"
        "publisherTitle" = "Cuenta publicadora principal"
        "forumsHelp" = "Añade todos los foros donde se publicarán los temas. Cada URL debe comenzar por https://"
        "accountsHelp" = "Añade una fila por cada cuenta publicadora adicional. El usuario se usará como etiqueta y para generar el Secret."
        "installButton" = "＋  Nueva instalación"
        "updateButton" = "✓  Actualizar instalación"
        "closeButton" = "Cerrar"
        "ready" = "Preparado para instalar."
        "installDone" = "Instalación terminada correctamente."
        "updateDone" = "Actualización completada correctamente."
        "forumLabelColumn" = "Nombre visible"
        "forumUrlColumn" = "URL completa del foro"
        "accountUsernameColumn" = "Usuario Foroactivo"
        "accountPasswordColumn" = "Contraseña"
        "deactivateForumButton" = "Eliminar foro seleccionado"
        "deactivateAccountButton" = "Eliminar cuenta seleccionada"
        "selectForumToDeactivate" = "Selecciona primero una fila de foro para eliminarla."
        "selectAccountToDeactivate" = "Selecciona primero una fila de cuenta para eliminarla."
        "confirmDeactivateForum" = "¿Quieres eliminar este foro de la base D1? Dejará de aparecer en el formulario."
        "confirmDeactivateAccount" = "¿Quieres eliminar esta cuenta publicadora de la base D1 y borrar sus secretos de Cloudflare? Dejará de aparecer en el formulario."
        "forumDeactivated" = "Foro eliminado correctamente."
        "accountDeactivated" = "Cuenta eliminada correctamente."
        "mainAccountCannotDelete" = "La cuenta publicadora principal no se elimina desde esta tabla. Para cambiarla, escribe el nuevo usuario y contraseña en la sección del proyecto y pulsa Actualizar instalación."
    }
    "EN" = @{
        "languageName" = "English"
        "windowTitle" = "Topic Scheduler for Foroactivo"
        "subtitle" = "Installer and configuration for the scheduled publishing system"
        "productBadge" = "  SAFE INSTALLER  "
        "tabProject" = "⚙  Project"
        "tabForums" = "🌐  Forums"
        "tabAccounts" = "👤  Additional accounts"
        "tabProgress" = "▶  Progress"
        "legalTitle" = "Authorship and terms of use"
        "generalTitle" = "General project settings"
        "securityTitle" = "Control panel access"
        "publisherTitle" = "Main publishing account"
        "forumsHelp" = "Add every forum where topics will be published. Each URL must start with https://"
        "accountsHelp" = "Add one row for each additional publishing account. The username will be used as the label and Secret key."
        "installButton" = "＋  New installation"
        "updateButton" = "✓  Update installation"
        "closeButton" = "Close"
        "ready" = "Ready to install."
        "installDone" = "Installation completed successfully."
        "updateDone" = "Update completed successfully."
        "forumLabelColumn" = "Visible name"
        "forumUrlColumn" = "Full forum URL"
        "accountUsernameColumn" = "Forumotion username"
        "accountPasswordColumn" = "Password"
    }
    "PT" = @{
        "languageName" = "Português"
        "windowTitle" = "Programador de tópicos para Foroactivo"
        "subtitle" = "Instalador e configuração do sistema de publicação programada"
        "productBadge" = "  INSTALADOR SEGURO  "
        "tabProject" = "⚙  Projeto"
        "tabForums" = "🌐  Fóruns"
        "tabAccounts" = "👤  Contas adicionais"
        "tabProgress" = "▶  Progresso"
        "legalTitle" = "Autoria e condições de uso"
        "generalTitle" = "Dados gerais do projeto"
        "securityTitle" = "Acesso ao painel de controle"
        "publisherTitle" = "Conta publicadora principal"
        "forumsHelp" = "Adicione todos os fóruns onde os tópicos serão publicados. Cada URL deve começar por https://"
        "accountsHelp" = "Adicione uma linha para cada conta publicadora adicional. O usuário será usado como etiqueta e chave do Secret."
        "installButton" = "＋  Nova instalação"
        "updateButton" = "✓  Atualizar instalação"
        "closeButton" = "Fechar"
        "ready" = "Pronto para instalar."
        "installDone" = "Instalação concluída com sucesso."
        "updateDone" = "Atualização concluída com sucesso."
        "forumLabelColumn" = "Nome visível"
        "forumUrlColumn" = "URL completa do fórum"
        "accountUsernameColumn" = "Usuário Forumeiros"
        "accountPasswordColumn" = "Senha"
    }
    "IT" = @{
        "languageName" = "Italiano"
        "windowTitle" = "Programmatore di argomenti per Foroactivo"
        "subtitle" = "Installazione e configurazione del sistema di pubblicazione programmata"
        "tabProject" = "⚙  Progetto"
        "tabForums" = "🌐  Forum"
        "tabAccounts" = "👤  Account aggiuntivi"
        "tabProgress" = "▶  Avanzamento"
        "legalTitle" = "Autoria e condizioni d'uso"
        "generalTitle" = "Dati generali del progetto"
        "securityTitle" = "Accesso al pannello di controllo"
        "publisherTitle" = "Account pubblicatore principale"
        "forumsHelp" = "Aggiungi tutti i forum in cui verranno pubblicati gli argomenti. Ogni URL deve iniziare con https://"
        "accountsHelp" = "Aggiungi una riga per ogni account pubblicatore aggiuntivo. L'utente verrà usato come etichetta e chiave Secret."
        "installButton" = "＋  Nuova installazione"
        "updateButton" = "✓  Aggiorna installazione"
        "closeButton" = "Chiudi"
        "ready" = "Pronto per l'installazione."
        "installDone" = "Installazione completata correttamente."
        "updateDone" = "Aggiornamento completato correttamente."
        "forumLabelColumn" = "Nome visibile"
        "forumUrlColumn" = "URL completo del forum"
        "accountUsernameColumn" = "Utente Forumattivo"
        "accountPasswordColumn" = "Password"
    }
    "RU" = @{
        "languageName" = "Русский"
        "windowTitle" = "Планировщик тем для Foroactivo"
        "subtitle" = "Установка и настройка системы запланированных публикаций"
        "tabProject" = "⚙  Проект"
        "tabForums" = "🌐  Форумы"
        "tabAccounts" = "👤  Дополнительные аккаунты"
        "tabProgress" = "▶  Ход выполнения"
        "legalTitle" = "Авторство и условия использования"
        "generalTitle" = "Общие параметры проекта"
        "securityTitle" = "Доступ к панели управления"
        "publisherTitle" = "Основной аккаунт публикации"
        "forumsHelp" = "Добавьте все форумы, где будут публиковаться темы. Каждый URL должен начинаться с https://"
        "accountsHelp" = "Добавьте строку для каждого дополнительного аккаунта. Имя пользователя будет использоваться как метка и ключ Secret."
        "installButton" = "＋  Новая установка"
        "updateButton" = "✓  Обновить установку"
        "closeButton" = "Закрыть"
        "ready" = "Готово к установке."
        "installDone" = "Установка успешно завершена."
        "updateDone" = "Обновление успешно завершено."
        "forumLabelColumn" = "Отображаемое имя"
        "forumUrlColumn" = "Полный URL форума"
        "accountUsernameColumn" = "Пользователь Forum2x2"
        "accountPasswordColumn" = "Пароль"
    }
    "FR" = @{
        "languageName" = "Français"
        "windowTitle" = "Planificateur de sujets pour Foroactivo"
        "subtitle" = "Installation et configuration du système de publication programmée"
        "tabProject" = "⚙  Projet"
        "tabForums" = "🌐  Forums"
        "tabAccounts" = "👤  Comptes supplémentaires"
        "tabProgress" = "▶  Progression"
        "legalTitle" = "Auteur et conditions d'utilisation"
        "generalTitle" = "Paramètres généraux du projet"
        "securityTitle" = "Accès au panneau de contrôle"
        "publisherTitle" = "Compte principal de publication"
        "forumsHelp" = "Ajoutez tous les forums où les sujets seront publiés. Chaque URL doit commencer par https://"
        "accountsHelp" = "Ajoutez une ligne pour chaque compte de publication supplémentaire. L'utilisateur servira d'étiquette et de clé Secret."
        "installButton" = "＋  Nouvelle installation"
        "updateButton" = "✓  Mettre à jour"
        "closeButton" = "Fermer"
        "ready" = "Prêt à installer."
        "installDone" = "Installation terminée avec succès."
        "updateDone" = "Mise à jour terminée avec succès."
        "forumLabelColumn" = "Nom visible"
        "forumUrlColumn" = "URL complète du forum"
        "accountUsernameColumn" = "Utilisateur Forumactif"
        "accountPasswordColumn" = "Mot de passe"
    }
    "DE" = @{
        "languageName" = "Deutsch"
        "windowTitle" = "Themenplaner für Foroactivo"
        "subtitle" = "Installation und Konfiguration des Systems für geplante Veröffentlichungen"
        "tabProject" = "⚙  Projekt"
        "tabForums" = "🌐  Foren"
        "tabAccounts" = "👤  Zusätzliche Konten"
        "tabProgress" = "▶  Fortschritt"
        "legalTitle" = "Urheberschaft und Nutzungsbedingungen"
        "generalTitle" = "Allgemeine Projekteinstellungen"
        "securityTitle" = "Zugang zum Kontrollpanel"
        "publisherTitle" = "Hauptkonto für Veröffentlichungen"
        "forumsHelp" = "Fügen Sie alle Foren hinzu, in denen Themen veröffentlicht werden. Jede URL muss mit https:// beginnen"
        "accountsHelp" = "Fügen Sie eine Zeile pro zusätzlichem Veröffentlichungskonto hinzu. Der Benutzername wird als Label und Secret-Schlüssel genutzt."
        "installButton" = "＋  Neue Installation"
        "updateButton" = "✓  Installation aktualisieren"
        "closeButton" = "Schließen"
        "ready" = "Bereit zur Installation."
        "installDone" = "Installation erfolgreich abgeschlossen."
        "updateDone" = "Aktualisierung erfolgreich abgeschlossen."
        "forumLabelColumn" = "Sichtbarer Name"
        "forumUrlColumn" = "Vollständige Forum-URL"
        "accountUsernameColumn" = "Forumieren-Benutzer"
        "accountPasswordColumn" = "Passwort"
    }
    "RO" = @{
        "languageName" = "Română"
        "windowTitle" = "Programator de subiecte pentru Foroactivo"
        "subtitle" = "Instalare și configurare pentru sistemul de publicare programată"
        "tabProject" = "⚙  Proiect"
        "tabForums" = "🌐  Forumuri"
        "tabAccounts" = "👤  Conturi suplimentare"
        "tabProgress" = "▶  Progres"
        "legalTitle" = "Autor și condiții de utilizare"
        "generalTitle" = "Setări generale ale proiectului"
        "securityTitle" = "Acces la panoul de control"
        "publisherTitle" = "Cont principal de publicare"
        "forumsHelp" = "Adaugă toate forumurile unde vor fi publicate subiectele. Fiecare URL trebuie să înceapă cu https://"
        "accountsHelp" = "Adaugă câte un rând pentru fiecare cont suplimentar. Utilizatorul va fi folosit ca etichetă și cheie Secret."
        "installButton" = "＋  Instalare nouă"
        "updateButton" = "✓  Actualizează instalarea"
        "closeButton" = "Închide"
        "ready" = "Gata pentru instalare."
        "installDone" = "Instalare finalizată cu succes."
        "updateDone" = "Actualizare finalizată cu succes."
        "forumLabelColumn" = "Nume vizibil"
        "forumUrlColumn" = "URL complet forum"
        "accountUsernameColumn" = "Utilizator Forumgratuit"
        "accountPasswordColumn" = "Parolă"
    }
    "NL" = @{
        "languageName" = "Nederlands"
        "windowTitle" = "Topicplanner voor Foroactivo"
        "subtitle" = "Installatie en configuratie van het systeem voor geplande publicatie"
        "productBadge" = "  VEILIGE INSTALLER  "
        "tabProject" = "⚙  Project"
        "tabForums" = "🌐  Forums"
        "tabAccounts" = "👤  Extra accounts"
        "tabProgress" = "▶  Voortgang"
        "legalTitle" = "Auteurschap en gebruiksvoorwaarden"
        "generalTitle" = "Algemene projectgegevens"
        "securityTitle" = "Toegang tot het controlepaneel"
        "publisherTitle" = "Hoofdaccount voor publicatie"
        "forumsHelp" = "Voeg alle forums toe waarop onderwerpen worden gepubliceerd. Elke URL moet beginnen met https://"
        "accountsHelp" = "Voeg één rij toe voor elk extra publicatieaccount. De gebruiker wordt gebruikt als label en Secret-sleutel."
        "installButton" = "＋  Nieuwe installatie"
        "updateButton" = "✓  Installatie bijwerken"
        "closeButton" = "Sluiten"
        "ready" = "Klaar om te installeren."
        "installDone" = "Installatie succesvol voltooid."
        "updateDone" = "Update succesvol voltooid."
        "forumLabelColumn" = "Zichtbare naam"
        "forumUrlColumn" = "Volledige forum-URL"
        "accountUsernameColumn" = "Actieforum-gebruiker"
        "accountPasswordColumn" = "Wachtwoord"
        "deactivateForumButton" = "Geselecteerd forum verwijderen"
        "deactivateAccountButton" = "Geselecteerd account verwijderen"
        "selectForumToDeactivate" = "Selecteer eerst een forumrij om te verwijderen."
        "selectAccountToDeactivate" = "Selecteer eerst een accountrij om te verwijderen."
        "confirmDeactivateForum" = "Wil je dit forum uit de D1-database verwijderen? Het verschijnt niet meer in het formulier."
        "confirmDeactivateAccount" = "Wil je dit publicatieaccount uit de D1-database verwijderen en de Cloudflare-secrets wissen? Het verschijnt niet meer in het formulier."
        "forumDeactivated" = "Forum correct verwijderd."
        "accountDeactivated" = "Account correct verwijderd."
        "mainAccountCannotDelete" = "Het hoofdaccount voor publicatie wordt niet vanuit deze tabel verwijderd. Om het te wijzigen, vul je de nieuwe gebruiker en het wachtwoord in de projectsectie in en klik je op Installatie bijwerken."
    }
}

$script:InstallerExtraText = @{
    "ES" = @{
        "languageLabel" = "Idioma / Language"
        "projectNameLabel" = "Nombre técnico del proyecto"
        "timezoneLabel" = "Zona horaria"
        "adminKeyLabel" = "Clave administrativa del panel"
        "hideAdminKey" = "Ocultar clave"
        "adminKeyWarning" = "IMPORTANTE: guarda esta clave. La necesitarás después para entrar en el panel de control."
        "startupTitle" = "Selecciona el idioma del instalador"
        "startupDescription" = "Se ha detectado el idioma de Windows cuando está disponible. Puedes cambiarlo antes de continuar."
        "startupContinue" = "Continuar"
        "legalBody" = "Proyecto de Código Abierto, desarrollado con ChatGPT + la consola de Firefox, con la supervisión total y múltiples pruebas de Jucarese, Administrador de Foroactivo. © 2026`nTodos los derechos reservados. Queda prohibida la reproducción, distribución, modificación o difusión, total o parcial, sin autorización expresa del autor."
        "mainUserLabel" = "Cuenta publicadora principal"
        "mainPassLabel" = "Contraseña de la cuenta principal"
        "note" = "Si Node.js no está instalado, se instalará automáticamente mediante Windows Package Manager. Cloudflare abrirá una sola ventana del navegador para autorizar la cuenta."
        "logLabel" = "Detalles técnicos"
        "resultTitle" = "Instalación completada correctamente"
        "resultIntro" = "Guarda la URL del Worker. La necesitarás para continuar la instalación en Foroactivo junto con la clave administrativa que escribiste en el instalador."
        "resultUrlLabel" = "URL del Worker"
        "copyUrl" = "Copiar URL"
        "urlCopied" = "URL copiada"
        "resultWarning" = "IMPORTANTE: guarda esta URL y la clave administrativa. Sin esos datos no podrás configurar el panel ni el formulario."
        "resultFiles" = "Se ha preparado una carpeta solo con los HTML del formulario, el panel de control y las instrucciones del idioma elegido. Abre esa carpeta y copia cada código en su página HTML correspondiente de Foroactivo."
        "openFiles" = "Abrir archivos de Foroactivo"
        "finish" = "Finalizar"
        "step1" = "Comprobar Node.js y herramientas"
        "step2" = "Instalar dependencias del proyecto"
        "step3" = "Preparar configuración de Cloudflare"
        "step4" = "Comprobar sesión de Cloudflare"
        "step5" = "Publicar el Worker"
        "step6" = "Aplicar migraciones de D1"
        "step7" = "Guardar credenciales y clave del panel"
        "step8" = "Registrar foros y cuentas adicionales"
        "step9" = "Publicar configuración final"
        "step10" = "Preparar archivos para Foroactivo"
        "cloudflareSessionDetected" = "sesión actual detectada"
        "cloudflareAccountDetected" = "cuenta detectada: {0}"
        "cloudflareSessionTitle" = "Sesión de Cloudflare"
        "cloudflareExistingSessionMessage" = "Wrangler ya tiene una sesión de Cloudflare activa ({0}).`n`nPulsa Sí para usar esa sesión y continuar.`nPulsa No si quieres cerrar la sesión de Wrangler y autorizar otra cuenta.`n`nEl instalador no abrirá ventanas extra: solo abrirá Cloudflare si realmente hace falta autorizar."
        "cloudflareBrowserChoiceMessage" = "No hay una sesión técnica de Wrangler activa, pero el navegador puede tener una cuenta de Cloudflare abierta.`n`nPulsa Sí si quieres usar la cuenta que ya esté abierta en el navegador.`nPulsa No si quieres cerrar/cambiar la cuenta de Cloudflare antes de autorizar."
        "cloudflareAuthorizeTitle" = "Autorizar Cloudflare"
        "cloudflareAuthorizeMessage" = "Cloudflare se abrirá una sola vez para autorizar el instalador.`n`nSi el navegador entra directamente en una cuenta que no quieres usar, cancela esa autorización en el navegador, cierra sesión en Cloudflare desde esa misma ventana y vuelve a pulsar Instalar."
        "cloudflareSwitchAccountTitle" = "Cambiar cuenta de Cloudflare"
        "cloudflareSwitchAccountMessage" = "Se ha cerrado la sesión técnica de Wrangler y se ha abierto Cloudflare para cambiar la cuenta del navegador.`n`n1. Cierra sesión en Cloudflare si aparece una cuenta que no quieres usar.`n2. Inicia sesión con la cuenta correcta.`n3. Cuando esa cuenta esté lista, vuelve aquí y pulsa Aceptar.`n`nDespués el instalador abrirá la autorización de Cloudflare para esa cuenta."
        "loadInstalledDataButton" = "Cargar datos instalados"
        "installedDataLoaded" = "Datos instalados cargados: {0} foro(s) y {1} cuenta(s) activa(s)."
        "accountKeyColumn" = "Clave interna"
        "cloudflareAuthFailed" = "Cloudflare no pudo terminar la autorización en el navegador.`n`nQué hacer:`n1. Vuelve a pulsar Instalar.`n2. Cuando se abra Cloudflare, inicia sesión y pulsa Permitir.`n3. No cierres esa pestaña hasta que el instalador continúe solo.`n`nSi vuelve a fallar, usa Chrome o Edge como navegador predeterminado solo durante la instalación y vuelve a intentarlo."
        "workersDevSubdomainMissing" = "Esta cuenta de Cloudflare todavía no tiene creado el subdominio workers.dev.`n`nCloudflare abrirá la página de configuración inicial. Crea el subdominio workers.dev de la cuenta y, cuando termine, vuelve a ejecutar el instalador. La base D1 ya creada se reutilizará si tiene el mismo nombre."
        "cloudflarePrivateLogout" = "Cerrando cualquier sesión privada anterior de Cloudflare antes de autorizar..."
        "cloudflareNoPrivateBrowser" = "No se encontró un navegador compatible para abrir Cloudflare en ventana privada. Instala o configura Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox o Pale Moon."
        "cloudflarePrivateLoginFailed" = "No se pudo completar la autorización privada de Cloudflare. Cierra las ventanas de autorización abiertas y vuelve a intentarlo desde el instalador."
        "logComplete" = "Log completo"
        "maintenanceNoChanges" = "Rellena al menos una clave, cuenta principal, foro o cuenta adicional antes de pulsar Mantenimiento."
        "maintenanceMainIncomplete" = "Para actualizar la cuenta publicadora principal debes rellenar usuario y contraseña."
        "maintenanceAdminUpdated" = "Clave del panel actualizada."
        "maintenanceMainUpdated" = "Cuenta publicadora principal actualizada."
        "maintenanceDone" = "Mantenimiento completado correctamente.`n`nNo se ha reinstalado el proyecto: solo se han actualizado Secrets y registros necesarios."
        "backupButton" = "💾  Copia D1"
        "backupCreated" = "Copia de seguridad D1 creada correctamente:`n{0}"
        "backupAutoCreated" = "Copia de seguridad automática creada antes del mantenimiento: {0}"
        "backupToolTip" = "Guarda una copia .sql de la base D1 vinculada en la carpeta d1_backups."
    }
    "EN" = @{
        "languageLabel" = "Language"
        "projectNameLabel" = "Technical project name"
        "timezoneLabel" = "Time zone"
        "adminKeyLabel" = "Control panel admin key"
        "hideAdminKey" = "Hide key"
        "adminKeyWarning" = "IMPORTANT: save this key. You will need it later to access the control panel."
        "startupTitle" = "Select the installer language"
        "startupDescription" = "The Windows regional language is detected when available. You can change it before continuing."
        "startupContinue" = "Continue"
        "legalBody" = "Open Source Project, developed with ChatGPT + the Firefox console, under the full supervision and multiple tests of Jucarese, Foroactivo Administrator. © 2026`nAll rights reserved. Reproduction, distribution, modification or publication, in whole or in part, is prohibited without the author's express authorization."
        "mainUserLabel" = "Main publishing account"
        "mainPassLabel" = "Main account password"
        "note" = "If Node.js is not installed, it will be installed automatically through Windows Package Manager. Cloudflare will open one browser window only when authorization is needed."
        "logLabel" = "Technical details"
        "resultTitle" = "Installation completed successfully"
        "resultIntro" = "Save the Worker URL. You will need it to continue the Foroactivo setup together with the admin key entered in the installer."
        "resultUrlLabel" = "Worker URL"
        "copyUrl" = "Copy URL"
        "urlCopied" = "URL copied"
        "resultWarning" = "IMPORTANT: save this URL and the admin key. Without them you cannot configure the panel or the form."
        "resultFiles" = "A folder has been prepared only with the form HTML, control panel HTML and instructions for the selected language. Open it and copy each code into its corresponding Foroactivo HTML page."
        "openFiles" = "Open Foroactivo files"
        "finish" = "Finish"
        "step1" = "Check Node.js and tools"
        "step2" = "Install project dependencies"
        "step3" = "Prepare Cloudflare configuration"
        "step4" = "Check Cloudflare session"
        "step5" = "Publish the Worker"
        "step6" = "Apply D1 migrations"
        "step7" = "Save credentials and panel key"
        "step8" = "Register forums and additional accounts"
        "step9" = "Publish final configuration"
        "step10" = "Prepare Foroactivo files"
        "cloudflareSessionDetected" = "current session detected"
        "cloudflareAccountDetected" = "detected account: {0}"
        "cloudflareSessionTitle" = "Cloudflare session"
        "cloudflareExistingSessionMessage" = "Wrangler already has an active Cloudflare session ({0}).`n`nClick Yes to use this session and continue.`nClick No to close the Wrangler session and authorize another account.`n`nThe installer will not open extra windows: it will only open Cloudflare when authorization is really needed."
        "cloudflareBrowserChoiceMessage" = "There is no active technical Wrangler session, but the browser may already have a Cloudflare account open.`n`nClick Yes to use whichever account is already open in the browser.`nClick No to log out or switch the Cloudflare account before authorization."
        "cloudflareAuthorizeTitle" = "Authorize Cloudflare"
        "cloudflareAuthorizeMessage" = "Cloudflare will open once to authorize the installer.`n`nIf the browser goes directly into an account you do not want to use, cancel that authorization in the browser, log out of Cloudflare in that same window, and click Install again."
        "cloudflareSwitchAccountTitle" = "Switch Cloudflare account"
        "cloudflareSwitchAccountMessage" = "The technical Wrangler session has been closed and Cloudflare has been opened so you can change the browser account.`n`n1. Log out of Cloudflare if it shows an account you do not want to use.`n2. Sign in with the correct account.`n3. When that account is ready, come back here and click OK.`n`nThe installer will then open the Cloudflare authorization for that account."
        "loadInstalledDataButton" = "Load installed data"
        "installedDataLoaded" = "Installed data loaded: {0} active forum(s) and {1} active account(s)."
        "accountKeyColumn" = "Internal key"
        "deactivateForumButton" = "Delete selected forum"
        "deactivateAccountButton" = "Delete selected account"
        "selectForumToDeactivate" = "Select a forum row first."
        "selectAccountToDeactivate" = "Select an account row first."
        "confirmDeactivateForum" = "Do you want to delete this forum from D1? It will no longer appear in the form."
        "confirmDeactivateAccount" = "Do you want to delete this publishing account from D1 and remove its Cloudflare secrets? It will no longer appear in the form."
        "forumDeactivated" = "Forum deleted successfully."
        "accountDeactivated" = "Account deleted successfully."
        "mainAccountCannotDelete" = "The main publishing account cannot be deleted from this table. To change it, enter the new username and password in the project section and click Update installation."
        "cloudflareAuthFailed" = "Cloudflare could not complete the browser authorization.`n`nWhat to do:`n1. Click Install again.`n2. When Cloudflare opens, sign in and click Allow.`n3. Do not close that tab until the installer continues by itself.`n`nIf it fails again, use Chrome or Edge as the default browser only during installation and try again."
        "workersDevSubdomainMissing" = "This Cloudflare account does not have a workers.dev subdomain yet.`n`nCloudflare will open the initial setup page. Create the workers.dev subdomain for the account and then run the installer again. The D1 database already created will be reused if it has the same name."
        "cloudflarePrivateLogout" = "Closing any previous private Cloudflare session before authorization..."
        "cloudflareNoPrivateBrowser" = "No compatible browser was found to open Cloudflare in a private window. Install or configure Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox or Pale Moon."
        "cloudflarePrivateLoginFailed" = "The private Cloudflare authorization could not be completed. Close any open authorization windows and try again from the installer."
        "logComplete" = "Full log"
        "maintenanceNoChanges" = "Fill in at least one key, main account, forum or additional account before clicking Maintenance."
        "maintenanceMainIncomplete" = "To update the main publishing account, fill in both username and password."
        "maintenanceAdminUpdated" = "Control panel key updated."
        "maintenanceMainUpdated" = "Main publishing account updated."
        "maintenanceDone" = "Maintenance completed successfully.`n`nThe project was not reinstalled: only the required Secrets and records were updated."
        "backupButton" = "💾  D1 backup"
        "backupCreated" = "D1 backup created successfully:`n{0}"
        "backupAutoCreated" = "Automatic backup created before maintenance: {0}"
        "backupToolTip" = "Saves a .sql copy of the linked D1 database in the backup folder."
    }
    "PT" = @{
        "languageLabel" = "Idioma"
        "projectNameLabel" = "Nome técnico do projeto"
        "timezoneLabel" = "Fuso horário"
        "adminKeyLabel" = "Chave administrativa do painel"
        "hideAdminKey" = "Ocultar chave"
        "adminKeyWarning" = "IMPORTANTE: guarde esta chave. Você precisará dela para entrar no painel de controle."
        "startupTitle" = "Selecione o idioma do instalador"
        "startupDescription" = "O idioma regional do Windows é detectado quando disponível. Você pode alterá-lo antes de continuar."
        "startupContinue" = "Continuar"
        "legalBody" = "Projeto de Código Aberto, desenvolvido com ChatGPT + a consola do Firefox, com a supervisão total e múltiplos testes de Jucarese, Administrador de Foroactivo. © 2026`nTodos os direitos reservados. É proibida a reprodução, distribuição, modificação ou divulgação, total ou parcial, sem autorização expressa do autor."
        "mainUserLabel" = "Conta publicadora principal"
        "mainPassLabel" = "Senha da conta principal"
        "note" = "Se o Node.js não estiver instalado, será instalado automaticamente pelo Windows Package Manager. O Cloudflare abrirá uma janela do navegador apenas quando for necessário autorizar."
        "logLabel" = "Detalhes técnicos"
        "resultTitle" = "Instalação concluída com sucesso"
        "resultIntro" = "Guarde a URL do Worker. Você precisará dela para continuar a configuração no Foroactivo junto com a chave administrativa."
        "resultUrlLabel" = "URL do Worker"
        "copyUrl" = "Copiar URL"
        "urlCopied" = "URL copiada"
        "resultWarning" = "IMPORTANTE: guarde esta URL e a chave administrativa. Sem esses dados você não poderá configurar o painel nem o formulário."
        "resultFiles" = "Foi preparada uma pasta apenas com o HTML do formulário, o HTML do painel de controle e as instruções do idioma escolhido."
        "openFiles" = "Abrir arquivos do Foroactivo"
        "finish" = "Finalizar"
        "step1" = "Verificar Node.js e ferramentas"
        "step2" = "Instalar dependências do projeto"
        "step3" = "Preparar configuração do Cloudflare"
        "step4" = "Verificar sessão do Cloudflare"
        "step5" = "Publicar o Worker"
        "step6" = "Aplicar migrações D1"
        "step7" = "Guardar credenciais e chave do painel"
        "step8" = "Registrar fóruns e contas adicionais"
        "step9" = "Publicar configuração final"
        "step10" = "Preparar arquivos para Foroactivo"
        "cloudflareSessionDetected" = "sessão atual detectada"
        "cloudflareAccountDetected" = "conta detectada: {0}"
        "cloudflareSessionTitle" = "Sessão do Cloudflare"
        "cloudflareExistingSessionMessage" = "O Wrangler já tem uma sessão do Cloudflare ativa ({0}).`n`nClique em Sim para usar esta sessão e continuar.`nClique em Não para fechar a sessão do Wrangler e autorizar outra conta.`n`nO instalador não abrirá janelas extras: só abrirá o Cloudflare quando a autorização for realmente necessária."
        "cloudflareBrowserChoiceMessage" = "Não há uma sessão técnica ativa do Wrangler, mas o navegador pode já ter uma conta Cloudflare aberta.`n`nClique em Sim para usar a conta que já estiver aberta no navegador.`nClique em Não para sair ou mudar a conta Cloudflare antes da autorização."
        "cloudflareAuthorizeTitle" = "Autorizar Cloudflare"
        "cloudflareAuthorizeMessage" = "O Cloudflare será aberto uma única vez para autorizar o instalador.`n`nSe o navegador entrar diretamente numa conta que você não quer usar, cancele essa autorização no navegador, saia do Cloudflare nessa mesma janela e clique em Instalar novamente."
        "cloudflareSwitchAccountTitle" = "Alterar conta Cloudflare"
        "cloudflareSwitchAccountMessage" = "A sessão técnica do Wrangler foi fechada e o Cloudflare foi aberto para alterar a conta do navegador.`n`n1. Termine a sessão no Cloudflare se aparecer uma conta que não quer usar.`n2. Inicie sessão com a conta correta.`n3. Quando essa conta estiver pronta, volte aqui e clique em OK.`n`nDepois o instalador abrirá a autorização do Cloudflare para essa conta."
        "loadInstalledDataButton" = "Carregar dados instalados"
        "installedDataLoaded" = "Dados instalados carregados: {0} fórum(ns) e {1} conta(s) ativa(s)."
        "accountKeyColumn" = "Chave interna"
        "deactivateForumButton" = "Eliminar fórum selecionado"
        "deactivateAccountButton" = "Eliminar conta selecionada"
        "selectForumToDeactivate" = "Selecione primeiro uma linha de fórum para eliminar."
        "selectAccountToDeactivate" = "Selecione primeiro uma linha de conta para eliminar."
        "confirmDeactivateForum" = "Deseja eliminar este fórum da base D1? Ele deixará de aparecer no formulário."
        "confirmDeactivateAccount" = "Deseja eliminar esta conta publicadora da base D1 e apagar seus secrets do Cloudflare? Ela deixará de aparecer no formulário."
        "forumDeactivated" = "Fórum eliminado corretamente."
        "accountDeactivated" = "Conta eliminada corretamente."
        "mainAccountCannotDelete" = "A conta publicadora principal não pode ser eliminada nesta tabela. Para alterá-la, introduza o novo utilizador e a senha na secção do projeto e clique em Atualizar instalação."
        "cloudflareAuthFailed" = "O Cloudflare não conseguiu concluir a autorização no navegador.`n`nO que fazer:`n1. Clique em Instalar novamente.`n2. Quando o Cloudflare abrir, inicie sessão e clique em Permitir.`n3. Não feche essa aba até o instalador continuar sozinho.`n`nSe falhar novamente, use Chrome ou Edge como navegador padrão apenas durante a instalação e tente outra vez."
        "workersDevSubdomainMissing" = "Esta conta Cloudflare ainda não tem um subdomínio workers.dev criado.`n`nO Cloudflare abrirá a página de configuração inicial. Crie o subdomínio workers.dev da conta e depois execute o instalador novamente. A base D1 já criada será reutilizada se tiver o mesmo nome."
        "cloudflarePrivateLogout" = "Fechando qualquer sessão privada anterior do Cloudflare antes da autorização..."
        "cloudflareNoPrivateBrowser" = "Não foi encontrado um navegador compatível para abrir o Cloudflare em janela privada. Instale ou configure Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox ou Pale Moon."
        "cloudflarePrivateLoginFailed" = "Não foi possível concluir a autorização privada do Cloudflare. Feche as janelas de autorização abertas e tente novamente pelo instalador."
        "logComplete" = "Log completo"
        "maintenanceNoChanges" = "Preencha pelo menos uma chave, conta principal, fórum ou conta adicional antes de clicar em Manutenção."
        "maintenanceMainIncomplete" = "Para atualizar a conta publicadora principal, preencha usuário e senha."
        "maintenanceAdminUpdated" = "Chave do painel atualizada."
        "maintenanceMainUpdated" = "Conta publicadora principal atualizada."
        "maintenanceDone" = "Manutenção concluída com sucesso.`n`nO projeto não foi reinstalado: apenas os Secrets e registros necessários foram atualizados."
        "backupButton" = "💾  Cópia D1"
        "backupCreated" = "Cópia de segurança D1 criada corretamente:`n{0}"
        "backupAutoCreated" = "Cópia automática criada antes da manutenção: {0}"
        "backupToolTip" = "Guarda uma cópia .sql da base D1 vinculada na pasta d1_backups."
    }
    "IT" = @{
        "languageLabel" = "Lingua"
        "projectNameLabel" = "Nome tecnico del progetto"
        "timezoneLabel" = "Fuso orario"
        "adminKeyLabel" = "Chiave amministrativa del pannello"
        "hideAdminKey" = "Nascondi chiave"
        "adminKeyWarning" = "IMPORTANTE: conserva questa chiave. Ti servirà per accedere al pannello di controllo."
        "startupTitle" = "Seleziona la lingua dell'installer"
        "startupDescription" = "La lingua regionale di Windows viene rilevata quando disponibile. Puoi cambiarla prima di continuare."
        "startupContinue" = "Continua"
        "legalBody" = "Progetto Open Source, sviluppato con ChatGPT + la console di Firefox, con la supervisione totale e molteplici test di Jucarese, Amministratore di Foroactivo. © 2026`nTutti i diritti riservati. È vietata la riproduzione, distribuzione, modifica o diffusione, totale o parziale, senza autorizzazione espressa dell'autore."
        "mainUserLabel" = "Account pubblicatore principale"
        "mainPassLabel" = "Password dell'account principale"
        "note" = "Se Node.js non è installato, verrà installato automaticamente tramite Windows Package Manager. Cloudflare aprirà una sola finestra del browser quando sarà necessaria l'autorizzazione."
        "logLabel" = "Dettagli tecnici"
        "resultTitle" = "Installazione completata correttamente"
        "resultIntro" = "Conserva l'URL del Worker. Ti servirà per continuare la configurazione in Foroactivo insieme alla chiave amministrativa."
        "resultUrlLabel" = "URL del Worker"
        "copyUrl" = "Copia URL"
        "urlCopied" = "URL copiato"
        "resultWarning" = "IMPORTANTE: conserva questo URL e la chiave amministrativa. Senza questi dati non potrai configurare il pannello o il modulo."
        "resultFiles" = "È stata preparata una cartella solo con l'HTML del modulo, l'HTML del pannello di controllo e le istruzioni della lingua scelta."
        "openFiles" = "Apri file Foroactivo"
        "finish" = "Fine"
        "step1" = "Controllare Node.js e strumenti"
        "step2" = "Installare dipendenze del progetto"
        "step3" = "Preparare configurazione Cloudflare"
        "step4" = "Controllare sessione Cloudflare"
        "step5" = "Pubblicare il Worker"
        "step6" = "Applicare migrazioni D1"
        "step7" = "Salvare credenziali e chiave pannello"
        "step8" = "Registrare forum e account aggiuntivi"
        "step9" = "Pubblicare configurazione finale"
        "step10" = "Preparare file per Foroactivo"
        "cloudflareSessionDetected" = "sessione attuale rilevata"
        "cloudflareAccountDetected" = "account rilevato: {0}"
        "cloudflareSessionTitle" = "Sessione Cloudflare"
        "cloudflareExistingSessionMessage" = "Wrangler ha già una sessione Cloudflare attiva ({0}).`n`nPremi Sì per usare questa sessione e continuare.`nPremi No per chiudere la sessione di Wrangler e autorizzare un altro account.`n`nL'installer non aprirà finestre extra: aprirà Cloudflare solo quando l'autorizzazione è davvero necessaria."
        "cloudflareBrowserChoiceMessage" = "Non c'è una sessione tecnica di Wrangler attiva, ma il browser potrebbe avere già un account Cloudflare aperto.`n`nPremi Sì per usare l'account già aperto nel browser.`nPremi No per uscire o cambiare l'account Cloudflare prima dell'autorizzazione."
        "cloudflareAuthorizeTitle" = "Autorizza Cloudflare"
        "cloudflareAuthorizeMessage" = "Cloudflare si aprirà una sola volta per autorizzare l'installer.`n`nSe il browser entra direttamente in un account che non vuoi usare, annulla l'autorizzazione nel browser, esci da Cloudflare in quella stessa finestra e premi di nuovo Installa."
        "cloudflareSwitchAccountTitle" = "Cambia account Cloudflare"
        "cloudflareSwitchAccountMessage" = "La sessione tecnica di Wrangler è stata chiusa e Cloudflare è stato aperto per cambiare l'account del browser.`n`n1. Esci da Cloudflare se appare un account che non vuoi usare.`n2. Accedi con l'account corretto.`n3. Quando l'account è pronto, torna qui e premi OK.`n`nPoi l'installer aprirà l'autorizzazione Cloudflare per quell'account."
        "loadInstalledDataButton" = "Carica dati installati"
        "installedDataLoaded" = "Dati installati caricati: {0} forum attivi e {1} account attivi."
        "accountKeyColumn" = "Chiave interna"
        "deactivateForumButton" = "Elimina forum selezionato"
        "deactivateAccountButton" = "Elimina account selezionato"
        "selectForumToDeactivate" = "Seleziona prima una riga di forum da eliminare."
        "selectAccountToDeactivate" = "Seleziona prima una riga di account da eliminare."
        "confirmDeactivateForum" = "Vuoi eliminare questo forum dal database D1? Non apparirà più nel modulo."
        "confirmDeactivateAccount" = "Vuoi eliminare questo account pubblicatore dal database D1 e cancellare i suoi secret Cloudflare? Non apparirà più nel modulo."
        "forumDeactivated" = "Forum eliminato correttamente."
        "accountDeactivated" = "Account eliminato correttamente."
        "mainAccountCannotDelete" = "L account pubblicatore principale non può essere eliminato da questa tabella. Per cambiarlo, inserisci il nuovo utente e la password nella sezione del progetto e premi Aggiorna installazione."
        "cloudflareAuthFailed" = "Cloudflare non ha potuto completare l'autorizzazione nel browser.`n`nCosa fare:`n1. Premi di nuovo Installa.`n2. Quando Cloudflare si apre, accedi e premi Consenti.`n3. Non chiudere quella scheda finché l'installer non continua da solo.`n`nSe fallisce ancora, usa Chrome o Edge come browser predefinito solo durante l'installazione e riprova."
        "workersDevSubdomainMissing" = "Questo account Cloudflare non ha ancora un sottodominio workers.dev.`n`nCloudflare aprirà la pagina di configurazione iniziale. Crea il sottodominio workers.dev dell account e poi esegui di nuovo l installer. Il database D1 già creato verrà riutilizzato se ha lo stesso nome."
        "cloudflarePrivateLogout" = "Chiusura di eventuali sessioni private Cloudflare precedenti prima dell autorizzazione..."
        "cloudflareNoPrivateBrowser" = "Non è stato trovato un browser compatibile per aprire Cloudflare in una finestra privata. Installa o configura Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox o Pale Moon."
        "cloudflarePrivateLoginFailed" = "Non è stato possibile completare l'autorizzazione privata di Cloudflare. Chiudi le finestre di autorizzazione aperte e riprova dall'installer."
        "logComplete" = "Log completo"
        "maintenanceNoChanges" = "Compila almeno una chiave, account principale, forum o account aggiuntivo prima di premere Manutenzione."
        "maintenanceMainIncomplete" = "Per aggiornare l'account pubblicatore principale devi inserire utente e password."
        "maintenanceAdminUpdated" = "Chiave del pannello aggiornata."
        "maintenanceMainUpdated" = "Account pubblicatore principale aggiornato."
        "maintenanceDone" = "Manutenzione completata correttamente.`n`nIl progetto non è stato reinstallato: sono stati aggiornati solo i Secrets e i record necessari."
        "backupButton" = "💾  Copia D1"
        "backupCreated" = "Copia di sicurezza D1 creata correttamente:`n{0}"
        "backupAutoCreated" = "Copia automatica creata prima della manutenzione: {0}"
        "backupToolTip" = "Salva una copia .sql del database D1 collegato nella cartella d1_backups."
    }
    "RU" = @{
        "languageLabel" = "Язык"
        "projectNameLabel" = "Техническое имя проекта"
        "timezoneLabel" = "Часовой пояс"
        "adminKeyLabel" = "Ключ администратора панели"
        "hideAdminKey" = "Скрыть ключ"
        "adminKeyWarning" = "ВАЖНО: сохраните этот ключ. Он понадобится для входа в панель управления."
        "startupTitle" = "Выберите язык установщика"
        "startupDescription" = "Региональный язык Windows определяется автоматически, если он поддерживается. Перед продолжением его можно изменить."
        "startupContinue" = "Продолжить"
        "legalBody" = "Проект с открытым исходным кодом, разработанный с помощью ChatGPT + консоли Firefox, при полном надзоре и многочисленных тестах Jucarese, администратора Foroactivo. © 2026`nВсе права защищены. Воспроизведение, распространение, изменение или публикация полностью или частично запрещены без явного разрешения автора."
        "mainUserLabel" = "Основной аккаунт публикации"
        "mainPassLabel" = "Пароль основного аккаунта"
        "note" = "Если Node.js не установлен, он будет установлен автоматически через Windows Package Manager. Cloudflare откроет окно браузера только при необходимости авторизации."
        "logLabel" = "Технические сведения"
        "resultTitle" = "Установка успешно завершена"
        "resultIntro" = "Сохраните URL Worker. Он понадобится для продолжения настройки Foroactivo вместе с административным ключом."
        "resultUrlLabel" = "URL Worker"
        "copyUrl" = "Копировать URL"
        "urlCopied" = "URL скопирован"
        "resultWarning" = "ВАЖНО: сохраните этот URL и административный ключ. Без них нельзя настроить панель или форму."
        "resultFiles" = "Подготовлена папка только с HTML формы, HTML панели управления и инструкциями для выбранного языка."
        "openFiles" = "Открыть файлы Foroactivo"
        "finish" = "Готово"
        "step1" = "Проверить Node.js и инструменты"
        "step2" = "Установить зависимости проекта"
        "step3" = "Подготовить конфигурацию Cloudflare"
        "step4" = "Проверить сессию Cloudflare"
        "step5" = "Опубликовать Worker"
        "step6" = "Применить миграции D1"
        "step7" = "Сохранить учетные данные и ключ панели"
        "step8" = "Зарегистрировать форумы и аккаунты"
        "step9" = "Опубликовать финальную конфигурацию"
        "step10" = "Подготовить файлы Foroactivo"
        "cloudflareSessionDetected" = "обнаружена текущая сессия"
        "cloudflareAccountDetected" = "обнаружен аккаунт: {0}"
        "cloudflareSessionTitle" = "Сессия Cloudflare"
        "cloudflareExistingSessionMessage" = "В Wrangler уже есть активная сессия Cloudflare ({0}).`n`nНажмите Да, чтобы использовать эту сессию и продолжить.`nНажмите Нет, чтобы закрыть сессию Wrangler и авторизовать другой аккаунт.`n`nУстановщик не будет открывать лишние окна: Cloudflare откроется только если авторизация действительно нужна."
        "cloudflareBrowserChoiceMessage" = "Активной технической сессии Wrangler нет, но в браузере уже может быть открыт аккаунт Cloudflare.`n`nНажмите Да, чтобы использовать аккаунт, который уже открыт в браузере.`nНажмите Нет, чтобы выйти или сменить аккаунт Cloudflare перед авторизацией."
        "cloudflareAuthorizeTitle" = "Авторизация Cloudflare"
        "cloudflareAuthorizeMessage" = "Cloudflare откроется один раз для авторизации установщика.`n`nЕсли браузер сразу входит в аккаунт, который вы не хотите использовать, отмените авторизацию в браузере, выйдите из Cloudflare в этом же окне и снова нажмите Установить."
        "cloudflareSwitchAccountTitle" = "Сменить аккаунт Cloudflare"
        "cloudflareSwitchAccountMessage" = "Технический сеанс Wrangler закрыт, и Cloudflare открыт, чтобы вы могли сменить аккаунт в браузере.`n`n1. Выйдите из Cloudflare, если открыт аккаунт, который вы не хотите использовать.`n2. Войдите в нужный аккаунт.`n3. Когда нужный аккаунт будет готов, вернитесь сюда и нажмите OK.`n`nПосле этого установщик откроет авторизацию Cloudflare для этого аккаунта."
        "loadInstalledDataButton" = "Загрузить установленные данные"
        "installedDataLoaded" = "Установленные данные загружены: {0} активных форум(ов) и {1} активных аккаунт(ов)."
        "accountKeyColumn" = "Внутренний ключ"
        "deactivateForumButton" = "Удалить выбранный форум"
        "deactivateAccountButton" = "Удалить выбранный аккаунт"
        "selectForumToDeactivate" = "Сначала выберите строку форума для удаления."
        "selectAccountToDeactivate" = "Сначала выберите строку аккаунта для удаления."
        "confirmDeactivateForum" = "Удалить этот форум из базы D1? Он больше не будет отображаться в форме."
        "confirmDeactivateAccount" = "Удалить этот аккаунт публикации из базы D1 и удалить его секреты Cloudflare? Он больше не будет отображаться в форме."
        "forumDeactivated" = "Форум успешно удален."
        "accountDeactivated" = "Аккаунт успешно удален."
        "mainAccountCannotDelete" = "Основной аккаунт публикации нельзя удалить из этой таблицы. Чтобы изменить его, введите новое имя пользователя и пароль в разделе проекта и нажмите Обновить установку."
        "cloudflareAuthFailed" = "Cloudflare не смог завершить авторизацию в браузере.`n`nЧто сделать:`n1. Снова нажмите Установить.`n2. Когда откроется Cloudflare, войдите и нажмите Разрешить.`n3. Не закрывайте эту вкладку, пока установщик не продолжит сам.`n`nЕсли снова не получится, временно сделайте Chrome или Edge браузером по умолчанию только на время установки и попробуйте еще раз."
        "workersDevSubdomainMissing" = "В этой учетной записи Cloudflare еще не создан поддомен workers.dev.`n`nCloudflare откроет страницу начальной настройки. Создайте поддомен workers.dev для учетной записи, затем снова запустите установщик. Уже созданная база D1 будет использована повторно, если имя совпадает."
        "cloudflarePrivateLogout" = "Закрытие предыдущей приватной сессии Cloudflare перед авторизацией..."
        "cloudflareNoPrivateBrowser" = "Не найден совместимый браузер для открытия Cloudflare в приватном окне. Установите или настройте Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox или Pale Moon."
        "cloudflarePrivateLoginFailed" = "Не удалось завершить приватную авторизацию Cloudflare. Закройте открытые окна авторизации и повторите попытку из установщика."
        "logComplete" = "Полный лог"
        "maintenanceNoChanges" = "Заполните хотя бы ключ, основной аккаунт, форум или дополнительный аккаунт перед нажатием Обслуживание."
        "maintenanceMainIncomplete" = "Чтобы обновить основной аккаунт публикации, укажите имя пользователя и пароль."
        "maintenanceAdminUpdated" = "Ключ панели управления обновлен."
        "maintenanceMainUpdated" = "Основной аккаунт публикации обновлен."
        "maintenanceDone" = "Обслуживание успешно завершено.`n`nПроект не переустанавливался: обновлены только необходимые Secrets и записи."
        "backupButton" = "💾  Копия D1"
        "backupCreated" = "Резервная копия D1 успешно создана:`n{0}"
        "backupAutoCreated" = "Автоматическая копия создана перед обслуживанием: {0}"
        "backupToolTip" = "Сохраняет .sql-копию связанной базы D1 в папке d1_backups."
    }
    "FR" = @{
        "languageLabel" = "Langue"
        "projectNameLabel" = "Nom technique du projet"
        "timezoneLabel" = "Fuseau horaire"
        "adminKeyLabel" = "Clé administrative du panneau"
        "hideAdminKey" = "Masquer la clé"
        "adminKeyWarning" = "IMPORTANT : conservez cette clé. Elle sera nécessaire pour accéder au panneau de contrôle."
        "startupTitle" = "Sélectionnez la langue de l'installateur"
        "startupDescription" = "La langue régionale de Windows est détectée lorsqu'elle est disponible. Vous pouvez la modifier avant de continuer."
        "startupContinue" = "Continuer"
        "legalBody" = "Projet Open Source, développé avec ChatGPT + la console Firefox, sous la supervision totale et après de multiples tests de Jucarese, Administrateur de Foroactivo. © 2026`nTous droits réservés. La reproduction, distribution, modification ou diffusion, totale ou partielle, est interdite sans autorisation expresse de l'auteur."
        "mainUserLabel" = "Compte principal de publication"
        "mainPassLabel" = "Mot de passe du compte principal"
        "note" = "Si Node.js n'est pas installé, il sera installé automatiquement via Windows Package Manager. Cloudflare ouvrira une seule fenêtre du navigateur si une autorisation est nécessaire."
        "logLabel" = "Détails techniques"
        "resultTitle" = "Installation terminée avec succès"
        "resultIntro" = "Conservez l'URL du Worker. Elle sera nécessaire pour continuer la configuration de Foroactivo avec la clé administrative."
        "resultUrlLabel" = "URL du Worker"
        "copyUrl" = "Copier l'URL"
        "urlCopied" = "URL copiée"
        "resultWarning" = "IMPORTANT : conservez cette URL et la clé administrative. Sans ces données, vous ne pourrez pas configurer le panneau ni le formulaire."
        "resultFiles" = "Un dossier a été préparé uniquement avec le HTML du formulaire, le HTML du panneau de contrôle et les instructions de la langue choisie."
        "openFiles" = "Ouvrir les fichiers Foroactivo"
        "finish" = "Terminer"
        "step1" = "Vérifier Node.js et les outils"
        "step2" = "Installer les dépendances du projet"
        "step3" = "Préparer la configuration Cloudflare"
        "step4" = "Vérifier la session Cloudflare"
        "step5" = "Publier le Worker"
        "step6" = "Appliquer les migrations D1"
        "step7" = "Enregistrer les identifiants et la clé"
        "step8" = "Enregistrer forums et comptes"
        "step9" = "Publier la configuration finale"
        "step10" = "Préparer les fichiers Foroactivo"
        "cloudflareSessionDetected" = "session actuelle détectée"
        "cloudflareAccountDetected" = "compte détecté : {0}"
        "cloudflareSessionTitle" = "Session Cloudflare"
        "cloudflareExistingSessionMessage" = "Wrangler a déjà une session Cloudflare active ({0}).`n`nCliquez sur Oui pour utiliser cette session et continuer.`nCliquez sur Non pour fermer la session Wrangler et autoriser un autre compte.`n`nL'installateur n'ouvrira pas de fenêtres supplémentaires : il ouvrira Cloudflare seulement si l'autorisation est vraiment nécessaire."
        "cloudflareBrowserChoiceMessage" = "Il n'y a pas de session technique Wrangler active, mais le navigateur peut déjà avoir un compte Cloudflare ouvert.`n`nCliquez sur Oui pour utiliser le compte déjà ouvert dans le navigateur.`nCliquez sur Non pour vous déconnecter ou changer de compte Cloudflare avant l'autorisation."
        "cloudflareAuthorizeTitle" = "Autoriser Cloudflare"
        "cloudflareAuthorizeMessage" = "Cloudflare s'ouvrira une seule fois pour autoriser l'installateur.`n`nSi le navigateur arrive directement sur un compte que vous ne voulez pas utiliser, annulez cette autorisation dans le navigateur, déconnectez-vous de Cloudflare dans cette même fenêtre, puis cliquez de nouveau sur Installer."
        "cloudflareSwitchAccountTitle" = "Changer de compte Cloudflare"
        "cloudflareSwitchAccountMessage" = "La session technique de Wrangler a été fermée et Cloudflare a été ouvert pour changer le compte du navigateur.`n`n1. Déconnectez-vous de Cloudflare si un compte que vous ne voulez pas utiliser apparaît.`n2. Connectez-vous avec le bon compte.`n3. Quand ce compte est prêt, revenez ici et cliquez sur OK.`n`nL'installateur ouvrira ensuite l'autorisation Cloudflare pour ce compte."
        "loadInstalledDataButton" = "Charger les données installées"
        "installedDataLoaded" = "Données installées chargées : {0} forum(s) actif(s) et {1} compte(s) actif(s)."
        "accountKeyColumn" = "Clé interne"
        "deactivateForumButton" = "Supprimer le forum sélectionné"
        "deactivateAccountButton" = "Supprimer le compte sélectionné"
        "selectForumToDeactivate" = "Sélectionnez une ligne de forum à supprimer."
        "selectAccountToDeactivate" = "Sélectionnez une ligne de compte à supprimer."
        "confirmDeactivateForum" = "Voulez-vous supprimer ce forum de la base D1 ? Il ne sera plus visible dans le formulaire."
        "confirmDeactivateAccount" = "Voulez-vous supprimer ce compte de publication de la base D1 et effacer ses secrets Cloudflare ? Il ne sera plus visible dans le formulaire."
        "forumDeactivated" = "Forum supprimé correctement."
        "accountDeactivated" = "Compte supprimé correctement."
        "mainAccountCannotDelete" = "Le compte de publication principal ne peut pas être supprimé depuis ce tableau. Pour le modifier, saisissez le nouvel utilisateur et le mot de passe dans la section du projet, puis cliquez sur Mettre à jour l installation."
        "cloudflareAuthFailed" = "Cloudflare n'a pas pu terminer l'autorisation dans le navigateur.`n`nQue faire :`n1. Cliquez de nouveau sur Installer.`n2. Quand Cloudflare s'ouvre, connectez-vous et cliquez sur Autoriser.`n3. Ne fermez pas cet onglet tant que l'installateur ne continue pas tout seul.`n`nSi cela échoue encore, utilisez Chrome ou Edge comme navigateur par défaut uniquement pendant l'installation, puis réessayez."
        "workersDevSubdomainMissing" = "Ce compte Cloudflare n a pas encore de sous-domaine workers.dev.`n`nCloudflare ouvrira la page de configuration initiale. Créez le sous-domaine workers.dev du compte, puis relancez l installateur. La base D1 déjà créée sera réutilisée si elle porte le même nom."
        "cloudflarePrivateLogout" = "Fermeture de toute session privée Cloudflare précédente avant l autorisation..."
        "cloudflareNoPrivateBrowser" = "Aucun navigateur compatible n'a été trouvé pour ouvrir Cloudflare en fenêtre privée. Installez ou configurez Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox ou Pale Moon."
        "cloudflarePrivateLoginFailed" = "L'autorisation privée de Cloudflare n'a pas pu être terminée. Fermez les fenêtres d'autorisation ouvertes et réessayez depuis l'installateur."
        "logComplete" = "Log complet"
        "maintenanceNoChanges" = "Renseignez au moins une clé, un compte principal, un forum ou un compte supplémentaire avant de cliquer sur Maintenance."
        "maintenanceMainIncomplete" = "Pour mettre à jour le compte principal de publication, renseignez utilisateur et mot de passe."
        "maintenanceAdminUpdated" = "Clé du panneau mise à jour."
        "maintenanceMainUpdated" = "Compte principal de publication mis à jour."
        "maintenanceDone" = "Maintenance terminée avec succès.`n`nLe projet n'a pas été réinstallé : seuls les Secrets et enregistrements nécessaires ont été mis à jour."
        "backupButton" = "💾  Copie D1"
        "backupCreated" = "Copie de sauvegarde D1 créée correctement :`n{0}"
        "backupAutoCreated" = "Copie automatique créée avant la maintenance : {0}"
        "backupToolTip" = "Enregistre une copie .sql de la base D1 liée dans le dossier d1_backups."
    }
    "DE" = @{
        "languageLabel" = "Sprache"
        "projectNameLabel" = "Technischer Projektname"
        "timezoneLabel" = "Zeitzone"
        "adminKeyLabel" = "Admin-Schlüssel des Kontrollpanels"
        "hideAdminKey" = "Schlüssel ausblenden"
        "adminKeyWarning" = "WICHTIG: Bewahren Sie diesen Schlüssel auf. Sie benötigen ihn später für das Kontrollpanel."
        "startupTitle" = "Sprache des Installers auswählen"
        "startupDescription" = "Die Windows-Regionalsprache wird erkannt, wenn sie unterstützt wird. Sie können sie vor dem Fortfahren ändern."
        "startupContinue" = "Fortfahren"
        "legalBody" = "Open-Source-Projekt, entwickelt mit ChatGPT + der Firefox-Konsole, unter vollständiger Aufsicht und mit zahlreichen Tests von Jucarese, Foroactivo-Administrator. © 2026`nAlle Rechte vorbehalten. Vervielfältigung, Verbreitung, Änderung oder Veröffentlichung, ganz oder teilweise, ist ohne ausdrückliche Genehmigung des Autors untersagt."
        "mainUserLabel" = "Hauptkonto für Veröffentlichungen"
        "mainPassLabel" = "Passwort des Hauptkontos"
        "note" = "Falls Node.js nicht installiert ist, wird es automatisch über Windows Package Manager installiert. Cloudflare öffnet nur bei Bedarf ein Browserfenster zur Autorisierung."
        "logLabel" = "Technische Details"
        "resultTitle" = "Installation erfolgreich abgeschlossen"
        "resultIntro" = "Speichern Sie die Worker-URL. Sie benötigen sie für die weitere Foroactivo-Einrichtung zusammen mit dem Admin-Schlüssel."
        "resultUrlLabel" = "Worker-URL"
        "copyUrl" = "URL kopieren"
        "urlCopied" = "URL kopiert"
        "resultWarning" = "WICHTIG: Speichern Sie diese URL und den Admin-Schlüssel. Ohne diese Daten können Panel und Formular nicht konfiguriert werden."
        "resultFiles" = "Ein Ordner wurde nur mit dem Formular-HTML, dem Kontrollpanel-HTML und den Anleitungen der gewählten Sprache vorbereitet."
        "openFiles" = "Foroactivo-Dateien öffnen"
        "finish" = "Fertig"
        "step1" = "Node.js und Werkzeuge prüfen"
        "step2" = "Projektabhängigkeiten installieren"
        "step3" = "Cloudflare-Konfiguration vorbereiten"
        "step4" = "Cloudflare-Sitzung prüfen"
        "step5" = "Worker veröffentlichen"
        "step6" = "D1-Migrationen anwenden"
        "step7" = "Zugangsdaten und Panel-Schlüssel speichern"
        "step8" = "Foren und zusätzliche Konten registrieren"
        "step9" = "Endgültige Konfiguration veröffentlichen"
        "step10" = "Foroactivo-Dateien vorbereiten"
        "cloudflareSessionDetected" = "aktuelle Sitzung erkannt"
        "cloudflareAccountDetected" = "erkanntes Konto: {0}"
        "cloudflareSessionTitle" = "Cloudflare-Sitzung"
        "cloudflareExistingSessionMessage" = "Wrangler hat bereits eine aktive Cloudflare-Sitzung ({0}).`n`nKlicken Sie auf Ja, um diese Sitzung zu verwenden und fortzufahren.`nKlicken Sie auf Nein, um die Wrangler-Sitzung zu schließen und ein anderes Konto zu autorisieren.`n`nDer Installer öffnet keine zusätzlichen Fenster: Cloudflare wird nur geöffnet, wenn eine Autorisierung wirklich nötig ist."
        "cloudflareBrowserChoiceMessage" = "Es gibt keine aktive technische Wrangler-Sitzung, aber im Browser kann bereits ein Cloudflare-Konto geöffnet sein.`n`nKlicken Sie auf Ja, um das im Browser geöffnete Konto zu verwenden.`nKlicken Sie auf Nein, um sich abzumelden oder das Cloudflare-Konto vor der Autorisierung zu wechseln."
        "cloudflareAuthorizeTitle" = "Cloudflare autorisieren"
        "cloudflareAuthorizeMessage" = "Cloudflare wird einmal geöffnet, um den Installer zu autorisieren.`n`nWenn der Browser direkt in ein Konto geht, das Sie nicht verwenden möchten, brechen Sie die Autorisierung im Browser ab, melden Sie sich in demselben Fenster bei Cloudflare ab und klicken Sie erneut auf Installieren."
        "cloudflareSwitchAccountTitle" = "Cloudflare-Konto wechseln"
        "cloudflareSwitchAccountMessage" = "Die technische Wrangler-Sitzung wurde geschlossen und Cloudflare wurde geöffnet, damit Sie das Browserkonto wechseln können.`n`n1. Melden Sie sich bei Cloudflare ab, wenn ein Konto angezeigt wird, das Sie nicht verwenden möchten.`n2. Melden Sie sich mit dem richtigen Konto an.`n3. Wenn dieses Konto bereit ist, kehren Sie hierher zurück und klicken Sie auf OK.`n`nDanach öffnet der Installer die Cloudflare-Autorisierung für dieses Konto."
        "loadInstalledDataButton" = "Installierte Daten laden"
        "installedDataLoaded" = "Installierte Daten geladen: {0} aktive Foren und {1} aktive Konten."
        "accountKeyColumn" = "Interner Schlüssel"
        "deactivateForumButton" = "Ausgewähltes Forum löschen"
        "deactivateAccountButton" = "Ausgewähltes Konto löschen"
        "selectForumToDeactivate" = "Wählen Sie zuerst eine Forum-Zeile zum Löschen aus."
        "selectAccountToDeactivate" = "Wählen Sie zuerst eine Konto-Zeile zum Löschen aus."
        "confirmDeactivateForum" = "Möchten Sie dieses Forum aus der D1-Datenbank löschen? Es erscheint nicht mehr im Formular."
        "confirmDeactivateAccount" = "Möchten Sie dieses Veröffentlichungskonto aus der D1-Datenbank löschen und seine Cloudflare-Secrets entfernen? Es erscheint nicht mehr im Formular."
        "forumDeactivated" = "Forum erfolgreich gelöscht."
        "accountDeactivated" = "Konto erfolgreich gelöscht."
        "mainAccountCannotDelete" = "Das Haupt-Veröffentlichungskonto kann nicht aus dieser Tabelle gelöscht werden. Um es zu ändern, geben Sie den neuen Benutzernamen und das Passwort im Projektbereich ein und klicken Sie auf Installation aktualisieren."
        "cloudflareAuthFailed" = "Cloudflare konnte die Autorisierung im Browser nicht abschließen.`n`nWas tun:`n1. Klicken Sie erneut auf Installieren.`n2. Wenn Cloudflare geöffnet wird, melden Sie sich an und klicken Sie auf Zulassen.`n3. Schließen Sie diesen Tab nicht, bis der Installer von selbst fortfährt.`n`nWenn es erneut fehlschlägt, verwenden Sie Chrome oder Edge nur während der Installation als Standardbrowser und versuchen Sie es erneut."
        "workersDevSubdomainMissing" = "Dieses Cloudflare-Konto hat noch keine workers.dev-Subdomain.`n`nCloudflare öffnet die Ersteinrichtungsseite. Erstellen Sie die workers.dev-Subdomain für das Konto und starten Sie danach den Installer erneut. Die bereits erstellte D1-Datenbank wird wiederverwendet, wenn sie denselben Namen hat."
        "cloudflarePrivateLogout" = "Vor der Autorisierung wird jede vorherige private Cloudflare-Sitzung geschlossen..."
        "cloudflareNoPrivateBrowser" = "Es wurde kein kompatibler Browser gefunden, um Cloudflare in einem privaten Fenster zu öffnen. Installieren oder konfigurieren Sie Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox oder Pale Moon."
        "cloudflarePrivateLoginFailed" = "Die private Cloudflare-Autorisierung konnte nicht abgeschlossen werden. Schließen Sie alle geöffneten Autorisierungsfenster und versuchen Sie es erneut über den Installer."
        "logComplete" = "Vollständiges Log"
        "maintenanceNoChanges" = "Füllen Sie mindestens einen Schlüssel, ein Hauptkonto, ein Forum oder ein zusätzliches Konto aus, bevor Sie Wartung klicken."
        "maintenanceMainIncomplete" = "Zum Aktualisieren des Hauptkontos müssen Benutzername und Passwort ausgefüllt werden."
        "maintenanceAdminUpdated" = "Kontrollpanel-Schlüssel aktualisiert."
        "maintenanceMainUpdated" = "Hauptkonto für Veröffentlichungen aktualisiert."
        "maintenanceDone" = "Wartung erfolgreich abgeschlossen.`n`nDas Projekt wurde nicht neu installiert: nur die erforderlichen Secrets und Einträge wurden aktualisiert."
        "backupButton" = "💾  D1-Kopie"
        "backupCreated" = "D1-Sicherung erfolgreich erstellt:`n{0}"
        "backupAutoCreated" = "Automatische Sicherung vor der Wartung erstellt: {0}"
        "backupToolTip" = "Speichert eine .sql-Kopie der verknüpften D1-Datenbank im Ordner d1_backups."
    }
    "RO" = @{
        "languageLabel" = "Limbă"
        "projectNameLabel" = "Numele tehnic al proiectului"
        "timezoneLabel" = "Fus orar"
        "adminKeyLabel" = "Cheie administrativă panou"
        "hideAdminKey" = "Ascunde cheia"
        "adminKeyWarning" = "IMPORTANT: păstrează această cheie. Vei avea nevoie de ea pentru panoul de control."
        "startupTitle" = "Selectează limba instalatorului"
        "startupDescription" = "Limba regională Windows este detectată când este disponibilă. O poți schimba înainte de a continua."
        "startupContinue" = "Continuă"
        "legalBody" = "Proiect Open Source, dezvoltat cu ChatGPT + consola Firefox, sub supravegherea totală și cu multiple teste de Jucarese, Administrator Foroactivo. © 2026`nToate drepturile rezervate. Reproducerea, distribuirea, modificarea sau publicarea, totală sau parțială, este interzisă fără autorizația expresă a autorului."
        "mainUserLabel" = "Cont principal de publicare"
        "mainPassLabel" = "Parola contului principal"
        "note" = "Dacă Node.js nu este instalat, va fi instalat automat prin Windows Package Manager. Cloudflare va deschide o singură fereastră de browser când este necesară autorizarea."
        "logLabel" = "Detalii tehnice"
        "resultTitle" = "Instalare finalizată cu succes"
        "resultIntro" = "Păstrează URL-ul Worker. Vei avea nevoie de el pentru configurarea Foroactivo împreună cu cheia administrativă."
        "resultUrlLabel" = "URL Worker"
        "copyUrl" = "Copiază URL"
        "urlCopied" = "URL copiat"
        "resultWarning" = "IMPORTANT: păstrează acest URL și cheia administrativă. Fără ele nu poți configura panoul sau formularul."
        "resultFiles" = "A fost pregătit un folder doar cu HTML-ul formularului, HTML-ul panoului de control și instrucțiunile limbii alese."
        "openFiles" = "Deschide fișierele Foroactivo"
        "finish" = "Finalizare"
        "step1" = "Verifică Node.js și instrumentele"
        "step2" = "Instalează dependențele proiectului"
        "step3" = "Pregătește configurarea Cloudflare"
        "step4" = "Verifică sesiunea Cloudflare"
        "step5" = "Publică Worker-ul"
        "step6" = "Aplică migrările D1"
        "step7" = "Salvează acreditările și cheia panoului"
        "step8" = "Înregistrează forumuri și conturi"
        "step9" = "Publică configurarea finală"
        "step10" = "Pregătește fișierele Foroactivo"
        "cloudflareSessionDetected" = "sesiune curentă detectată"
        "cloudflareAccountDetected" = "cont detectat: {0}"
        "cloudflareSessionTitle" = "Sesiune Cloudflare"
        "cloudflareExistingSessionMessage" = "Wrangler are deja o sesiune Cloudflare activă ({0}).`n`nApasă Da pentru a folosi această sesiune și a continua.`nApasă Nu pentru a închide sesiunea Wrangler și a autoriza alt cont.`n`nInstalatorul nu va deschide ferestre suplimentare: va deschide Cloudflare doar când autorizarea este cu adevărat necesară."
        "cloudflareBrowserChoiceMessage" = "Nu există o sesiune tehnică Wrangler activă, dar browserul poate avea deja un cont Cloudflare deschis.`n`nApasă Da pentru a folosi contul deja deschis în browser.`nApasă Nu pentru a te deconecta sau a schimba contul Cloudflare înainte de autorizare."
        "cloudflareAuthorizeTitle" = "Autorizează Cloudflare"
        "cloudflareAuthorizeMessage" = "Cloudflare se va deschide o singură dată pentru a autoriza instalatorul.`n`nDacă browserul intră direct într-un cont pe care nu vrei să îl folosești, anulează autorizarea în browser, deconectează-te de la Cloudflare în aceeași fereastră și apasă din nou Instalare."
        "cloudflareSwitchAccountTitle" = "Schimbă contul Cloudflare"
        "cloudflareSwitchAccountMessage" = "Sesiunea tehnică Wrangler a fost închisă și Cloudflare a fost deschis pentru a schimba contul din browser.`n`n1. Deconectează-te din Cloudflare dacă apare un cont pe care nu vrei să îl folosești.`n2. Autentifică-te cu contul corect.`n3. Când acel cont este gata, revino aici și apasă OK.`n`nApoi instalatorul va deschide autorizarea Cloudflare pentru acel cont."
        "loadInstalledDataButton" = "Încarcă datele instalate"
        "installedDataLoaded" = "Date instalate încărcate: {0} forumuri active și {1} conturi active."
        "accountKeyColumn" = "Cheie internă"
        "deactivateForumButton" = "Șterge forumul selectat"
        "deactivateAccountButton" = "Șterge contul selectat"
        "selectForumToDeactivate" = "Selectează mai întâi un rând de forum pentru ștergere."
        "selectAccountToDeactivate" = "Selectează mai întâi un rând de cont pentru ștergere."
        "confirmDeactivateForum" = "Vrei să ștergi acest forum din baza D1? Nu va mai apărea în formular."
        "confirmDeactivateAccount" = "Vrei să ștergi acest cont de publicare din baza D1 și să elimini secretele Cloudflare? Nu va mai apărea în formular."
        "forumDeactivated" = "Forumul a fost șters corect."
        "accountDeactivated" = "Contul a fost șters corect."
        "mainAccountCannotDelete" = "Contul principal de publicare nu poate fi șters din acest tabel. Pentru a-l schimba, introdu noul utilizator și parola în secțiunea proiectului și apasă Actualizează instalarea."
        "cloudflareAuthFailed" = "Cloudflare nu a putut finaliza autorizarea în browser.`n`nCe trebuie să faci:`n1. Apasă din nou Instalare.`n2. Când se deschide Cloudflare, autentifică-te și apasă Permite.`n3. Nu închide acea filă până când instalatorul continuă singur.`n`nDacă eșuează din nou, folosește Chrome sau Edge ca browser implicit doar pe durata instalării și încearcă din nou."
        "workersDevSubdomainMissing" = "Acest cont Cloudflare nu are încă un subdomeniu workers.dev.`n`nCloudflare va deschide pagina de configurare inițială. Creează subdomeniul workers.dev al contului, apoi rulează din nou instalatorul. Baza D1 deja creată va fi reutilizată dacă are același nume."
        "cloudflarePrivateLogout" = "Se închide orice sesiune privată Cloudflare anterioară înainte de autorizare..."
        "cloudflareNoPrivateBrowser" = "Nu s-a găsit un browser compatibil pentru a deschide Cloudflare într-o fereastră privată. Instalează sau configurează Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox sau Pale Moon."
        "cloudflarePrivateLoginFailed" = "Autorizarea privată Cloudflare nu a putut fi finalizată. Închide ferestrele de autorizare deschise și încearcă din nou din instalator."
        "logComplete" = "Log complet"
        "maintenanceNoChanges" = "Completează cel puțin o cheie, contul principal, un forum sau un cont suplimentar înainte de a apăsa Mentenanță."
        "maintenanceMainIncomplete" = "Pentru a actualiza contul principal de publicare, completează utilizatorul și parola."
        "maintenanceAdminUpdated" = "Cheia panoului a fost actualizată."
        "maintenanceMainUpdated" = "Contul principal de publicare a fost actualizat."
        "maintenanceDone" = "Mentenanță finalizată cu succes.`n`nProiectul nu a fost reinstalat: au fost actualizate doar Secrets și înregistrările necesare."
        "backupButton" = "💾  Copie D1"
        "backupCreated" = "Copia de siguranță D1 a fost creată corect:`n{0}"
        "backupAutoCreated" = "Copie automată creată înainte de mentenanță: {0}"
        "backupToolTip" = "Salvează o copie .sql a bazei D1 asociate în folderul d1_backups."
    }
    "NL" = @{
        "languageLabel" = "Taal"
        "projectNameLabel" = "Technische projectnaam"
        "timezoneLabel" = "Tijdzone"
        "adminKeyLabel" = "Administratieve sleutel van het paneel"
        "hideAdminKey" = "Sleutel verbergen"
        "adminKeyWarning" = "BELANGRIJK: bewaar deze sleutel. Je hebt hem later nodig om het controlepaneel te openen."
        "startupTitle" = "Selecteer de taal van de installer"
        "startupDescription" = "De Windows-taal wordt gebruikt wanneer die beschikbaar is. Je kunt de taal wijzigen voordat je verdergaat."
        "startupContinue" = "Doorgaan"
        "legalBody" = "Open Source Project, ontwikkeld met ChatGPT + de Firefox-console, onder volledige supervisie en met meerdere tests van Jucarese, Administrator van Foroactivo. © 2026`nAlle rechten voorbehouden. Reproductie, distributie, wijziging of publicatie, geheel of gedeeltelijk, is verboden zonder uitdrukkelijke toestemming van de auteur."
        "mainUserLabel" = "Hoofdaccount voor publicatie"
        "mainPassLabel" = "Wachtwoord van het hoofdaccount"
        "note" = "Als Node.js niet is geïnstalleerd, wordt het automatisch geïnstalleerd via Windows Package Manager. Cloudflare opent slechts één browservenster wanneer autorisatie nodig is."
        "logLabel" = "Technische details"
        "resultTitle" = "Installatie succesvol voltooid"
        "resultIntro" = "Bewaar de Worker-URL. Je hebt die nodig om de installatie in Actieforum te voltooien, samen met de administratieve sleutel die je in de installer hebt ingevoerd."
        "resultUrlLabel" = "Worker-URL"
        "copyUrl" = "URL kopiëren"
        "urlCopied" = "URL gekopieerd"
        "resultWarning" = "BELANGRIJK: bewaar deze URL en de administratieve sleutel. Zonder deze gegevens kun je het paneel en het formulier niet configureren."
        "resultFiles" = "Er is een map voorbereid met alleen de HTML van het formulier, het controlepaneel en de instructies in de gekozen taal. Open die map en kopieer elke code naar de bijbehorende HTML-pagina van Actieforum."
        "openFiles" = "Actieforum-bestanden openen"
        "finish" = "Voltooien"
        "step1" = "Node.js en tools controleren"
        "step2" = "Projectafhankelijkheden installeren"
        "step3" = "Cloudflare-configuratie voorbereiden"
        "step4" = "Cloudflare-sessie controleren"
        "step5" = "Worker publiceren"
        "step6" = "D1-migraties toepassen"
        "step7" = "Inloggegevens en paneelsleutel opslaan"
        "step8" = "Forums en extra accounts registreren"
        "step9" = "Definitieve configuratie publiceren"
        "step10" = "Actieforum-bestanden voorbereiden"
        "cloudflareSessionDetected" = "huidige sessie gedetecteerd"
        "cloudflareAccountDetected" = "account gedetecteerd: {0}"
        "cloudflareSessionTitle" = "Cloudflare-sessie"
        "cloudflareExistingSessionMessage" = "Wrangler heeft al een actieve Cloudflare-sessie ({0}).`n`nKlik Ja om deze sessie te gebruiken en door te gaan.`nKlik Nee om de Wrangler-sessie te sluiten en een ander account te autoriseren.`n`nDe installer opent geen extra vensters: Cloudflare wordt alleen geopend als autorisatie echt nodig is."
        "cloudflareBrowserChoiceMessage" = "Er is geen actieve technische Wrangler-sessie, maar de browser kan al een Cloudflare-account open hebben.`n`nKlik Ja als je het account wilt gebruiken dat al in de browser open is.`nKlik Nee als je wilt afmelden of van Cloudflare-account wilt wisselen voordat je autoriseert."
        "cloudflareAuthorizeTitle" = "Cloudflare autoriseren"
        "cloudflareAuthorizeMessage" = "Cloudflare wordt één keer geopend om de installer te autoriseren.`n`nAls de browser direct naar een account gaat dat je niet wilt gebruiken, annuleer dan de autorisatie in de browser, meld je in datzelfde venster af bij Cloudflare en klik opnieuw op Installeren."
        "cloudflareSwitchAccountTitle" = "Cloudflare-account wisselen"
        "cloudflareSwitchAccountMessage" = "De technische Wrangler-sessie is gesloten en Cloudflare is geopend om het browseraccount te wijzigen.`n`n1. Meld je af bij Cloudflare als er een account verschijnt dat je niet wilt gebruiken.`n2. Meld je aan met het juiste account.`n3. Wanneer dat account klaar is, keer je hier terug en klik je op OK.`n`nDaarna opent de installer de Cloudflare-autorisatie voor dat account."
        "loadInstalledDataButton" = "Geïnstalleerde gegevens laden"
        "installedDataLoaded" = "Geïnstalleerde gegevens geladen: {0} actieve forum(s) en {1} actieve account(s)."
        "accountKeyColumn" = "Interne sleutel"
        "deactivateForumButton" = "Geselecteerd forum verwijderen"
        "deactivateAccountButton" = "Geselecteerd account verwijderen"
        "selectForumToDeactivate" = "Selecteer eerst een forumrij om te verwijderen."
        "selectAccountToDeactivate" = "Selecteer eerst een accountrij om te verwijderen."
        "confirmDeactivateForum" = "Wil je dit forum uit de D1-database verwijderen? Het verschijnt niet meer in het formulier."
        "confirmDeactivateAccount" = "Wil je dit publicatieaccount uit de D1-database verwijderen en de Cloudflare-secrets wissen? Het verschijnt niet meer in het formulier."
        "forumDeactivated" = "Forum correct verwijderd."
        "accountDeactivated" = "Account correct verwijderd."
        "mainAccountCannotDelete" = "Het hoofdaccount voor publicatie wordt niet vanuit deze tabel verwijderd. Om het te wijzigen, vul je de nieuwe gebruiker en het wachtwoord in de projectsectie in en klik je op Installatie bijwerken."
        "cloudflareAuthFailed" = "Cloudflare kon de autorisatie in de browser niet afronden.`n`nWat te doen:`n1. Klik opnieuw op Installeren.`n2. Wanneer Cloudflare opent, meld je aan en klik je op Toestaan.`n3. Sluit dat tabblad niet totdat de installer zelf verdergaat.`n`nAls het opnieuw mislukt, gebruik dan Chrome of Edge tijdelijk als standaardbrowser tijdens de installatie en probeer opnieuw."
        "workersDevSubdomainMissing" = "Dit Cloudflare-account heeft nog geen workers.dev-subdomein.`n`nCloudflare opent de eerste configuratiepagina. Maak het workers.dev-subdomein voor het account aan en start daarna de installer opnieuw. De al gemaakte D1-database wordt hergebruikt als deze dezelfde naam heeft."
        "cloudflarePrivateLogout" = "Eerdere privé-Cloudflare-sessies worden gesloten vóór autorisatie..."
        "cloudflareNoPrivateBrowser" = "Er is geen compatibele browser gevonden om Cloudflare in een privévenster te openen. Installeer of configureer Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox of Pale Moon."
        "cloudflarePrivateLoginFailed" = "De privé-autorisatie van Cloudflare kon niet worden voltooid. Sluit alle geopende autorisatievensters en probeer het opnieuw vanuit de installer."
        "logComplete" = "Volledig logboek"
        "maintenanceNoChanges" = "Vul ten minste een sleutel, hoofdaccount, forum of extra account in voordat je op Onderhoud klikt."
        "maintenanceMainIncomplete" = "Om het hoofdaccount voor publicatie bij te werken, moet je gebruiker en wachtwoord invullen."
        "maintenanceAdminUpdated" = "Paneelsleutel bijgewerkt."
        "maintenanceMainUpdated" = "Hoofdaccount voor publicatie bijgewerkt."
        "maintenanceDone" = "Onderhoud succesvol voltooid.`n`nHet project is niet opnieuw geïnstalleerd: alleen de vereiste secrets en records zijn bijgewerkt."
        "backupButton" = "💾  D1-kopie"
        "backupCreated" = "D1-back-up succesvol gemaakt:`n{0}"
        "backupAutoCreated" = "Automatische back-up vóór onderhoud gemaakt: {0}"
        "backupToolTip" = "Slaat een .sql-kopie van de gekoppelde D1-database op in de map d1_backups."
    }
}


$script:InstallerRuntimeText = @{
    "ES" = @{
        "confirmNewInstallTitle" = "Confirmar nueva instalación"
        "confirmNewInstallMessage" = "Ya existe una instalación vinculada en esta carpeta.`n`nPara añadir foros, cuentas o actualizar contenido usa 'Actualizar instalación'.`n`n¿Quieres iniciar de todos modos una instalación nueva?"
        "workersSubdomainTitle" = "Subdominio workers.dev"
        "workersSubdomainHelp" = "Cloudflare necesita reservar un subdominio workers.dev para esta cuenta. Elige un nombre corto, en minúsculas, sin espacios ni tildes."
        "workersSubdomainError" = "Ese nombre no se pudo reservar. Prueba con otro."
        "actionHint" = "Elige una acción. Actualizar conserva el Worker y la base de datos vinculados."
        "updateToolTip" = "Añade foros, cuentas o actualiza contenido sin reinstalar el proyecto."
        "installToolTip" = "Crea un Worker y una base D1 para una instalación nueva."
    }
    "EN" = @{
        "confirmNewInstallTitle" = "Confirm new installation"
        "confirmNewInstallMessage" = "There is already a linked installation in this folder.`n`nTo add forums, accounts or update content, use 'Update installation'.`n`nDo you still want to start a new installation?"
        "workersSubdomainTitle" = "workers.dev subdomain"
        "workersSubdomainHelp" = "Cloudflare needs to reserve a workers.dev subdomain for this account. Choose a short lowercase name, without spaces or accents."
        "workersSubdomainError" = "That name could not be reserved. Try another one."
        "actionHint" = "Choose an action. Update keeps the linked Worker and database."
        "updateToolTip" = "Add forums, accounts or update content without reinstalling the project."
        "installToolTip" = "Creates a Worker and a D1 database for a new installation."
    }
    "PT" = @{
        "confirmNewInstallTitle" = "Confirmar nova instalação"
        "confirmNewInstallMessage" = "Já existe uma instalação vinculada nesta pasta.`n`nPara adicionar fóruns, contas ou atualizar conteúdo, use 'Atualizar instalação'.`n`nDeseja iniciar uma nova instalação mesmo assim?"
        "workersSubdomainTitle" = "Subdomínio workers.dev"
        "workersSubdomainHelp" = "O Cloudflare precisa reservar um subdomínio workers.dev para esta conta. Escolha um nome curto, em minúsculas, sem espaços nem acentos."
        "workersSubdomainError" = "Esse nome não pôde ser reservado. Tente outro."
        "actionHint" = "Escolha uma ação. Atualizar conserva o Worker e a base de dados vinculados."
        "updateToolTip" = "Adicione fóruns, contas ou atualize conteúdo sem reinstalar o projeto."
        "installToolTip" = "Cria um Worker e uma base D1 para uma nova instalação."
    }
    "IT" = @{
        "confirmNewInstallTitle" = "Conferma nuova installazione"
        "confirmNewInstallMessage" = "Esiste già un'installazione collegata in questa cartella.`n`nPer aggiungere forum, account o aggiornare contenuti, usa 'Aggiorna installazione'.`n`nVuoi comunque avviare una nuova installazione?"
        "workersSubdomainTitle" = "Sottodominio workers.dev"
        "workersSubdomainHelp" = "Cloudflare deve riservare un sottodominio workers.dev per questo account. Scegli un nome breve, minuscolo, senza spazi o accenti."
        "workersSubdomainError" = "Non è stato possibile riservare quel nome. Provane un altro."
        "actionHint" = "Scegli un'azione. Aggiorna conserva il Worker e il database collegati."
        "updateToolTip" = "Aggiungi forum, account o aggiorna contenuti senza reinstallare il progetto."
        "installToolTip" = "Crea un Worker e un database D1 per una nuova installazione."
    }
    "RU" = @{
        "confirmNewInstallTitle" = "Подтвердите новую установку"
        "confirmNewInstallMessage" = "В этой папке уже есть связанная установка.`n`nЧтобы добавить форумы, аккаунты или обновить содержимое, используйте 'Обновить установку'.`n`nВсе равно начать новую установку?"
        "workersSubdomainTitle" = "Поддомен workers.dev"
        "workersSubdomainHelp" = "Cloudflare должен зарезервировать поддомен workers.dev для этого аккаунта. Выберите короткое имя в нижнем регистре, без пробелов и акцентов."
        "workersSubdomainError" = "Это имя не удалось зарезервировать. Попробуйте другое."
        "actionHint" = "Выберите действие. Обновление сохраняет связанный Worker и базу данных."
        "updateToolTip" = "Добавляйте форумы, аккаунты или обновляйте содержимое без переустановки проекта."
        "installToolTip" = "Создает Worker и базу D1 для новой установки."
    }
    "FR" = @{
        "confirmNewInstallTitle" = "Confirmer la nouvelle installation"
        "confirmNewInstallMessage" = "Une installation liée existe déjà dans ce dossier.`n`nPour ajouter des forums, des comptes ou mettre à jour le contenu, utilisez 'Mettre à jour'.`n`nVoulez-vous quand même démarrer une nouvelle installation ?"
        "workersSubdomainTitle" = "Sous-domaine workers.dev"
        "workersSubdomainHelp" = "Cloudflare doit réserver un sous-domaine workers.dev pour ce compte. Choisissez un nom court, en minuscules, sans espaces ni accents."
        "workersSubdomainError" = "Ce nom n'a pas pu être réservé. Essayez-en un autre."
        "actionHint" = "Choisissez une action. La mise à jour conserve le Worker et la base de données liés."
        "updateToolTip" = "Ajoutez des forums, des comptes ou mettez à jour le contenu sans réinstaller le projet."
        "installToolTip" = "Crée un Worker et une base D1 pour une nouvelle installation."
    }
    "DE" = @{
        "confirmNewInstallTitle" = "Neue Installation bestätigen"
        "confirmNewInstallMessage" = "In diesem Ordner ist bereits eine verknüpfte Installation vorhanden.`n`nZum Hinzufügen von Foren, Konten oder zum Aktualisieren von Inhalten verwenden Sie 'Installation aktualisieren'.`n`nMöchten Sie trotzdem eine neue Installation starten?"
        "workersSubdomainTitle" = "workers.dev-Subdomain"
        "workersSubdomainHelp" = "Cloudflare muss für dieses Konto eine workers.dev-Subdomain reservieren. Wählen Sie einen kurzen Namen in Kleinbuchstaben, ohne Leerzeichen oder Akzente."
        "workersSubdomainError" = "Dieser Name konnte nicht reserviert werden. Versuchen Sie einen anderen."
        "actionHint" = "Wählen Sie eine Aktion. Aktualisieren behält den verknüpften Worker und die Datenbank."
        "updateToolTip" = "Fügen Sie Foren oder Konten hinzu oder aktualisieren Sie Inhalte, ohne das Projekt neu zu installieren."
        "installToolTip" = "Erstellt einen Worker und eine D1-Datenbank für eine neue Installation."
    }
    "RO" = @{
        "confirmNewInstallTitle" = "Confirmă instalarea nouă"
        "confirmNewInstallMessage" = "Există deja o instalare asociată în acest folder.`n`nPentru a adăuga forumuri, conturi sau a actualiza conținutul, folosește 'Actualizează instalarea'.`n`nVrei totuși să începi o instalare nouă?"
        "workersSubdomainTitle" = "Subdomeniu workers.dev"
        "workersSubdomainHelp" = "Cloudflare trebuie să rezerve un subdomeniu workers.dev pentru acest cont. Alege un nume scurt, cu litere mici, fără spații sau accente."
        "workersSubdomainError" = "Numele nu a putut fi rezervat. Încearcă altul."
        "actionHint" = "Alege o acțiune. Actualizarea păstrează Worker-ul și baza de date asociate."
        "updateToolTip" = "Adaugă forumuri, conturi sau actualizează conținutul fără să reinstalezi proiectul."
        "installToolTip" = "Creează un Worker și o bază D1 pentru o instalare nouă."
    }
    "NL" = @{
        "confirmNewInstallTitle" = "Nieuwe installatie bevestigen"
        "confirmNewInstallMessage" = "Er bestaat al een gekoppelde installatie in deze map.`n`nGebruik 'Installatie bijwerken' om forums of accounts toe te voegen of inhoud bij te werken.`n`nWil je toch een nieuwe installatie starten?"
        "workersSubdomainTitle" = "workers.dev-subdomein"
        "workersSubdomainHelp" = "Cloudflare moet een workers.dev-subdomein reserveren voor dit account. Kies een korte naam in kleine letters, zonder spaties of accenten."
        "workersSubdomainError" = "Die naam kon niet worden gereserveerd. Probeer een andere."
        "actionHint" = "Kies een actie. Bijwerken behoudt de gekoppelde Worker en database."
        "updateToolTip" = "Voeg forums of accounts toe of werk inhoud bij zonder het project opnieuw te installeren."
        "installToolTip" = "Maakt een Worker en een D1-database voor een nieuwe installatie."
    }
}

function Get-UiText([string]$key) {
    $text = $null
    if ($script:InstallerExtraText -and
        $script:InstallerExtraText.ContainsKey($script:CurrentLanguage) -and
        $script:InstallerExtraText[$script:CurrentLanguage].ContainsKey($key)) {
        $text = $script:InstallerExtraText[$script:CurrentLanguage][$key]
    }
    elseif ($script:InstallerRuntimeText -and
        $script:InstallerRuntimeText.ContainsKey($script:CurrentLanguage) -and
        $script:InstallerRuntimeText[$script:CurrentLanguage].ContainsKey($key)) {
        $text = $script:InstallerRuntimeText[$script:CurrentLanguage][$key]
    }
    elseif ($script:InstallerText[$script:CurrentLanguage].ContainsKey($key)) {
        $text = $script:InstallerText[$script:CurrentLanguage][$key]
    }
    elseif ($script:InstallerRuntimeText -and
        $script:InstallerRuntimeText.ContainsKey("ES") -and
        $script:InstallerRuntimeText["ES"].ContainsKey($key)) {
        $text = $script:InstallerRuntimeText["ES"][$key]
    }
    elseif ($script:InstallerExtraText -and
        $script:InstallerExtraText.ContainsKey("ES") -and
        $script:InstallerExtraText["ES"].ContainsKey($key)) {
        $text = $script:InstallerExtraText["ES"][$key]
    }
    else {
        $text = $script:InstallerText["ES"][$key]
    }

    if ($key -eq "legalBody") {
        return $text
    }

    return (Apply-ForumBrand $text)
}

function Get-ForumBrand([string]$lang) {
    switch ($lang) {
        "EN" { return "Forumotion" }
        "PT" { return "Forumeiros" }
        "IT" { return "Forumattivo" }
        "RU" { return "Forum2x2" }
        "FR" { return "Forumactif" }
        "DE" { return "Forumieren" }
        "RO" { return "Forumgratuit" }
        "NL" { return "Actieforum" }
        default { return "Foroactivo" }
    }
}

function Apply-ForumBrand([string]$text, [string]$lang = $script:CurrentLanguage) {
    if ($null -eq $text) { return $text }
    $brand = Get-ForumBrand $lang
    $brandUpper = $brand.ToUpperInvariant()
    return $text.
        Replace("FOROACTIVO", $brandUpper).
        Replace("FORUMOTION", $brandUpper).
        Replace("FORUMACTIF", $brandUpper).
        Replace("FORUMIEREN", $brandUpper).
        Replace("FORUMATTIVO", $brandUpper).
        Replace("FORUMEIROS", $brandUpper).
        Replace("FORUMGRATUIT", $brandUpper).
        Replace("FORUM2X2", $brandUpper).
        Replace("ACTIEFORUM", $brandUpper).
        Replace("Foroactivo", $brand).
        Replace("Forumotion", $brand).
        Replace("Forumactif", $brand).
        Replace("Forumieren", $brand).
        Replace("Forumattivo", $brand).
        Replace("Forumeiros", $brand).
        Replace("Forumgratuit", $brand).
        Replace("Forum2x2", $brand).
        Replace("Actieforum", $brand)
}

function Get-InstructionFileName([string]$lang) {
    switch ($lang) {
        "EN" { return "INSTALLATION_INSTRUCTIONS.txt" }
        "PT" { return "INSTRUCOES_DE_INSTALACAO.txt" }
        "IT" { return "ISTRUZIONI_DI_INSTALLAZIONE.txt" }
        "RU" { return "ИНСТРУКЦИИ_ПО_УСТАНОВКЕ.txt" }
        "FR" { return "INSTRUCTIONS_D_INSTALLATION.txt" }
        "DE" { return "INSTALLATIONSANLEITUNG.txt" }
        "RO" { return "INSTRUCTIUNI_DE_INSTALARE.txt" }
        "NL" { return "INSTALLATIE_INSTRUCTIES.txt" }
        default { return "INSTRUCCIONES_DE_INSTALACION.txt" }
    }
}

function Get-PanelFileName([string]$lang) {
    switch ($lang) {
        "EN" { return "CONTROL_PANEL.html" }
        "PT" { return "PAINEL_DE_CONTROLE.html" }
        "IT" { return "PANNELLO_DI_CONTROLLO.html" }
        "RU" { return "ПАНЕЛЬ_УПРАВЛЕНИЯ.html" }
        "FR" { return "PANNEAU_DE_CONTROLE.html" }
        "DE" { return "KONTROLLPANEL.html" }
        "RO" { return "PANOU_DE_CONTROL.html" }
        "NL" { return "CONTROLEPANEEL.html" }
        default { return "PANEL_DE_CONTROL.html" }
    }
}

function Get-FormFileName([string]$lang) {
    switch ($lang) {
        "EN" { return "SCHEDULING_FORM.html" }
        "PT" { return "FORMULARIO_DE_PROGRAMACAO.html" }
        "IT" { return "MODULO_DI_PROGRAMMAZIONE.html" }
        "RU" { return "ФОРМА_ПЛАНИРОВАНИЯ.html" }
        "FR" { return "FORMULAIRE_DE_PROGRAMMATION.html" }
        "DE" { return "PLANUNGSFORMULAR.html" }
        "RO" { return "FORMULAR_DE_PROGRAMARE.html" }
        "NL" { return "PLANNINGSFORMULIER.html" }
        default { return "FORMULARIO_DE_PROGRAMACION.html" }
    }
}

function Get-OutputFolderName([string]$lang) {
    switch ($lang) {
        "EN" { return "INSTALL_IN_FORUMOTION" }
        "PT" { return "INSTALAR_NO_FORUMEIROS" }
        "IT" { return "INSTALLA_IN_FORUMATTIVO" }
        "RU" { return "УСТАНОВИТЬ_В_FORUM2X2" }
        "FR" { return "INSTALLER_DANS_FORUMACTIF" }
        "DE" { return "IN_FORUMIEREN_INSTALLIEREN" }
        "RO" { return "INSTALARE_IN_FORUMGRATUIT" }
        "NL" { return "INSTALLEREN_IN_ACTIEFORUM" }
        default { return "INSTALAR_EN_FOROACTIVO" }
    }
}

function Set-InstallerOutputFolderForLanguage([string]$lang) {
    if (-not [string]::IsNullOrWhiteSpace($env:FOROACTIVO_INSTALLER_OUTPUT_DIR)) {
        $script:OutputFolder = $env:FOROACTIVO_INSTALLER_OUTPUT_DIR
    }
    else {
        $script:OutputFolder = Join-Path $script:OutputBaseFolder (Get-OutputFolderName $lang)
    }

    if (-not (Test-Path $script:OutputFolder)) {
        New-Item -ItemType Directory -Path $script:OutputFolder -Force | Out-Null
    }

    $script:LogPath = Join-Path $script:OutputFolder (Get-InstructionLogFileName $lang)
    Set-Content -LiteralPath $script:LogPath -Value ("Installer start: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8
}

function Get-InstructionLogFileName([string]$lang) {
    switch ($lang) {
        "EN" { return "INSTALLER_FORUMOTION_LOG.txt" }
        "PT" { return "INSTALADOR_FORUMEIROS_LOG.txt" }
        "IT" { return "INSTALLATORE_FORUMATTIVO_LOG.txt" }
        "RU" { return "ЛОГ_УСТАНОВЩИКА_FORUM2X2.txt" }
        "FR" { return "INSTALLATEUR_FORUMACTIF_LOG.txt" }
        "DE" { return "INSTALLER_FORUMIEREN_LOG.txt" }
        "RO" { return "INSTALATOR_FORUMGRATUIT_LOG.txt" }
        "NL" { return "INSTALLER_ACTIEFORUM_LOG.txt" }
        default { return "INSTALADOR_FOROACTIVO_LOG.txt" }
    }
}

function Get-LegalTitleForHtml([string]$lang) {
    switch ($lang) {
        "EN" { return "Authorship and terms of use" }
        "PT" { return "Autoria e condições de uso" }
        "IT" { return "Autoria e condizioni d'uso" }
        "RU" { return "Авторство и условия использования" }
        "FR" { return "Auteur et conditions d'utilisation" }
        "DE" { return "Urheberschaft und Nutzungsbedingungen" }
        "RO" { return "Autor și condiții de utilizare" }
        "NL" { return "Auteurschap en gebruiksvoorwaarden" }
        default { return "Autoría y condiciones de uso" }
    }
}

function Get-LegalBodyForHtml([string]$lang) {
    switch ($lang) {
        "EN" { return "Open Source Project, developed with ChatGPT + the Firefox console, under the full supervision and multiple tests of Jucarese, Foroactivo Administrator. © 2026`nAll rights reserved. Reproduction, distribution, modification or publication, in whole or in part, is prohibited without the author's express authorization." }
        "PT" { return "Projeto de Código Aberto, desenvolvido com ChatGPT + a consola do Firefox, com a supervisão total e múltiplos testes de Jucarese, Administrador de Foroactivo. © 2026`nTodos os direitos reservados. É proibida a reprodução, distribuição, modificação ou divulgação, total ou parcial, sem autorização expressa do autor." }
        "IT" { return "Progetto Open Source, sviluppato con ChatGPT + la console di Firefox, con la supervisione totale e molteplici test di Jucarese, Amministratore di Foroactivo. © 2026`nTutti i diritti riservati. È vietata la riproduzione, distribuzione, modifica o diffusione, totale o parziale, senza autorizzazione espressa dell'autore." }
        "RU" { return "Проект с открытым исходным кодом, разработанный с помощью ChatGPT + консоли Firefox, при полном надзоре и многочисленных тестах Jucarese, администратора Foroactivo. © 2026`nВсе права защищены. Воспроизведение, распространение, изменение или публикация, полностью или частично, запрещены без явного разрешения автора." }
        "FR" { return "Projet Open Source, développé avec ChatGPT + la console Firefox, sous la supervision totale et après de multiples tests de Jucarese, Administrateur de Foroactivo. © 2026`nTous droits réservés. La reproduction, distribution, modification ou diffusion, totale ou partielle, est interdite sans l'autorisation expresse de l'auteur." }
        "DE" { return "Open-Source-Projekt, entwickelt mit ChatGPT + der Firefox-Konsole, unter vollständiger Aufsicht und mit zahlreichen Tests von Jucarese, Foroactivo-Administrator. © 2026`nAlle Rechte vorbehalten. Vervielfältigung, Verbreitung, Änderung oder Veröffentlichung, ganz oder teilweise, ist ohne ausdrückliche Genehmigung des Autors verboten." }
        "RO" { return "Proiect Open Source, dezvoltat cu ChatGPT + consola Firefox, sub supravegherea totală și cu multiple teste de Jucarese, Administrator Foroactivo. © 2026`nToate drepturile rezervate. Reproducerea, distribuirea, modificarea sau publicarea, totală sau parțială, este interzisă fără autorizația expresă a autorului." }
        "NL" { return "Open Source Project, ontwikkeld met ChatGPT + de Firefox-console, onder volledige supervisie en met meerdere tests van Jucarese, Administrator van Foroactivo. © 2026`nAlle rechten voorbehouden. Reproductie, distributie, wijziging of publicatie, geheel of gedeeltelijk, is verboden zonder uitdrukkelijke toestemming van de auteur." }
        default { return "Proyecto de Código Abierto, desarrollado con ChatGPT + la consola de Firefox, con la supervisión total y múltiples pruebas de Jucarese, Administrador de Foroactivo. © 2026`nTodos los derechos reservados. Queda prohibida la reproducción, distribución, modificación o difusión, total o parcial, sin autorización expresa del autor." }
    }
}

function Get-GeneratedLanguageLabelForHtml([string]$lang) {
    switch ($lang) {
        "EN" { return "Generated language" }
        "PT" { return "Idioma gerado" }
        "IT" { return "Lingua generata" }
        "RU" { return "Сгенерированный язык" }
        "FR" { return "Langue générée" }
        "DE" { return "Generierte Sprache" }
        "RO" { return "Limba generată" }
        "NL" { return "Gegenereerde taal" }
        default { return "Idioma generado" }
    }
}

function Get-HtmlCommentText([string]$lang, [string]$key) {
    $comments = @{
        "ES" = @{
            "formIntro" = "Formulario multicuenta v1 para el gestor de publicaciones: SCEditor, emoticonos completos, Servimg y configuración inicial portable."
            "sceditorStyles" = "Estilos de SCEditor para Foroactivo"
            "sceditorIcons" = "Posiciones de iconos de SCEditor para Foroactivo"
            "compressedButtons" = "Evita botones comprimidos dentro del programador"
            "servimgPanel" = "Panel personalizado de Servimg cuando el comando nativo de Foroactivo no puede abrirse dentro de una página HTML."
            "sceditorVariables" = "Variables de SCEditor de Foroactivo usadas por los scripts originales."
            "toolbarString" = "Cadena local de la barra de herramientas. No se usa window.toolbar porque Foroactivo puede definirlo como objeto."
            "wysiwygInsert" = "Mejor ruta para el SCEditor antiguo de Foroactivo: insertar HTML directamente en WYSIWYG."
            "servimgParams" = "Es la misma estructura esencial de parámetros que usa el iframe de Servimg propio de Foroactivo."
        }
        "EN" = @{
            "formIntro" = "v1 multi-account form for the publication manager: SCEditor, full smileys, Servimg and portable first-run configuration."
            "sceditorStyles" = "Forumotion SCEditor styles"
            "sceditorIcons" = "Forumotion SCEditor icon positions"
            "compressedButtons" = "Prevent compressed buttons inside the scheduler"
            "servimgPanel" = "Custom Servimg panel used when the native Forumotion command cannot open inside an HTML page."
            "sceditorVariables" = "Forumotion SCEditor variables used by the original scripts."
            "toolbarString" = "Local toolbar string. Do not use window.toolbar because Forumotion may already define it as an object."
            "wysiwygInsert" = "Best path for old Forumotion SCEditor: insert HTML directly in WYSIWYG."
            "servimgParams" = "This is the same essential parameter structure used by Forumotion's own Servimg iframe."
        }
        "NL" = @{
            "formIntro" = "v1 multi-account formulier voor de publicatiemanager: SCEditor, volledige smileys, Servimg en draagbare eerste configuratie."
            "sceditorStyles" = "Actieforum SCEditor-stijlen"
            "sceditorIcons" = "Actieforum SCEditor-icoonposities"
            "compressedButtons" = "Voorkomt samengedrukte knoppen binnen de planner"
            "servimgPanel" = "Aangepast Servimg-paneel wanneer de native Actieforum-opdracht niet binnen een HTML-pagina kan openen."
            "sceditorVariables" = "Actieforum SCEditor-variabelen die door de originele scripts worden gebruikt."
            "toolbarString" = "Lokale werkbalkreeks. Gebruik window.toolbar niet, omdat Actieforum dit al als object kan definiëren."
            "wysiwygInsert" = "Beste route voor oude Actieforum SCEditor: HTML rechtstreeks invoegen in WYSIWYG."
            "servimgParams" = "Dit is dezelfde essentiële parameterstructuur die door Actieforum's eigen Servimg-iframe wordt gebruikt."
        }
        "PT" = @{
            "formIntro" = "Formulário multiconta v1 para o gestor de publicações: SCEditor, smileys completos, Servimg e configuração inicial portátil."
            "sceditorStyles" = "Estilos do SCEditor do Forumeiros"
            "sceditorIcons" = "Posições dos ícones do SCEditor do Forumeiros"
            "compressedButtons" = "Evita botões comprimidos dentro do programador"
            "servimgPanel" = "Painel Servimg personalizado usado quando o comando nativo do Forumeiros não consegue abrir dentro de uma página HTML."
            "sceditorVariables" = "Variáveis do SCEditor do Forumeiros usadas pelos scripts originais."
            "toolbarString" = "String local da barra de ferramentas. Não use window.toolbar porque o Forumeiros pode defini-la como objeto."
            "wysiwygInsert" = "Melhor caminho para o SCEditor antigo do Forumeiros: inserir HTML diretamente no WYSIWYG."
            "servimgParams" = "Esta é a mesma estrutura essencial de parâmetros usada pelo iframe Servimg próprio do Forumeiros."
        }
        "IT" = @{
            "formIntro" = "Modulo multi-account v1 per il gestore pubblicazioni: SCEditor, emoticon complete, Servimg e configurazione iniziale portabile."
            "sceditorStyles" = "Stili SCEditor di Forumattivo"
            "sceditorIcons" = "Posizioni delle icone SCEditor di Forumattivo"
            "compressedButtons" = "Evita pulsanti compressi dentro il programmatore"
            "servimgPanel" = "Pannello Servimg personalizzato usato quando il comando nativo di Forumattivo non può aprirsi dentro una pagina HTML."
            "sceditorVariables" = "Variabili SCEditor di Forumattivo usate dagli script originali."
            "toolbarString" = "Stringa locale della barra strumenti. Non usare window.toolbar perché Forumattivo potrebbe già definirla come oggetto."
            "wysiwygInsert" = "Percorso migliore per il vecchio SCEditor di Forumattivo: inserire HTML direttamente in WYSIWYG."
            "servimgParams" = "Questa è la stessa struttura essenziale dei parametri usata dall'iframe Servimg di Forumattivo."
        }
        "RU" = @{
            "formIntro" = "Мультиаккаунтная форма v1 для менеджера публикаций: SCEditor, полный набор смайлов, Servimg и переносимая начальная настройка."
            "sceditorStyles" = "Стили SCEditor для Forum2x2"
            "sceditorIcons" = "Позиции иконок SCEditor для Forum2x2"
            "compressedButtons" = "Предотвращает сжатие кнопок внутри планировщика"
            "servimgPanel" = "Пользовательская панель Servimg, когда встроенная команда Forum2x2 не может открыться внутри HTML-страницы."
            "sceditorVariables" = "Переменные SCEditor Forum2x2, используемые исходными скриптами."
            "toolbarString" = "Локальная строка панели инструментов. Не используйте window.toolbar, потому что Forum2x2 уже может определить ее как объект."
            "wysiwygInsert" = "Лучший путь для старого SCEditor Forum2x2: вставлять HTML напрямую в WYSIWYG."
            "servimgParams" = "Это та же основная структура параметров, которую использует собственный iframe Servimg в Forum2x2."
        }
        "FR" = @{
            "formIntro" = "Formulaire multi-comptes v1 pour le gestionnaire de publications : SCEditor, smileys complets, Servimg et configuration initiale portable."
            "sceditorStyles" = "Styles SCEditor de Forumactif"
            "sceditorIcons" = "Positions des icônes SCEditor de Forumactif"
            "compressedButtons" = "Évite les boutons comprimés dans le planificateur"
            "servimgPanel" = "Panneau Servimg personnalisé utilisé lorsque la commande native de Forumactif ne peut pas s'ouvrir dans une page HTML."
            "sceditorVariables" = "Variables SCEditor de Forumactif utilisées par les scripts originaux."
            "toolbarString" = "Chaîne locale de la barre d'outils. N'utilisez pas window.toolbar car Forumactif peut déjà la définir comme objet."
            "wysiwygInsert" = "Meilleure voie pour l'ancien SCEditor de Forumactif : insérer le HTML directement dans le WYSIWYG."
            "servimgParams" = "C'est la même structure essentielle de paramètres que celle utilisée par l'iframe Servimg propre à Forumactif."
        }
        "DE" = @{
            "formIntro" = "v1-Mehrkontenformular für den Veröffentlichungsmanager: SCEditor, vollständige Smileys, Servimg und portable Erstkonfiguration."
            "sceditorStyles" = "SCEditor-Stile für Forumieren"
            "sceditorIcons" = "SCEditor-Symbolpositionen für Forumieren"
            "compressedButtons" = "Verhindert zusammengedrückte Schaltflächen im Planer"
            "servimgPanel" = "Benutzerdefiniertes Servimg-Panel, wenn der native Forumieren-Befehl nicht innerhalb einer HTML-Seite geöffnet werden kann."
            "sceditorVariables" = "SCEditor-Variablen von Forumieren, die von den ursprünglichen Skripten verwendet werden."
            "toolbarString" = "Lokale Toolbar-Zeichenfolge. Verwenden Sie nicht window.toolbar, da Forumieren sie bereits als Objekt definieren kann."
            "wysiwygInsert" = "Bester Weg für den alten Forumieren-SCEditor: HTML direkt in WYSIWYG einfügen."
            "servimgParams" = "Dies ist dieselbe wesentliche Parameterstruktur, die vom Forumieren-eigenen Servimg-iframe verwendet wird."
        }
        "RO" = @{
            "formIntro" = "Formular multi-cont v1 pentru managerul de publicări: SCEditor, smiley-uri complete, Servimg și configurare inițială portabilă."
            "sceditorStyles" = "Stiluri SCEditor pentru Forumgratuit"
            "sceditorIcons" = "Poziții pictograme SCEditor pentru Forumgratuit"
            "compressedButtons" = "Previne butoanele comprimate în programator"
            "servimgPanel" = "Panou Servimg personalizat folosit când comanda nativă Forumgratuit nu se poate deschide într-o pagină HTML."
            "sceditorVariables" = "Variabile SCEditor Forumgratuit folosite de scripturile originale."
            "toolbarString" = "Șir local pentru bara de instrumente. Nu folosi window.toolbar deoarece Forumgratuit îl poate defini deja ca obiect."
            "wysiwygInsert" = "Cea mai bună cale pentru vechiul SCEditor Forumgratuit: inserează HTML direct în WYSIWYG."
            "servimgParams" = "Aceasta este aceeași structură esențială de parametri folosită de iframe-ul Servimg propriu Forumgratuit."
        }
    }

    if (-not $comments.ContainsKey($lang)) { $lang = "EN" }
    return $comments[$lang][$key]
}

function Get-FormRuntimeText([string]$lang, [string]$key) {
    $texts = @{
        "ES" = @{
            "searchSmiley" = "Buscar código de emoticono..."
            "serviceMissing" = "La dirección del servicio no está configurada."
            "configLoadError" = "No se pudo cargar la configuración del proyecto."
            "emptyPublicConfig" = "El instalador todavía no ha configurado foros de publicación ni cuentas."
            "publicConfigLoaded" = "Foros y cuentas publicadoras cargados."
            "configSavedLoading" = "Configuración guardada. Cargando foros y cuentas publicadoras..."
            "loadingPublicConfig" = "Cargando foros y cuentas publicadoras..."
            "configSavedListsError" = "Configuración guardada, pero no se pudieron cargar las listas: "
            "servimgOpenError" = "No se pudo abrir Servimg."
            "scriptLoadError" = "No se pudo cargar: "
            "postPageError" = "No se pudo abrir la página de publicación de Foroactivo para leer los datos de sesión de Servimg."
            "servimgMissing" = "No se encontraron datos de sesión de Servimg. Abre una página normal de nuevo tema una vez y vuelve a este formulario."
            "servimgLoading" = "Cargando Servimg..."
            "editorBlocked" = "No se pudo cargar SCEditor. Abre la consola del navegador y comprueba qué archivo SCEditor de Foroactivo está bloqueado o falta."
            "editorLoaded" = "Editor de Foroactivo cargado."
            "toolbarError" = "La barra de herramientas debe ser una cadena."
            "editorInitError" = "Error al inicializar SCEditor: "
            "formConfigFirst" = "Completa primero la configuración del formulario."
            "savingSchedule" = "Guardando programación..."
            "saving" = "Guardando..."
            "scheduleSaved" = "Programación guardada correctamente. Volviendo al tema de origen..."
            "httpError" = "Error HTTP "
            "unknownError" = "Error desconocido"
            "editorLoadPrefix" = "No se pudo cargar SCEditor: "
            "imageInserted" = "Imagen insertada en el editor."
            "imagePrompt" = "Pega la URL completa de la imagen:"
            "invalidImageUrl" = "La URL de imagen no es válida."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Ancho (Opcional):"
            "imageHeightLabel" = "Altura (Opcional):"
            "imageInsertButton" = "Insertar"
        }
        "EN" = @{
            "searchSmiley" = "Search smiley code..."
            "serviceMissing" = "The service address has not been configured."
            "configLoadError" = "Could not load project configuration."
            "emptyPublicConfig" = "The installer has not configured any publication forums or accounts yet."
            "publicConfigLoaded" = "Forums and publishing accounts loaded."
            "configSavedLoading" = "Configuration saved. Loading forums and publishing accounts..."
            "loadingPublicConfig" = "Loading forums and publishing accounts..."
            "configSavedListsError" = "Configuration saved, but the lists could not be loaded: "
            "servimgOpenError" = "Servimg could not be opened."
            "scriptLoadError" = "Could not load: "
            "postPageError" = "Could not open the Forumotion post page to read Servimg session data."
            "servimgMissing" = "Servimg session data was not found. Open a normal new-topic page once, then return to this form."
            "servimgLoading" = "Loading Servimg..."
            "editorBlocked" = "SCEditor could not be loaded. Open the browser console and check which Forumotion SCEditor file is blocked or missing."
            "editorLoaded" = "Forumotion editor loaded."
            "toolbarError" = "Toolbar must be a string."
            "editorInitError" = "SCEditor initialization failed: "
            "formConfigFirst" = "Complete the form configuration first."
            "savingSchedule" = "Saving schedule..."
            "saving" = "Saving..."
            "scheduleSaved" = "Schedule saved successfully. Returning to the forum index..."
            "httpError" = "HTTP error "
            "unknownError" = "Unknown error"
            "editorLoadPrefix" = "SCEditor could not be loaded: "
            "imageInserted" = "Image inserted in the editor."
            "imagePrompt" = "Paste the full image URL:"
            "invalidImageUrl" = "The image URL is not valid."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Width (optional):"
            "imageHeightLabel" = "Height (optional):"
            "imageInsertButton" = "Insert"
        }
        "NL" = @{
            "searchSmiley" = "Smileycode zoeken..."
            "serviceMissing" = "Het serviceadres is niet geconfigureerd."
            "configLoadError" = "Projectconfiguratie kon niet worden geladen."
            "emptyPublicConfig" = "De installer heeft nog geen publicatieforums of accounts geconfigureerd."
            "publicConfigLoaded" = "Forums en publicatieaccounts geladen."
            "configSavedLoading" = "Configuratie opgeslagen. Forums en publicatieaccounts worden geladen..."
            "loadingPublicConfig" = "Forums en publicatieaccounts laden..."
            "configSavedListsError" = "Configuratie opgeslagen, maar de lijsten konden niet worden geladen: "
            "servimgOpenError" = "Servimg kon niet worden geopend."
            "scriptLoadError" = "Kon niet laden: "
            "postPageError" = "Kon de Actieforum-publicatiepagina niet openen om Servimg-sessiegegevens te lezen."
            "servimgMissing" = "Servimg-sessiegegevens zijn niet gevonden. Open één keer een normale pagina voor een nieuw onderwerp en keer daarna terug naar dit formulier."
            "servimgLoading" = "Servimg laden..."
            "editorBlocked" = "SCEditor kon niet worden geladen. Open de browserconsole en controleer welk Actieforum SCEditor-bestand is geblokkeerd of ontbreekt."
            "editorLoaded" = "Actieforum-editor geladen."
            "toolbarError" = "De werkbalk moet een tekenreeks zijn."
            "editorInitError" = "Fout bij initialiseren van SCEditor: "
            "formConfigFirst" = "Voltooi eerst de formulierconfiguratie."
            "savingSchedule" = "Planning opslaan..."
            "saving" = "Opslaan..."
            "scheduleSaved" = "Planning succesvol opgeslagen. Terug naar de forumindex..."
            "httpError" = "HTTP-fout "
            "unknownError" = "Onbekende fout"
            "editorLoadPrefix" = "SCEditor kon niet worden geladen: "
            "imageInserted" = "Afbeelding ingevoegd in de editor."
            "imagePrompt" = "Plak de volledige afbeeldings-URL:"
            "invalidImageUrl" = "De afbeeldings-URL is ongeldig."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Breedte (optioneel):"
            "imageHeightLabel" = "Hoogte (optioneel):"
            "imageInsertButton" = "Invoegen"
        }
        "PT" = @{
            "searchSmiley" = "Pesquisar código do smiley..."
            "serviceMissing" = "O endereço do serviço não foi configurado."
            "configLoadError" = "Não foi possível carregar a configuração do projeto."
            "emptyPublicConfig" = "O instalador ainda não configurou fóruns de publicação nem contas."
            "publicConfigLoaded" = "Fóruns e contas publicadoras carregados."
            "configSavedLoading" = "Configuração guardada. Carregando fóruns e contas publicadoras..."
            "loadingPublicConfig" = "Carregando fóruns e contas publicadoras..."
            "configSavedListsError" = "Configuração guardada, mas não foi possível carregar as listas: "
            "servimgOpenError" = "Não foi possível abrir o Servimg."
            "scriptLoadError" = "Não foi possível carregar: "
            "postPageError" = "Não foi possível abrir a página de publicação do Forumeiros para ler os dados de sessão do Servimg."
            "servimgMissing" = "Os dados de sessão do Servimg não foram encontrados. Abra uma página normal de novo tópico uma vez e volte a este formulário."
            "servimgLoading" = "Carregando Servimg..."
            "editorBlocked" = "Não foi possível carregar o SCEditor. Abra a consola do navegador e verifique qual arquivo SCEditor do Forumeiros está bloqueado ou ausente."
            "editorLoaded" = "Editor do Forumeiros carregado."
            "toolbarError" = "A barra de ferramentas deve ser uma string."
            "editorInitError" = "Falha ao inicializar o SCEditor: "
            "formConfigFirst" = "Complete primeiro a configuração do formulário."
            "savingSchedule" = "Guardando programação..."
            "saving" = "Guardando..."
            "scheduleSaved" = "Programação guardada corretamente. Voltando ao índice do fórum..."
            "httpError" = "Erro HTTP "
            "unknownError" = "Erro desconhecido"
            "editorLoadPrefix" = "Não foi possível carregar o SCEditor: "
            "imageInserted" = "Imagem inserida no editor."
            "imagePrompt" = "Cole a URL completa da imagem:"
            "invalidImageUrl" = "A URL da imagem não é válida."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Largura (opcional):"
            "imageHeightLabel" = "Altura (opcional):"
            "imageInsertButton" = "Inserir"
        }
        "IT" = @{
            "searchSmiley" = "Cerca codice emoticon..."
            "serviceMissing" = "L'indirizzo del servizio non è stato configurato."
            "configLoadError" = "Impossibile caricare la configurazione del progetto."
            "emptyPublicConfig" = "L'installer non ha ancora configurato forum di pubblicazione o account."
            "publicConfigLoaded" = "Forum e account pubblicatori caricati."
            "configSavedLoading" = "Configurazione salvata. Caricamento forum e account pubblicatori..."
            "loadingPublicConfig" = "Caricamento forum e account pubblicatori..."
            "configSavedListsError" = "Configurazione salvata, ma non è stato possibile caricare gli elenchi: "
            "servimgOpenError" = "Impossibile aprire Servimg."
            "scriptLoadError" = "Impossibile caricare: "
            "postPageError" = "Impossibile aprire la pagina di pubblicazione di Forumattivo per leggere i dati di sessione Servimg."
            "servimgMissing" = "Dati di sessione Servimg non trovati. Apri una normale pagina di nuovo argomento una volta, poi torna a questo modulo."
            "servimgLoading" = "Caricamento Servimg..."
            "editorBlocked" = "Impossibile caricare SCEditor. Apri la console del browser e controlla quale file SCEditor di Forumattivo è bloccato o mancante."
            "editorLoaded" = "Editor Forumattivo caricato."
            "toolbarError" = "La barra degli strumenti deve essere una stringa."
            "editorInitError" = "Inizializzazione SCEditor non riuscita: "
            "formConfigFirst" = "Completa prima la configurazione del modulo."
            "savingSchedule" = "Salvataggio programmazione..."
            "saving" = "Salvataggio..."
            "scheduleSaved" = "Programmazione salvata correttamente. Ritorno all'indice del forum..."
            "httpError" = "Errore HTTP "
            "unknownError" = "Errore sconosciuto"
            "editorLoadPrefix" = "Impossibile caricare SCEditor: "
            "imageInserted" = "Immagine inserita nell'editor."
            "imagePrompt" = "Incolla l'URL completo dell'immagine:"
            "invalidImageUrl" = "L'URL dell'immagine non è valido."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Larghezza (opzionale):"
            "imageHeightLabel" = "Altezza (opzionale):"
            "imageInsertButton" = "Inserisci"
        }
        "RU" = @{
            "searchSmiley" = "Поиск кода смайла..."
            "serviceMissing" = "Адрес сервиса не настроен."
            "configLoadError" = "Не удалось загрузить конфигурацию проекта."
            "emptyPublicConfig" = "Установщик еще не настроил форумы публикации или аккаунты."
            "publicConfigLoaded" = "Форумы и аккаунты публикации загружены."
            "configSavedLoading" = "Конфигурация сохранена. Загрузка форумов и аккаунтов публикации..."
            "loadingPublicConfig" = "Загрузка форумов и аккаунтов публикации..."
            "configSavedListsError" = "Конфигурация сохранена, но не удалось загрузить списки: "
            "servimgOpenError" = "Не удалось открыть Servimg."
            "scriptLoadError" = "Не удалось загрузить: "
            "postPageError" = "Не удалось открыть страницу публикации Forum2x2 для чтения данных сессии Servimg."
            "servimgMissing" = "Данные сессии Servimg не найдены. Один раз откройте обычную страницу новой темы, затем вернитесь к этой форме."
            "servimgLoading" = "Загрузка Servimg..."
            "editorBlocked" = "Не удалось загрузить SCEditor. Откройте консоль браузера и проверьте, какой файл SCEditor Forum2x2 заблокирован или отсутствует."
            "editorLoaded" = "Редактор Forum2x2 загружен."
            "toolbarError" = "Панель инструментов должна быть строкой."
            "editorInitError" = "Ошибка инициализации SCEditor: "
            "formConfigFirst" = "Сначала завершите настройку формы."
            "savingSchedule" = "Сохранение расписания..."
            "saving" = "Сохранение..."
            "scheduleSaved" = "Расписание успешно сохранено. Возврат к индексу форума..."
            "httpError" = "Ошибка HTTP "
            "unknownError" = "Неизвестная ошибка"
            "editorLoadPrefix" = "Не удалось загрузить SCEditor: "
            "imageInserted" = "Изображение вставлено в редактор."
            "imagePrompt" = "Вставьте полный URL изображения:"
            "invalidImageUrl" = "URL изображения недействителен."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Ширина (необязательно):"
            "imageHeightLabel" = "Высота (необязательно):"
            "imageInsertButton" = "Вставить"
        }
        "FR" = @{
            "searchSmiley" = "Rechercher un code de smiley..."
            "serviceMissing" = "L'adresse du service n'a pas été configurée."
            "configLoadError" = "Impossible de charger la configuration du projet."
            "emptyPublicConfig" = "L'installateur n'a pas encore configuré de forums de publication ni de comptes."
            "publicConfigLoaded" = "Forums et comptes de publication chargés."
            "configSavedLoading" = "Configuration enregistrée. Chargement des forums et des comptes de publication..."
            "loadingPublicConfig" = "Chargement des forums et des comptes de publication..."
            "configSavedListsError" = "Configuration enregistrée, mais les listes n'ont pas pu être chargées : "
            "servimgOpenError" = "Impossible d'ouvrir Servimg."
            "scriptLoadError" = "Impossible de charger : "
            "postPageError" = "Impossible d'ouvrir la page de publication Forumactif pour lire les données de session Servimg."
            "servimgMissing" = "Données de session Servimg introuvables. Ouvrez une page normale de nouveau sujet une fois, puis revenez à ce formulaire."
            "servimgLoading" = "Chargement de Servimg..."
            "editorBlocked" = "Impossible de charger SCEditor. Ouvrez la console du navigateur et vérifiez quel fichier SCEditor de Forumactif est bloqué ou manquant."
            "editorLoaded" = "Éditeur Forumactif chargé."
            "toolbarError" = "La barre d'outils doit être une chaîne."
            "editorInitError" = "Échec de l'initialisation de SCEditor : "
            "formConfigFirst" = "Complétez d'abord la configuration du formulaire."
            "savingSchedule" = "Enregistrement de la programmation..."
            "saving" = "Enregistrement..."
            "scheduleSaved" = "Programmation enregistrée correctement. Retour à l'index du forum..."
            "httpError" = "Erreur HTTP "
            "unknownError" = "Erreur inconnue"
            "editorLoadPrefix" = "Impossible de charger SCEditor : "
            "imageInserted" = "Image insérée dans l'éditeur."
            "imagePrompt" = "Collez l'URL complète de l'image :"
            "invalidImageUrl" = "L'URL de l'image n'est pas valide."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Largeur (facultatif) :"
            "imageHeightLabel" = "Hauteur (facultatif) :"
            "imageInsertButton" = "Insérer"
        }
        "DE" = @{
            "searchSmiley" = "Smiley-Code suchen..."
            "serviceMissing" = "Die Serviceadresse wurde nicht konfiguriert."
            "configLoadError" = "Projektkonfiguration konnte nicht geladen werden."
            "emptyPublicConfig" = "Der Installer hat noch keine Veröffentlichungsforen oder Konten konfiguriert."
            "publicConfigLoaded" = "Foren und Veröffentlichungskonten geladen."
            "configSavedLoading" = "Konfiguration gespeichert. Foren und Veröffentlichungskonten werden geladen..."
            "loadingPublicConfig" = "Foren und Veröffentlichungskonten werden geladen..."
            "configSavedListsError" = "Konfiguration gespeichert, aber die Listen konnten nicht geladen werden: "
            "servimgOpenError" = "Servimg konnte nicht geöffnet werden."
            "scriptLoadError" = "Konnte nicht geladen werden: "
            "postPageError" = "Die Forumieren-Beitragsseite konnte nicht geöffnet werden, um Servimg-Sitzungsdaten zu lesen."
            "servimgMissing" = "Servimg-Sitzungsdaten wurden nicht gefunden. Öffnen Sie einmal eine normale Seite für ein neues Thema und kehren Sie dann zu diesem Formular zurück."
            "servimgLoading" = "Servimg wird geladen..."
            "editorBlocked" = "SCEditor konnte nicht geladen werden. Öffnen Sie die Browserkonsole und prüfen Sie, welche Forumieren-SCEditor-Datei blockiert ist oder fehlt."
            "editorLoaded" = "Forumieren-Editor geladen."
            "toolbarError" = "Die Toolbar muss eine Zeichenfolge sein."
            "editorInitError" = "SCEditor-Initialisierung fehlgeschlagen: "
            "formConfigFirst" = "Schließen Sie zuerst die Formularkonfiguration ab."
            "savingSchedule" = "Planung wird gespeichert..."
            "saving" = "Speichern..."
            "scheduleSaved" = "Planung erfolgreich gespeichert. Rückkehr zur Forenübersicht..."
            "httpError" = "HTTP-Fehler "
            "unknownError" = "Unbekannter Fehler"
            "editorLoadPrefix" = "SCEditor konnte nicht geladen werden: "
            "imageInserted" = "Bild in den Editor eingefügt."
            "imagePrompt" = "Fügen Sie die vollständige Bild-URL ein:"
            "invalidImageUrl" = "Die Bild-URL ist ungültig."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Breite (optional):"
            "imageHeightLabel" = "Höhe (optional):"
            "imageInsertButton" = "Einfügen"
        }
        "RO" = @{
            "searchSmiley" = "Caută cod smiley..."
            "serviceMissing" = "Adresa serviciului nu a fost configurată."
            "configLoadError" = "Nu s-a putut încărca configurarea proiectului."
            "emptyPublicConfig" = "Instalatorul nu a configurat încă forumuri de publicare sau conturi."
            "publicConfigLoaded" = "Forumurile și conturile de publicare au fost încărcate."
            "configSavedLoading" = "Configurarea a fost salvată. Se încarcă forumurile și conturile de publicare..."
            "loadingPublicConfig" = "Se încarcă forumurile și conturile de publicare..."
            "configSavedListsError" = "Configurarea a fost salvată, dar listele nu au putut fi încărcate: "
            "servimgOpenError" = "Servimg nu a putut fi deschis."
            "scriptLoadError" = "Nu s-a putut încărca: "
            "postPageError" = "Nu s-a putut deschide pagina de publicare Forumgratuit pentru a citi datele sesiunii Servimg."
            "servimgMissing" = "Datele sesiunii Servimg nu au fost găsite. Deschide o pagină normală de subiect nou o dată, apoi revino la acest formular."
            "servimgLoading" = "Se încarcă Servimg..."
            "editorBlocked" = "SCEditor nu a putut fi încărcat. Deschide consola browserului și verifică ce fișier SCEditor Forumgratuit este blocat sau lipsește."
            "editorLoaded" = "Editor Forumgratuit încărcat."
            "toolbarError" = "Bara de instrumente trebuie să fie un șir."
            "editorInitError" = "Inițializarea SCEditor a eșuat: "
            "formConfigFirst" = "Completează mai întâi configurarea formularului."
            "savingSchedule" = "Se salvează programarea..."
            "saving" = "Se salvează..."
            "scheduleSaved" = "Programarea a fost salvată corect. Revenire la indexul forumului..."
            "httpError" = "Eroare HTTP "
            "unknownError" = "Eroare necunoscută"
            "editorLoadPrefix" = "SCEditor nu a putut fi încărcat: "
            "imageInserted" = "Imagine inserată în editor."
            "imagePrompt" = "Lipește URL-ul complet al imaginii:"
            "invalidImageUrl" = "URL-ul imaginii nu este valid."
            "imageUrlLabel" = "URL"
            "imageWidthLabel" = "Lățime (opțional):"
            "imageHeightLabel" = "Înălțime (opțional):"
            "imageInsertButton" = "Inserează"
        }
    }

    if (-not $texts.ContainsKey($lang)) { $lang = "EN" }
    return $texts[$lang][$key]
}

function Add-TextReplacement([hashtable]$map, [string]$from, [string]$to) {
    if (-not [string]::IsNullOrEmpty($from) -and -not $map.ContainsKey($from)) {
        $map[$from] = $to
    }
}

function Get-CronDelayNote([string]$lang) {
    $notes = @{
        "ES" = "El sistema usa la zona horaria seleccionada durante la instalación. El programador revisa cada minuto; Cloudflare puede lanzar el cron un poco después del minuto exacto, así que la publicación y la actualización del panel pueden tardar uno o dos minutos."
        "EN" = "The system uses the time zone selected during installation. The scheduler checks every minute; Cloudflare may launch the cron a little after the exact minute, so publication and panel refresh can take up to one or two minutes."
        "PT" = "O sistema usa o fuso horário selecionado durante a instalação. O programador verifica a cada minuto; o Cloudflare pode lançar o cron um pouco depois do minuto exato, por isso a publicação e a atualização do painel podem demorar um ou dois minutos."
        "IT" = "Il sistema usa il fuso orario scelto durante l'installazione. Il programmatore controlla ogni minuto; Cloudflare può avviare il cron poco dopo il minuto esatto, quindi la pubblicazione e l'aggiornamento del pannello possono richiedere uno o due minuti."
        "RU" = "Система использует часовой пояс, выбранный при установке. Планировщик проверяет каждую минуту; Cloudflare может запускать cron немного позже точной минуты, поэтому публикация и обновление панели могут занять одну-две минуты."
        "FR" = "Le système utilise le fuseau horaire choisi lors de l'installation. Le planificateur vérifie chaque minute ; Cloudflare peut lancer le cron légèrement après la minute exacte, donc la publication et l'actualisation du panneau peuvent prendre une ou deux minutes."
        "DE" = "Das System verwendet die bei der Installation gewählte Zeitzone. Der Planer prüft jede Minute; Cloudflare kann den Cron etwas nach der exakten Minute starten, daher können Veröffentlichung und Panel-Aktualisierung ein bis zwei Minuten dauern."
        "RO" = "Sistemul folosește fusul orar selectat la instalare. Programatorul verifică în fiecare minut; Cloudflare poate porni cron-ul puțin după minutul exact, deci publicarea și actualizarea panoului pot dura unul sau două minute."
        "NL" = "Het systeem gebruikt de tijdzone die tijdens de installatie is gekozen. De planner controleert elke minuut; Cloudflare kan de cron iets na de exacte minuut starten, dus publicatie en vernieuwing van het paneel kunnen een of twee minuten duren."
    }

    if (-not $notes.ContainsKey($lang)) { $lang = "EN" }
    return $notes[$lang]
}

function Get-DateInputFormat([string]$lang) {
    $formats = @{
        "ES" = "DD/MM/YYYY"
        "EN" = "MM/DD/YYYY"
        "PT" = "DD/MM/YYYY"
        "IT" = "DD/MM/YYYY"
        "FR" = "DD/MM/YYYY"
        "DE" = "DD.MM.YYYY"
        "RO" = "DD.MM.YYYY"
        "RU" = "DD.MM.YYYY"
        "NL" = "DD-MM-YYYY"
    }

    if (-not $formats.ContainsKey($lang)) { $lang = "EN" }
    return $formats[$lang]
}

function Get-DateFormatLabel([string]$lang) {
    $texts = @{
        "ES" = "Formato de fecha"
        "EN" = "Date format"
        "PT" = "Formato da data"
        "IT" = "Formato data"
        "FR" = "Format de date"
        "DE" = "Datumsformat"
        "RO" = "Format dată"
        "RU" = "Формат даты"
        "NL" = "Datumformaat"
    }

    if (-not $texts.ContainsKey($lang)) { $lang = "EN" }
    return $texts[$lang]
}

function Get-DateInputHelpTemplate([string]$lang) {
    $texts = @{
        "ES" = "Usa el formato {0}."
        "EN" = "Use {0} format."
        "PT" = "Use o formato {0}."
        "IT" = "Usa il formato {0}."
        "FR" = "Utilisez le format {0}."
        "DE" = "Verwenden Sie das Format {0}."
        "RO" = "Folosește formatul {0}."
        "RU" = "Используйте формат {0}."
        "NL" = "Gebruik het formaat {0}."
    }

    if (-not $texts.ContainsKey($lang)) { $lang = "EN" }
    return $texts[$lang]
}

function Get-DateInputHelp([string]$lang) {
    $format = Get-DateInputFormat $lang
    return (Get-DateInputHelpTemplate $lang).Replace("{0}", $format)
}

function Get-PanelRuntimeText([string]$lang, [string]$key) {
    $texts = @{
        "ES" = @{
            "invalidAdmin" = "Contraseña no válida."
            "missingAdminSecret" = "Falta configurar el Secret ADMIN_API_KEY."
        }
        "EN" = @{
            "invalidAdmin" = "Invalid admin key."
            "missingAdminSecret" = "The ADMIN_API_KEY Secret is not configured."
        }
        "PT" = @{
            "invalidAdmin" = "Chave administrativa inválida."
            "missingAdminSecret" = "Falta configurar o Secret ADMIN_API_KEY."
        }
        "IT" = @{
            "invalidAdmin" = "Chiave amministrativa non valida."
            "missingAdminSecret" = "Il Secret ADMIN_API_KEY non è configurato."
        }
        "RU" = @{
            "invalidAdmin" = "Недействительный административный ключ."
            "missingAdminSecret" = "Secret ADMIN_API_KEY не настроен."
        }
        "FR" = @{
            "invalidAdmin" = "Clé administrative non valide."
            "missingAdminSecret" = "Le Secret ADMIN_API_KEY n'est pas configuré."
        }
        "DE" = @{
            "invalidAdmin" = "Ungültiger Administrationsschlüssel."
            "missingAdminSecret" = "Das Secret ADMIN_API_KEY ist nicht konfiguriert."
        }
        "RO" = @{
            "invalidAdmin" = "Cheie administrativă nevalidă."
            "missingAdminSecret" = "Secretul ADMIN_API_KEY nu este configurat."
        }
        "NL" = @{
            "invalidAdmin" = "Ongeldige beheerderssleutel."
            "missingAdminSecret" = "De Secret ADMIN_API_KEY is niet geconfigureerd."
        }
    }

    if (-not $texts.ContainsKey($lang)) { $lang = "EN" }
    return $texts[$lang][$key]
}

function ConvertTo-JavaScriptString([string]$value) {
    if ($null -eq $value) { return "" }
    return $value.
        Replace("\", "\\").
        Replace('"', '\"').
        Replace("`r", "").
        Replace("`n", "\n")
}

function Get-StorageSuffix([string]$projectTitle) {
    $suffix = [Regex]::Replace([string]$projectTitle, "[^A-Za-z0-9_-]+", "_").Trim("_")
    if ([string]::IsNullOrWhiteSpace($suffix)) {
        return "default"
    }
    return $suffix.ToLowerInvariant()
}

function Get-LocalizedPhrase([string]$lang, [string]$key) {
    $phrases = @{
        "ES" = @{
            "manager" = "Gestor de publicaciones"; "schedulePost" = "Programar tema"; "formSubtitle" = "Formulario privado para programar temas automáticos en Foroactivo."; "settings" = "Ajustes"; "initialConfig" = "Configuración inicial"; "projectName" = "Nombre del proyecto"; "serviceAddress" = "Dirección del servicio"; "pasteWorker" = "Pega la dirección workers.dev creada durante la instalación."; "loadedAutomatically" = "Los foros destino y las cuentas publicadoras se cargan automáticamente desde el instalador del proyecto."; "refreshLists" = "Actualizar listas"; "cancel" = "Cancelar"; "saveConfig" = "Guardar configuración"; "backSource" = "← Volver al tema de origen"; "mainTopic" = "Datos principales del tema"; "topicTitle" = "Título del tema"; "minTitle0" = "Longitud mínima del título: 10 caracteres. Actual: 0."; "unlockHelp" = "El resto del formulario se desbloqueará cuando el título alcance 10 caracteres."; "topicContent" = "Contenido del tema"; "editorHelp" = "Usa el editor de Foroactivo para escribir el tema programado en formato BBCode."; "destination" = "Destino de publicación"; "targetForum" = "Foro destino"; "noForums" = "No hay foros destino configurados"; "forumUrlHelp" = "Usa la URL del foro donde debe publicarse el tema."; "publishingAccount" = "Cuenta publicadora"; "noAccounts" = "No hay cuentas publicadoras configuradas"; "accountHelp" = "La cuenta debe tener permiso para publicar en el foro seleccionado."; "dateTime" = "Fecha y hora"; "publicationDate" = "Fecha de publicación"; "publicationTime" = "Hora de publicación"; "hour" = "Hora"; "minutes" = "Minutos"; "timeFormat" = "Formato horario"; "format24" = "24 horas"; "format12" = "12 horas AM/PM"; "timeNote" = "El sistema usa la zona horaria seleccionada durante la instalación. El programador revisa cada minuto y publica cuando llega la hora programada."; "loadingEditor" = "Cargando editor de Foroactivo..."; "completeConfig" = "Completa primero la configuración del formulario."; "validWorker" = "Introduce una dirección workers.dev válida que comience por https://"; "title10" = "El título debe contener al menos 10 caracteres."; "contentRequired" = "El contenido del tema es obligatorio."; "selectForum" = "Selecciona un foro destino."; "selectAccount" = "Selecciona una cuenta publicadora."; "dateRequired" = "La fecha y hora de publicación son obligatorias."; "panelPrivate" = "Panel privado de administración"; "loginNote" = "Pulsa <strong>Entrar</strong>. El navegador te pedirá la clave en una ventana segura. Se admiten Ñ, tildes, espacios y símbolos. La contraseña no se guarda: solo se guarda su huella SHA-256 en este navegador para mantener la sesión al actualizar. Se elimina al pulsar Cerrar sesión."; "enter" = "Entrar"; "scheduledTopics" = "Temas programados"; "panelSubtitle" = "Consulta, edita, reprograma, publica o cancela temas."; "logout" = "Cerrar sesión"; "viewForum" = "Ver foro"; "pending" = "Pendientes"; "published" = "Publicados"; "cancelled" = "Cancelados"; "failed" = "Fallidos"; "search" = "Buscar por título, autor o URL..."; "allStatus" = "Todos los estados"; "paused" = "Pausados"; "processing" = "Procesando"; "refresh" = "Actualizar"; "records" = "registros"; "cleanup" = "Limpieza del panel:"; "deletePage" = "Eliminar registros de la página"; "clearHistory" = "Vaciar historial"; "loadingTopics" = "Cargando temas..."; "titleDest" = "Título y destino"; "scheduled" = "Programado"; "status" = "Estado"; "attempts" = "Intentos"; "publishedAt" = "Publicado"; "actions" = "Acciones"; "empty" = "No hay registros para mostrar."; "editTopic" = "Editar tema"; "close" = "Cerrar"; "title" = "Título"; "contentBBCode" = "Contenido BBCode"; "forumUrl" = "URL del foro destino"; "returnUrl" = "URL de retorno"; "saveChanges" = "Guardar cambios"; "adminPrompt" = "Introduce el valor exacto de la clave administrativa:"; "noKey" = "No has introducido ninguna clave."; "checking" = "Comprobando..."
        }
        "EN" = @{
            "manager" = "Publication manager"; "schedulePost" = "Schedule post"; "formSubtitle" = "Private form to schedule automatic topics on Forumotion."; "settings" = "Settings"; "initialConfig" = "Initial configuration"; "projectName" = "Project name"; "serviceAddress" = "Service address"; "pasteWorker" = "Paste the workers.dev address created during installation."; "loadedAutomatically" = "Target forums and publishing accounts are loaded automatically from the project installer."; "refreshLists" = "Refresh lists"; "cancel" = "Cancel"; "saveConfig" = "Save configuration"; "backSource" = "← Back to forum index"; "mainTopic" = "Main topic data"; "topicTitle" = "Topic title"; "minTitle0" = "Minimum title length: 10 characters. Current: 0."; "unlockHelp" = "The rest of the form will unlock when the title reaches 10 characters."; "topicContent" = "Topic content"; "editorHelp" = "Use the Forumotion editor to write the scheduled topic in BBCode format."; "destination" = "Publication destination"; "targetForum" = "Target forum"; "noForums" = "No target forums configured"; "forumUrlHelp" = "Use the forum URL where the topic must be published."; "publishingAccount" = "Publishing account"; "noAccounts" = "No publishing accounts configured"; "accountHelp" = "The account must have permission to post in the selected forum."; "dateTime" = "Date and time"; "publicationDate" = "Publication date"; "publicationTime" = "Publication time"; "hour" = "Hour"; "minutes" = "Minutes"; "timeFormat" = "Time format"; "format24" = "24-hour"; "format12" = "12-hour AM/PM"; "timeNote" = "The system uses the time zone selected during installation. The scheduler checks every minute and publishes when the scheduled time is reached."; "loadingEditor" = "Loading Forumotion editor..."; "completeConfig" = "Complete the form configuration first."; "validWorker" = "Enter a valid workers.dev address beginning with https://"; "title10" = "The title must contain at least 10 characters."; "contentRequired" = "Topic content is required."; "selectForum" = "Select a target forum."; "selectAccount" = "Select a publishing account."; "dateRequired" = "Publication date and time are required."; "panelPrivate" = "Private administration panel"; "loginNote" = "Click <strong>Enter</strong>. The browser will ask for the key in a secure window. Accents, spaces and symbols are accepted. The password is not saved: only its SHA-256 fingerprint is stored in this browser to keep the session after refresh. It is removed when you click Log out."; "enter" = "Enter"; "scheduledTopics" = "Scheduled topics"; "panelSubtitle" = "View, edit, reschedule, publish or cancel topics."; "logout" = "Log out"; "viewForum" = "View forum"; "pending" = "Pending"; "published" = "Published"; "cancelled" = "Cancelled"; "failed" = "Failed"; "search" = "Search by title, author or URL..."; "allStatus" = "All statuses"; "paused" = "Paused"; "processing" = "Processing"; "refresh" = "Refresh"; "records" = "records"; "cleanup" = "Panel cleanup:"; "deletePage" = "Delete page records"; "clearHistory" = "Clear history"; "loadingTopics" = "Loading topics..."; "titleDest" = "Title and destination"; "scheduled" = "Scheduled"; "status" = "Status"; "attempts" = "Attempts"; "publishedAt" = "Published"; "actions" = "Actions"; "empty" = "No records to show."; "editTopic" = "Edit topic"; "close" = "Close"; "title" = "Title"; "contentBBCode" = "BBCode content"; "forumUrl" = "Target forum URL"; "returnUrl" = "Return URL"; "saveChanges" = "Save changes"; "adminPrompt" = "Enter the exact admin key value:"; "noKey" = "You did not enter a key."; "checking" = "Checking..."
        }
        "PT" = @{
            "manager" = "Gestor de publicações"; "schedulePost" = "Programar tópico"; "formSubtitle" = "Formulário privado para programar tópicos automáticos no Forumeiros."; "settings" = "Definições"; "initialConfig" = "Configuração inicial"; "projectName" = "Nome do projeto"; "serviceAddress" = "Endereço do serviço"; "pasteWorker" = "Cole o endereço workers.dev criado durante a instalação."; "loadedAutomatically" = "Os fóruns de destino e as contas publicadoras são carregados automaticamente pelo instalador do projeto."; "refreshLists" = "Atualizar listas"; "cancel" = "Cancelar"; "saveConfig" = "Guardar configuração"; "backSource" = "← Voltar ao índice do fórum"; "mainTopic" = "Dados principais do tópico"; "topicTitle" = "Título do tópico"; "minTitle0" = "Tamanho mínimo do título: 10 caracteres. Atual: 0."; "unlockHelp" = "O restante formulário será desbloqueado quando o título atingir 10 caracteres."; "topicContent" = "Conteúdo do tópico"; "editorHelp" = "Use o editor do Forumeiros para escrever o tópico programado em formato BBCode."; "destination" = "Destino da publicação"; "targetForum" = "Fórum de destino"; "noForums" = "Não há fóruns de destino configurados"; "forumUrlHelp" = "Use a URL do fórum onde o tópico deve ser publicado."; "publishingAccount" = "Conta publicadora"; "noAccounts" = "Não há contas publicadoras configuradas"; "accountHelp" = "A conta deve ter permissão para publicar no fórum selecionado."; "dateTime" = "Data e hora"; "publicationDate" = "Data de publicação"; "publicationTime" = "Hora de publicação"; "hour" = "Hora"; "minutes" = "Minutos"; "timeFormat" = "Formato da hora"; "format24" = "24 horas"; "format12" = "12 horas AM/PM"; "timeNote" = "O sistema usa o fuso horário selecionado durante a instalação. O programador verifica a cada minuto e publica quando chega a hora programada."; "loadingEditor" = "Carregando editor do Forumeiros..."; "completeConfig" = "Complete primeiro a configuração do formulário."; "validWorker" = "Introduza um endereço workers.dev válido que comece por https://"; "title10" = "O título deve conter pelo menos 10 caracteres."; "contentRequired" = "O conteúdo do tópico é obrigatório."; "selectForum" = "Selecione um fórum de destino."; "selectAccount" = "Selecione uma conta publicadora."; "dateRequired" = "A data e hora de publicação são obrigatórias."; "panelPrivate" = "Painel privado de administração"; "loginNote" = "Clique em <strong>Entrar</strong>. O navegador pedirá a chave numa janela segura. São aceitos acentos, espaços e símbolos. A senha não é guardada: apenas a impressão SHA-256 fica neste navegador para manter a sessão ao atualizar. É removida ao clicar em Sair."; "enter" = "Entrar"; "scheduledTopics" = "Tópicos programados"; "panelSubtitle" = "Consulte, edite, reprograme, publique ou cancele tópicos."; "logout" = "Sair"; "viewForum" = "Ver fórum"; "pending" = "Pendentes"; "published" = "Publicados"; "cancelled" = "Cancelados"; "failed" = "Falhados"; "search" = "Pesquisar por título, autor ou URL..."; "allStatus" = "Todos os estados"; "paused" = "Pausados"; "processing" = "Processando"; "refresh" = "Atualizar"; "records" = "registros"; "cleanup" = "Limpeza do painel:"; "deletePage" = "Eliminar registros da página"; "clearHistory" = "Esvaziar histórico"; "loadingTopics" = "Carregando tópicos..."; "titleDest" = "Título e destino"; "scheduled" = "Programado"; "status" = "Estado"; "attempts" = "Tentativas"; "publishedAt" = "Publicado"; "actions" = "Ações"; "empty" = "Não há registros para mostrar."; "editTopic" = "Editar tópico"; "close" = "Fechar"; "title" = "Título"; "contentBBCode" = "Conteúdo BBCode"; "forumUrl" = "URL do fórum de destino"; "returnUrl" = "URL de retorno"; "saveChanges" = "Guardar alterações"; "adminPrompt" = "Introduza o valor exato da chave administrativa:"; "noKey" = "Não introduziu nenhuma chave."; "checking" = "Verificando..."
        }
        "IT" = @{
            "manager" = "Gestore pubblicazioni"; "schedulePost" = "Programma argomento"; "formSubtitle" = "Modulo privato per programmare argomenti automatici su Forumattivo."; "settings" = "Impostazioni"; "initialConfig" = "Configurazione iniziale"; "projectName" = "Nome del progetto"; "serviceAddress" = "Indirizzo del servizio"; "pasteWorker" = "Incolla l'indirizzo workers.dev creato durante l'installazione."; "loadedAutomatically" = "I forum di destinazione e gli account pubblicatori vengono caricati automaticamente dall'installer del progetto."; "refreshLists" = "Aggiorna elenchi"; "cancel" = "Annulla"; "saveConfig" = "Salva configurazione"; "backSource" = "← Torna all'indice del forum"; "mainTopic" = "Dati principali dell'argomento"; "topicTitle" = "Titolo dell'argomento"; "minTitle0" = "Lunghezza minima del titolo: 10 caratteri. Attuale: 0."; "unlockHelp" = "Il resto del modulo si sbloccherà quando il titolo raggiunge 10 caratteri."; "topicContent" = "Contenuto dell'argomento"; "editorHelp" = "Usa l'editor di Forumattivo per scrivere l'argomento programmato in formato BBCode."; "destination" = "Destinazione pubblicazione"; "targetForum" = "Forum di destinazione"; "noForums" = "Nessun forum di destinazione configurato"; "forumUrlHelp" = "Usa l'URL del forum in cui pubblicare l'argomento."; "publishingAccount" = "Account pubblicatore"; "noAccounts" = "Nessun account pubblicatore configurato"; "accountHelp" = "L'account deve avere il permesso di pubblicare nel forum selezionato."; "dateTime" = "Data e ora"; "publicationDate" = "Data pubblicazione"; "publicationTime" = "Ora pubblicazione"; "hour" = "Ora"; "minutes" = "Minuti"; "timeFormat" = "Formato orario"; "format24" = "24 ore"; "format12" = "12 ore AM/PM"; "timeNote" = "Il sistema usa il fuso orario scelto durante l'installazione. Il programmatore controlla ogni minuto e pubblica all'orario previsto."; "loadingEditor" = "Caricamento editor Forumattivo..."; "completeConfig" = "Completa prima la configurazione del modulo."; "validWorker" = "Inserisci un indirizzo workers.dev valido che inizi con https://"; "title10" = "Il titolo deve contenere almeno 10 caratteri."; "contentRequired" = "Il contenuto dell'argomento è obbligatorio."; "selectForum" = "Seleziona un forum di destinazione."; "selectAccount" = "Seleziona un account pubblicatore."; "dateRequired" = "Data e ora di pubblicazione sono obbligatorie."; "panelPrivate" = "Pannello privato di amministrazione"; "loginNote" = "Premi <strong>Entra</strong>. Il browser chiederà la chiave in una finestra sicura. Sono accettati accenti, spazi e simboli. La password non viene salvata: resta solo l'impronta SHA-256 in questo browser per mantenere la sessione dopo l'aggiornamento. Viene eliminata premendo Esci."; "enter" = "Entra"; "scheduledTopics" = "Argomenti programmati"; "panelSubtitle" = "Consulta, modifica, riprogramma, pubblica o annulla argomenti."; "logout" = "Esci"; "viewForum" = "Vedi forum"; "pending" = "In attesa"; "published" = "Pubblicati"; "cancelled" = "Annullati"; "failed" = "Falliti"; "search" = "Cerca per titolo, autore o URL..."; "allStatus" = "Tutti gli stati"; "paused" = "In pausa"; "processing" = "In elaborazione"; "refresh" = "Aggiorna"; "records" = "registri"; "cleanup" = "Pulizia pannello:"; "deletePage" = "Elimina registri della pagina"; "clearHistory" = "Svuota cronologia"; "loadingTopics" = "Caricamento argomenti..."; "titleDest" = "Titolo e destinazione"; "scheduled" = "Programmato"; "status" = "Stato"; "attempts" = "Tentativi"; "publishedAt" = "Pubblicato"; "actions" = "Azioni"; "empty" = "Nessun registro da mostrare."; "editTopic" = "Modifica argomento"; "close" = "Chiudi"; "title" = "Titolo"; "contentBBCode" = "Contenuto BBCode"; "forumUrl" = "URL forum di destinazione"; "returnUrl" = "URL di ritorno"; "saveChanges" = "Salva modifiche"; "adminPrompt" = "Inserisci il valore esatto della chiave amministrativa:"; "noKey" = "Non hai inserito alcuna chiave."; "checking" = "Verifica..."
        }
        "FR" = @{
            "manager" = "Gestionnaire de publications"; "schedulePost" = "Programmer un sujet"; "formSubtitle" = "Formulaire privé pour programmer des sujets automatiques sur Forumactif."; "settings" = "Paramètres"; "initialConfig" = "Configuration initiale"; "projectName" = "Nom du projet"; "serviceAddress" = "Adresse du service"; "pasteWorker" = "Collez l'adresse workers.dev créée pendant l'installation."; "loadedAutomatically" = "Les forums cibles et les comptes de publication sont chargés automatiquement depuis l'installateur du projet."; "refreshLists" = "Actualiser les listes"; "cancel" = "Annuler"; "saveConfig" = "Enregistrer la configuration"; "backSource" = "← Retour à l'index du forum"; "mainTopic" = "Données principales du sujet"; "topicTitle" = "Titre du sujet"; "minTitle0" = "Longueur minimale du titre : 10 caractères. Actuel : 0."; "unlockHelp" = "Le reste du formulaire sera déverrouillé quand le titre atteindra 10 caractères."; "topicContent" = "Contenu du sujet"; "editorHelp" = "Utilisez l'éditeur Forumactif pour rédiger le sujet programmé au format BBCode."; "destination" = "Destination de publication"; "targetForum" = "Forum cible"; "noForums" = "Aucun forum cible configuré"; "forumUrlHelp" = "Utilisez l'URL du forum où le sujet doit être publié."; "publishingAccount" = "Compte de publication"; "noAccounts" = "Aucun compte de publication configuré"; "accountHelp" = "Le compte doit avoir l'autorisation de publier dans le forum sélectionné."; "dateTime" = "Date et heure"; "publicationDate" = "Date de publication"; "publicationTime" = "Heure de publication"; "hour" = "Heure"; "minutes" = "Minutes"; "timeFormat" = "Format horaire"; "format24" = "24 heures"; "format12" = "12 heures AM/PM"; "timeNote" = "Le système utilise le fuseau horaire choisi lors de l'installation. Le planificateur vérifie chaque minute et publie à l'heure programmée."; "loadingEditor" = "Chargement de l'éditeur Forumactif..."; "completeConfig" = "Complétez d'abord la configuration du formulaire."; "validWorker" = "Saisissez une adresse workers.dev valide commençant par https://"; "title10" = "Le titre doit contenir au moins 10 caractères."; "contentRequired" = "Le contenu du sujet est obligatoire."; "selectForum" = "Sélectionnez un forum cible."; "selectAccount" = "Sélectionnez un compte de publication."; "dateRequired" = "La date et l'heure de publication sont obligatoires."; "panelPrivate" = "Panneau privé d'administration"; "loginNote" = "Cliquez sur <strong>Entrer</strong>. Le navigateur demandera la clé dans une fenêtre sécurisée. Accents, espaces et symboles sont acceptés. Le mot de passe n'est pas enregistré : seule son empreinte SHA-256 est conservée dans ce navigateur pour maintenir la session après actualisation. Elle est supprimée en cliquant sur Déconnexion."; "enter" = "Entrer"; "scheduledTopics" = "Sujets programmés"; "panelSubtitle" = "Consultez, modifiez, reprogrammez, publiez ou annulez des sujets."; "logout" = "Déconnexion"; "viewForum" = "Voir le forum"; "pending" = "En attente"; "published" = "Publiés"; "cancelled" = "Annulés"; "failed" = "Échoués"; "search" = "Rechercher par titre, auteur ou URL..."; "allStatus" = "Tous les états"; "paused" = "En pause"; "processing" = "En cours"; "refresh" = "Actualiser"; "records" = "enregistrements"; "cleanup" = "Nettoyage du panneau :"; "deletePage" = "Supprimer les enregistrements de la page"; "clearHistory" = "Vider l'historique"; "loadingTopics" = "Chargement des sujets..."; "titleDest" = "Titre et destination"; "scheduled" = "Programmé"; "status" = "État"; "attempts" = "Tentatives"; "publishedAt" = "Publié"; "actions" = "Actions"; "empty" = "Aucun enregistrement à afficher."; "editTopic" = "Modifier le sujet"; "close" = "Fermer"; "title" = "Titre"; "contentBBCode" = "Contenu BBCode"; "forumUrl" = "URL du forum cible"; "returnUrl" = "URL de retour"; "saveChanges" = "Enregistrer les modifications"; "adminPrompt" = "Saisissez la valeur exacte de la clé administrative :"; "noKey" = "Vous n'avez saisi aucune clé."; "checking" = "Vérification..."
        }
        "DE" = @{
            "manager" = "Veröffentlichungsmanager"; "schedulePost" = "Thema planen"; "formSubtitle" = "Privates Formular zum Planen automatischer Themen auf Forumieren."; "settings" = "Einstellungen"; "initialConfig" = "Erstkonfiguration"; "projectName" = "Projektname"; "serviceAddress" = "Serviceadresse"; "pasteWorker" = "Fügen Sie die während der Installation erstellte workers.dev-Adresse ein."; "loadedAutomatically" = "Zielforen und Veröffentlichungskonten werden automatisch aus dem Projektinstaller geladen."; "refreshLists" = "Listen aktualisieren"; "cancel" = "Abbrechen"; "saveConfig" = "Konfiguration speichern"; "backSource" = "← Zurück zur Forenübersicht"; "mainTopic" = "Hauptdaten des Themas"; "topicTitle" = "Thementitel"; "minTitle0" = "Mindestlänge des Titels: 10 Zeichen. Aktuell: 0."; "unlockHelp" = "Der Rest des Formulars wird freigeschaltet, wenn der Titel 10 Zeichen erreicht."; "topicContent" = "Themeninhalt"; "editorHelp" = "Verwenden Sie den Forumieren-Editor, um das geplante Thema im BBCode-Format zu schreiben."; "destination" = "Veröffentlichungsziel"; "targetForum" = "Zielforum"; "noForums" = "Keine Zielforen konfiguriert"; "forumUrlHelp" = "Verwenden Sie die URL des Forums, in dem das Thema veröffentlicht werden soll."; "publishingAccount" = "Veröffentlichungskonto"; "noAccounts" = "Keine Veröffentlichungskonten konfiguriert"; "accountHelp" = "Das Konto muss im ausgewählten Forum veröffentlichen dürfen."; "dateTime" = "Datum und Uhrzeit"; "publicationDate" = "Veröffentlichungsdatum"; "publicationTime" = "Veröffentlichungszeit"; "hour" = "Stunde"; "minutes" = "Minuten"; "timeFormat" = "Zeitformat"; "format24" = "24 Stunden"; "format12" = "12 Stunden AM/PM"; "timeNote" = "Das System verwendet die bei der Installation gewählte Zeitzone. Der Planer prüft jede Minute und veröffentlicht zur geplanten Zeit."; "loadingEditor" = "Forumieren-Editor wird geladen..."; "completeConfig" = "Schließen Sie zuerst die Formularkonfiguration ab."; "validWorker" = "Geben Sie eine gültige workers.dev-Adresse ein, die mit https:// beginnt"; "title10" = "Der Titel muss mindestens 10 Zeichen enthalten."; "contentRequired" = "Der Themeninhalt ist erforderlich."; "selectForum" = "Wählen Sie ein Zielforum."; "selectAccount" = "Wählen Sie ein Veröffentlichungskonto."; "dateRequired" = "Veröffentlichungsdatum und -zeit sind erforderlich."; "panelPrivate" = "Privates Administrationspanel"; "loginNote" = "Klicken Sie auf <strong>Eintreten</strong>. Der Browser fragt den Schlüssel in einem sicheren Fenster ab. Akzente, Leerzeichen und Symbole sind erlaubt. Das Passwort wird nicht gespeichert: Nur der SHA-256-Fingerabdruck bleibt in diesem Browser, um die Sitzung nach dem Aktualisieren zu behalten. Er wird beim Abmelden gelöscht."; "enter" = "Eintreten"; "scheduledTopics" = "Geplante Themen"; "panelSubtitle" = "Themen ansehen, bearbeiten, neu planen, veröffentlichen oder abbrechen."; "logout" = "Abmelden"; "viewForum" = "Forum ansehen"; "pending" = "Ausstehend"; "published" = "Veröffentlicht"; "cancelled" = "Abgebrochen"; "failed" = "Fehlgeschlagen"; "search" = "Nach Titel, Autor oder URL suchen..."; "allStatus" = "Alle Status"; "paused" = "Pausiert"; "processing" = "In Bearbeitung"; "refresh" = "Aktualisieren"; "records" = "Einträge"; "cleanup" = "Panelbereinigung:"; "deletePage" = "Seiteneinträge löschen"; "clearHistory" = "Verlauf leeren"; "loadingTopics" = "Themen werden geladen..."; "titleDest" = "Titel und Ziel"; "scheduled" = "Geplant"; "status" = "Status"; "attempts" = "Versuche"; "publishedAt" = "Veröffentlicht"; "actions" = "Aktionen"; "empty" = "Keine Einträge vorhanden."; "editTopic" = "Thema bearbeiten"; "close" = "Schließen"; "title" = "Titel"; "contentBBCode" = "BBCode-Inhalt"; "forumUrl" = "URL des Zielforums"; "returnUrl" = "Rückkehr-URL"; "saveChanges" = "Änderungen speichern"; "adminPrompt" = "Geben Sie den exakten Admin-Schlüssel ein:"; "noKey" = "Sie haben keinen Schlüssel eingegeben."; "checking" = "Prüfung..."
        }
        "RO" = @{
            "manager" = "Manager de publicări"; "schedulePost" = "Programează subiect"; "formSubtitle" = "Formular privat pentru programarea subiectelor automate pe Forumgratuit."; "settings" = "Setări"; "initialConfig" = "Configurare inițială"; "projectName" = "Numele proiectului"; "serviceAddress" = "Adresa serviciului"; "pasteWorker" = "Lipește adresa workers.dev creată în timpul instalării."; "loadedAutomatically" = "Forumurile destinație și conturile de publicare sunt încărcate automat din instalatorul proiectului."; "refreshLists" = "Actualizează liste"; "cancel" = "Anulează"; "saveConfig" = "Salvează configurarea"; "backSource" = "← Înapoi la indexul forumului"; "mainTopic" = "Date principale ale subiectului"; "topicTitle" = "Titlul subiectului"; "minTitle0" = "Lungime minimă titlu: 10 caractere. Actual: 0."; "unlockHelp" = "Restul formularului se va debloca atunci când titlul ajunge la 10 caractere."; "topicContent" = "Conținutul subiectului"; "editorHelp" = "Folosește editorul Forumgratuit pentru a scrie subiectul programat în format BBCode."; "destination" = "Destinația publicării"; "targetForum" = "Forum destinație"; "noForums" = "Nu există forumuri destinație configurate"; "forumUrlHelp" = "Folosește URL-ul forumului unde trebuie publicat subiectul."; "publishingAccount" = "Cont de publicare"; "noAccounts" = "Nu există conturi de publicare configurate"; "accountHelp" = "Contul trebuie să aibă permisiunea de a publica în forumul selectat."; "dateTime" = "Data și ora"; "publicationDate" = "Data publicării"; "publicationTime" = "Ora publicării"; "hour" = "Ora"; "minutes" = "Minute"; "timeFormat" = "Format orar"; "format24" = "24 de ore"; "format12" = "12 ore AM/PM"; "timeNote" = "Sistemul folosește fusul orar selectat la instalare. Programatorul verifică în fiecare minut și publică la ora programată."; "loadingEditor" = "Se încarcă editorul Forumgratuit..."; "completeConfig" = "Completează mai întâi configurarea formularului."; "validWorker" = "Introdu o adresă workers.dev validă care începe cu https://"; "title10" = "Titlul trebuie să conțină cel puțin 10 caractere."; "contentRequired" = "Conținutul subiectului este obligatoriu."; "selectForum" = "Selectează un forum destinație."; "selectAccount" = "Selectează un cont de publicare."; "dateRequired" = "Data și ora publicării sunt obligatorii."; "panelPrivate" = "Panou privat de administrare"; "loginNote" = "Apasă <strong>Intră</strong>. Browserul va cere cheia într-o fereastră securizată. Sunt acceptate accente, spații și simboluri. Parola nu se salvează: se păstrează doar amprenta SHA-256 în acest browser pentru menținerea sesiunii după reîmprospătare. Se șterge la deconectare."; "enter" = "Intră"; "scheduledTopics" = "Subiecte programate"; "panelSubtitle" = "Consultă, editează, reprogramează, publică sau anulează subiecte."; "logout" = "Deconectare"; "viewForum" = "Vezi forumul"; "pending" = "În așteptare"; "published" = "Publicate"; "cancelled" = "Anulate"; "failed" = "Eșuate"; "search" = "Caută după titlu, autor sau URL..."; "allStatus" = "Toate stările"; "paused" = "Pauzate"; "processing" = "În procesare"; "refresh" = "Actualizează"; "records" = "înregistrări"; "cleanup" = "Curățare panou:"; "deletePage" = "Șterge înregistrările paginii"; "clearHistory" = "Golește istoricul"; "loadingTopics" = "Se încarcă subiectele..."; "titleDest" = "Titlu și destinație"; "scheduled" = "Programat"; "status" = "Stare"; "attempts" = "Încercări"; "publishedAt" = "Publicat"; "actions" = "Acțiuni"; "empty" = "Nu există înregistrări de afișat."; "editTopic" = "Editează subiectul"; "close" = "Închide"; "title" = "Titlu"; "contentBBCode" = "Conținut BBCode"; "forumUrl" = "URL forum destinație"; "returnUrl" = "URL de retur"; "saveChanges" = "Salvează modificările"; "adminPrompt" = "Introdu valoarea exactă a cheii administrative:"; "noKey" = "Nu ai introdus nicio cheie."; "checking" = "Se verifică..."
        }
        "NL" = @{
            "manager" = "Publicatiebeheer"; "schedulePost" = "Onderwerp plannen"; "formSubtitle" = "Privéformulier om automatische onderwerpen op Actieforum te plannen."; "settings" = "Instellingen"; "initialConfig" = "Initiële configuratie"; "projectName" = "Projectnaam"; "serviceAddress" = "Serviceadres"; "pasteWorker" = "Plak het workers.dev-adres dat tijdens de installatie is aangemaakt."; "loadedAutomatically" = "Doelforums en publicatieaccounts worden automatisch geladen vanuit het projectinstallatieprogramma."; "refreshLists" = "Lijsten vernieuwen"; "cancel" = "Annuleren"; "saveConfig" = "Configuratie opslaan"; "backSource" = "← Terug naar forumindex"; "mainTopic" = "Hoofdgegevens van het onderwerp"; "topicTitle" = "Onderwerptitel"; "minTitle0" = "Minimale titellengte: 10 tekens. Huidig: 0."; "unlockHelp" = "De rest van het formulier wordt ontgrendeld zodra de titel 10 tekens bereikt."; "topicContent" = "Onderwerpinhoud"; "editorHelp" = "Gebruik de Actieforum-editor om het geplande onderwerp in BBCode-formaat te schrijven."; "destination" = "Publicatiebestemming"; "targetForum" = "Doelforum"; "noForums" = "Geen doelforums geconfigureerd"; "forumUrlHelp" = "Gebruik de URL van het forum waar het onderwerp moet worden gepubliceerd."; "publishingAccount" = "Publicatieaccount"; "noAccounts" = "Geen publicatieaccounts geconfigureerd"; "accountHelp" = "Het account moet toestemming hebben om in het geselecteerde forum te publiceren."; "dateTime" = "Datum en tijd"; "publicationDate" = "Publicatiedatum"; "publicationTime" = "Publicatietijd"; "hour" = "Uur"; "minutes" = "Minuten"; "timeFormat" = "Tijdnotatie"; "format24" = "24 uur"; "format12" = "12 uur AM/PM"; "timeNote" = "Het systeem gebruikt de tijdzone die tijdens de installatie is gekozen. De planner controleert elke minuut en publiceert zodra de geplande tijd is bereikt."; "loadingEditor" = "Actieforum-editor laden..."; "completeConfig" = "Voltooi eerst de formulierconfiguratie."; "validWorker" = "Voer een geldig workers.dev-adres in dat begint met https://"; "title10" = "De titel moet minimaal 10 tekens bevatten."; "contentRequired" = "De onderwerpinhoud is verplicht."; "selectForum" = "Selecteer een doelforum."; "selectAccount" = "Selecteer een publicatieaccount."; "dateRequired" = "Publicatiedatum en -tijd zijn verplicht."; "panelPrivate" = "Privébeheerpaneel"; "loginNote" = "Klik op <strong>Inloggen</strong>. De browser vraagt de sleutel in een beveiligd venster. Accenten, spaties en symbolen worden geaccepteerd. Het wachtwoord wordt niet opgeslagen: alleen de SHA-256-vingerafdruk blijft in deze browser bewaard om de sessie na vernieuwen te behouden. Deze wordt verwijderd wanneer u op Uitloggen klikt."; "enter" = "Inloggen"; "scheduledTopics" = "Geplande onderwerpen"; "panelSubtitle" = "Bekijk, bewerk, herplan, publiceer of annuleer onderwerpen."; "logout" = "Uitloggen"; "viewForum" = "Forum bekijken"; "pending" = "In behandeling"; "published" = "Gepubliceerd"; "cancelled" = "Geannuleerd"; "failed" = "Mislukt"; "search" = "Zoeken op titel, auteur of URL..."; "allStatus" = "Alle statussen"; "paused" = "Gepauzeerd"; "processing" = "Wordt verwerkt"; "refresh" = "Vernieuwen"; "records" = "records"; "cleanup" = "Paneel opschonen:"; "deletePage" = "Paginarrecords verwijderen"; "clearHistory" = "Geschiedenis wissen"; "loadingTopics" = "Onderwerpen laden..."; "titleDest" = "Titel en bestemming"; "scheduled" = "Gepland"; "status" = "Status"; "attempts" = "Pogingen"; "publishedAt" = "Gepubliceerd"; "actions" = "Acties"; "empty" = "Geen records om te tonen."; "editTopic" = "Onderwerp bewerken"; "close" = "Sluiten"; "title" = "Titel"; "contentBBCode" = "BBCode-inhoud"; "forumUrl" = "URL van doelforum"; "returnUrl" = "Retour-URL"; "saveChanges" = "Wijzigingen opslaan"; "adminPrompt" = "Voer de exacte waarde van de beheerderssleutel in:"; "noKey" = "U hebt geen sleutel ingevoerd."; "checking" = "Controleren..."
        }
        "RU" = @{
            "manager" = "Менеджер публикаций"; "schedulePost" = "Запланировать тему"; "formSubtitle" = "Приватная форма для автоматического планирования тем на Forum2x2."; "settings" = "Настройки"; "initialConfig" = "Начальная настройка"; "projectName" = "Название проекта"; "serviceAddress" = "Адрес сервиса"; "pasteWorker" = "Вставьте адрес workers.dev, созданный во время установки."; "loadedAutomatically" = "Целевые форумы и аккаунты публикации автоматически загружаются из установщика проекта."; "refreshLists" = "Обновить списки"; "cancel" = "Отмена"; "saveConfig" = "Сохранить настройки"; "backSource" = "← Вернуться к индексу форума"; "mainTopic" = "Основные данные темы"; "topicTitle" = "Заголовок темы"; "minTitle0" = "Минимальная длина заголовка: 10 символов. Сейчас: 0."; "unlockHelp" = "Остальная часть формы станет доступна, когда заголовок достигнет 10 символов."; "topicContent" = "Содержание темы"; "editorHelp" = "Используйте редактор Forum2x2 для написания запланированной темы в формате BBCode."; "destination" = "Место публикации"; "targetForum" = "Целевой форум"; "noForums" = "Целевые форумы не настроены"; "forumUrlHelp" = "Используйте URL форума, где должна быть опубликована тема."; "publishingAccount" = "Аккаунт публикации"; "noAccounts" = "Аккаунты публикации не настроены"; "accountHelp" = "Аккаунт должен иметь право публиковать в выбранном форуме."; "dateTime" = "Дата и время"; "publicationDate" = "Дата публикации"; "publicationTime" = "Время публикации"; "hour" = "Час"; "minutes" = "Минуты"; "timeFormat" = "Формат времени"; "format24" = "24 часа"; "format12" = "12 часов AM/PM"; "timeNote" = "Система использует часовой пояс, выбранный при установке. Планировщик проверяет каждую минуту и публикует в назначенное время."; "loadingEditor" = "Загрузка редактора Forum2x2..."; "completeConfig" = "Сначала завершите настройку формы."; "validWorker" = "Введите действительный адрес workers.dev, начинающийся с https://"; "title10" = "Заголовок должен содержать не менее 10 символов."; "contentRequired" = "Содержание темы обязательно."; "selectForum" = "Выберите целевой форум."; "selectAccount" = "Выберите аккаунт публикации."; "dateRequired" = "Дата и время публикации обязательны."; "panelPrivate" = "Приватная панель администрирования"; "loginNote" = "Нажмите <strong>Войти</strong>. Браузер запросит ключ в защищенном окне. Допускаются акценты, пробелы и символы. Пароль не сохраняется: в этом браузере хранится только отпечаток SHA-256 для сохранения сеанса после обновления. Он удаляется при выходе."; "enter" = "Войти"; "scheduledTopics" = "Запланированные темы"; "panelSubtitle" = "Просмотр, редактирование, перенос, публикация или отмена тем."; "logout" = "Выйти"; "viewForum" = "Открыть форум"; "pending" = "Ожидают"; "published" = "Опубликованы"; "cancelled" = "Отменены"; "failed" = "Ошибки"; "search" = "Поиск по заголовку, автору или URL..."; "allStatus" = "Все статусы"; "paused" = "На паузе"; "processing" = "Обработка"; "refresh" = "Обновить"; "records" = "записей"; "cleanup" = "Очистка панели:"; "deletePage" = "Удалить записи страницы"; "clearHistory" = "Очистить историю"; "loadingTopics" = "Загрузка тем..."; "titleDest" = "Заголовок и место"; "scheduled" = "Запланировано"; "status" = "Статус"; "attempts" = "Попытки"; "publishedAt" = "Опубликовано"; "actions" = "Действия"; "empty" = "Нет записей для отображения."; "editTopic" = "Редактировать тему"; "close" = "Закрыть"; "title" = "Заголовок"; "contentBBCode" = "Содержание BBCode"; "forumUrl" = "URL целевого форума"; "returnUrl" = "URL возврата"; "saveChanges" = "Сохранить изменения"; "adminPrompt" = "Введите точное значение административного ключа:"; "noKey" = "Ключ не введен."; "checking" = "Проверка..."
        }
    }

    if (-not $phrases.ContainsKey($lang)) { $lang = "ES" }
    return Apply-ForumBrand $phrases[$lang][$key] $lang
}

function Convert-LocalizedHtml([string]$sourcePath, [string]$lang, [string]$kind, [string]$projectTitle = "", [string]$workerUrl = "") {
    $html = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
    $map = @{}
    $smileyPanelTitles = @{
        "ES" = "Emoticonos"
        "EN" = "Emoticons"
        "PT" = "Emoticons"
        "IT" = "Emoticon"
        "RU" = "Смайлы"
        "FR" = "Émoticônes"
        "DE" = "Emoticons"
        "RO" = "Emoticoane"
        "NL" = "Emoticons"
    }
    if (-not $smileyPanelTitles.ContainsKey($lang)) { $smileyPanelTitles[$lang] = $smileyPanelTitles["EN"] }
    Add-TextReplacement $map "Emoticons" $smileyPanelTitles[$lang]

    $keys = @("manager","schedulePost","formSubtitle","settings","initialConfig","projectName","serviceAddress","pasteWorker","loadedAutomatically","refreshLists","cancel","saveConfig","backSource","mainTopic","topicTitle","minTitle0","unlockHelp","topicContent","editorHelp","destination","targetForum","noForums","forumUrlHelp","publishingAccount","noAccounts","accountHelp","dateTime","publicationDate","publicationTime","hour","minutes","timeFormat","format24","format12","timeNote","loadingEditor","completeConfig","validWorker","title10","contentRequired","selectForum","selectAccount","dateRequired","panelPrivate","loginNote","enter","scheduledTopics","panelSubtitle","logout","viewForum","pending","published","cancelled","failed","search","allStatus","paused","processing","refresh","records","cleanup","deletePage","clearHistory","loadingTopics","titleDest","scheduled","status","attempts","publishedAt","actions","empty","editTopic","close","title","contentBBCode","forumUrl","returnUrl","saveChanges","adminPrompt","noKey","checking")
    foreach ($key in $keys) {
        $value = Get-LocalizedPhrase $lang $key
        $english = Get-LocalizedPhrase "EN" $key
        $spanish = Get-LocalizedPhrase "ES" $key
        Add-TextReplacement $map $english $value
        Add-TextReplacement $map $spanish $value
    }

    $panelExtra = @{
        "EN" = @{
            "Pendiente" = "Pending"; "Pausado" = "Paused"; "Procesando" = "Processing"; "Publicado" = "Published"; "Fallido" = "Failed"; "Cancelado" = "Cancelled"
            "Editar" = "Edit"; "Publicar ahora" = "Publish now"; "Pausar" = "Pause"; "Reanudar" = "Resume"; "Ver tema" = "View topic"; "Eliminar del panel" = "Remove from panel"; "Sin acciones disponibles" = "No actions available"
            "Publicando..." = "Publishing..."; "Publicando el tema. Espera unos segundos..." = "Publishing the topic. Please wait a few seconds..."; "Tema publicado correctamente." = "Topic published successfully."
            "Tema pausado correctamente." = "Topic paused successfully."; "Tema reanudado correctamente." = "Topic resumed successfully."; "Tema cancelado correctamente." = "Topic cancelled successfully."; "Registro eliminado del panel." = "Record removed from the panel."
            "Selecciona al menos un estado para limpiar." = "Select at least one status to clean."; "No hay registros de esos estados en esta página." = "There are no records with those statuses on this page."; "Registros eliminados del panel." = "Records removed from the panel."; "Historial limpiado correctamente." = "History cleared successfully."
            "Completa todos los campos obligatorios." = "Complete all required fields."; "Guardando..." = "Saving..."; "Tema actualizado." = "Topic updated."; "Error inesperado al guardar: " = "Unexpected error while saving: "; "Editar tema #" = "Edit topic #"
            '¿Publicar ahora el tema "' = 'Publish the topic "'; '¿Pausar el tema "' = 'Pause the topic "'; '¿Reanudar el tema "' = 'Resume the topic "'; '¿Cancelar el tema "' = 'Cancel the topic "'; '¿Eliminar del panel el registro "' = 'Remove the record "'; "Solo se eliminará el registro del panel. " = "Only the panel record will be removed. "; "El tema del foro, si existe, NO se eliminará." = "The forum topic, if it exists, will NOT be deleted."
            "¿Eliminar del panel " = "Remove "; " registros de esta página?" = " records from this page?"; "No se eliminará ningún tema del foro." = "No forum topic will be deleted."; "Esto eliminará todos los registros publicados, cancelados y fallidos." = "This will delete all published, cancelled and failed records."; "Los pendientes, pausados y en proceso se conservarán." = "Pending, paused and processing records will be kept."; "Escribe ELIMINAR para continuar:" = "Type ELIMINAR to continue:"
            "Elimina solo los registros visibles en el panel según los filtros seleccionados. No borra temas del foro." = "Deletes only the records visible in the panel according to the selected filters. It does not delete topics from the forum."; "Elimina todo el historial finalizado del panel: registros publicados, cancelados y fallidos. Conserva pendientes, pausados y en proceso." = "Deletes all completed history from the panel: published, cancelled and failed records. Pending, paused and processing records are kept."
        }
        "PT" = @{
            "Pendiente" = "Pendente"; "Pausado" = "Pausado"; "Procesando" = "Processando"; "Publicado" = "Publicado"; "Fallido" = "Falhado"; "Cancelado" = "Cancelado"
            "Editar" = "Editar"; "Publicar ahora" = "Publicar agora"; "Pausar" = "Pausar"; "Reanudar" = "Retomar"; "Ver tema" = "Ver tópico"; "Eliminar del panel" = "Remover do painel"; "Sin acciones disponibles" = "Sem ações disponíveis"
            "Publicando..." = "Publicando..."; "Publicando el tema. Espera unos segundos..." = "Publicando o tópico. Aguarde alguns segundos..."; "Tema publicado correctamente." = "Tópico publicado com sucesso."
            "Tema pausado correctamente." = "Tópico pausado com sucesso."; "Tema reanudado correctamente." = "Tópico retomado com sucesso."; "Tema cancelado correctamente." = "Tópico cancelado com sucesso."; "Registro eliminado del panel." = "Registro removido do painel."
            "Selecciona al menos un estado para limpiar." = "Selecione pelo menos um estado para limpar."; "No hay registros de esos estados en esta página." = "Não há registros desses estados nesta página."; "Registros eliminados del panel." = "Registros removidos do painel."; "Historial limpiado correctamente." = "Histórico limpo com sucesso."
            "Completa todos los campos obligatorios." = "Preencha todos os campos obrigatórios."; "Guardando..." = "Guardando..."; "Tema actualizado." = "Tópico atualizado."; "Error inesperado al guardar: " = "Erro inesperado ao guardar: "; "Editar tema #" = "Editar tópico #"
            '¿Publicar ahora el tema "' = 'Publicar agora o tópico "'; '¿Pausar el tema "' = 'Pausar o tópico "'; '¿Reanudar el tema "' = 'Retomar o tópico "'; '¿Cancelar el tema "' = 'Cancelar o tópico "'; '¿Eliminar del panel el registro "' = 'Remover do painel o registro "'; "Solo se eliminará el registro del panel. " = "Só o registro do painel será removido. "; "El tema del foro, si existe, NO se eliminará." = "O tópico do fórum, se existir, NÃO será eliminado."
            "¿Eliminar del panel " = "Remover "; " registros de esta página?" = " registros desta página?"; "No se eliminará ningún tema del foro." = "Nenhum tópico do fórum será eliminado."; "Esto eliminará todos los registros publicados, cancelados y fallidos." = "Isto eliminará todos os registros publicados, cancelados e falhados."; "Los pendientes, pausados y en proceso se conservarán." = "Os pendentes, pausados e em processamento serão mantidos."; "Escribe ELIMINAR para continuar:" = "Escreva ELIMINAR para continuar:"
            "Elimina solo los registros visibles en el panel según los filtros seleccionados. No borra temas del foro." = "Elimina apenas os registros visíveis no painel conforme os filtros selecionados. Não apaga tópicos do fórum."; "Elimina todo el historial finalizado del panel: registros publicados, cancelados y fallidos. Conserva pendientes, pausados y en proceso." = "Elimina todo o histórico finalizado do painel: registros publicados, cancelados e falhados. Mantém pendentes, pausados e em processamento."
        }
        "IT" = @{
            "Pendiente" = "In attesa"; "Pausado" = "In pausa"; "Procesando" = "In elaborazione"; "Publicado" = "Pubblicato"; "Fallido" = "Fallito"; "Cancelado" = "Annullato"
            "Editar" = "Modifica"; "Publicar ahora" = "Pubblica ora"; "Pausar" = "Metti in pausa"; "Reanudar" = "Riprendi"; "Ver tema" = "Vedi argomento"; "Eliminar del panel" = "Rimuovi dal pannello"; "Sin acciones disponibles" = "Nessuna azione disponibile"
            "Publicando..." = "Pubblicazione..."; "Publicando el tema. Espera unos segundos..." = "Pubblicazione dell'argomento. Attendi qualche secondo..."; "Tema publicado correctamente." = "Argomento pubblicato correttamente."
            "Tema pausado correctamente." = "Argomento messo in pausa correttamente."; "Tema reanudado correctamente." = "Argomento ripreso correttamente."; "Tema cancelado correctamente." = "Argomento annullato correttamente."; "Registro eliminado del panel." = "Registro rimosso dal pannello."
            "Selecciona al menos un estado para limpiar." = "Seleziona almeno uno stato da pulire."; "No hay registros de esos estados en esta página." = "Non ci sono registri con questi stati in questa pagina."; "Registros eliminados del panel." = "Registri rimossi dal pannello."; "Historial limpiado correctamente." = "Cronologia svuotata correttamente."
            "Completa todos los campos obligatorios." = "Completa tutti i campi obbligatori."; "Guardando..." = "Salvataggio..."; "Tema actualizado." = "Argomento aggiornato."; "Error inesperado al guardar: " = "Errore imprevisto durante il salvataggio: "; "Editar tema #" = "Modifica argomento #"
            '¿Publicar ahora el tema "' = 'Pubblicare ora l''argomento "'; '¿Pausar el tema "' = 'Mettere in pausa l''argomento "'; '¿Reanudar el tema "' = 'Riprendere l''argomento "'; '¿Cancelar el tema "' = 'Annullare l''argomento "'; '¿Eliminar del panel el registro "' = 'Rimuovere dal pannello il registro "'; "Solo se eliminará el registro del panel. " = "Verrà rimosso solo il registro del pannello. "; "El tema del foro, si existe, NO se eliminará." = "L'argomento del forum, se esiste, NON verrà eliminato."
            "¿Eliminar del panel " = "Rimuovere "; " registros de esta página?" = " registri da questa pagina?"; "No se eliminará ningún tema del foro." = "Nessun argomento del forum verrà eliminato."; "Esto eliminará todos los registros publicados, cancelados y fallidos." = "Questo eliminerà tutti i registri pubblicati, annullati e falliti."; "Los pendientes, pausados y en proceso se conservarán." = "I registri in attesa, in pausa e in elaborazione saranno conservati."; "Escribe ELIMINAR para continuar:" = "Scrivi ELIMINAR per continuare:"
            "Elimina solo los registros visibles en el panel según los filtros seleccionados. No borra temas del foro." = "Elimina solo i registri visibili nel pannello in base ai filtri selezionati. Non elimina argomenti dal forum."; "Elimina todo el historial finalizado del panel: registros publicados, cancelados y fallidos. Conserva pendientes, pausados y en proceso." = "Elimina tutta la cronologia completata del pannello: registri pubblicati, annullati e falliti. Conserva quelli in attesa, in pausa e in elaborazione."
        }
        "FR" = @{
            "Pendiente" = "En attente"; "Pausado" = "En pause"; "Procesando" = "En traitement"; "Publicado" = "Publié"; "Fallido" = "Échoué"; "Cancelado" = "Annulé"
            "Editar" = "Modifier"; "Publicar ahora" = "Publier maintenant"; "Pausar" = "Mettre en pause"; "Reanudar" = "Reprendre"; "Ver tema" = "Voir le sujet"; "Eliminar del panel" = "Retirer du panneau"; "Sin acciones disponibles" = "Aucune action disponible"
            "Publicando..." = "Publication..."; "Publicando el tema. Espera unos segundos..." = "Publication du sujet. Patientez quelques secondes..."; "Tema publicado correctamente." = "Sujet publié correctement."
            "Tema pausado correctamente." = "Sujet mis en pause correctement."; "Tema reanudado correctamente." = "Sujet repris correctement."; "Tema cancelado correctamente." = "Sujet annulé correctement."; "Registro eliminado del panel." = "Enregistrement retiré du panneau."
            "Selecciona al menos un estado para limpiar." = "Sélectionnez au moins un état à nettoyer."; "No hay registros de esos estados en esta página." = "Aucun enregistrement avec ces états sur cette page."; "Registros eliminados del panel." = "Enregistrements retirés du panneau."; "Historial limpiado correctamente." = "Historique vidé correctement."
            "Completa todos los campos obligatorios." = "Complétez tous les champs obligatoires."; "Guardando..." = "Enregistrement..."; "Tema actualizado." = "Sujet mis à jour."; "Error inesperado al guardar: " = "Erreur inattendue lors de l'enregistrement : "; "Editar tema #" = "Modifier le sujet #"
            '¿Publicar ahora el tema "' = 'Publier maintenant le sujet "'; '¿Pausar el tema "' = 'Mettre en pause le sujet "'; '¿Reanudar el tema "' = 'Reprendre le sujet "'; '¿Cancelar el tema "' = 'Annuler le sujet "'; '¿Eliminar del panel el registro "' = 'Retirer du panneau l''enregistrement "'; "Solo se eliminará el registro del panel. " = "Seul l'enregistrement du panneau sera retiré. "; "El tema del foro, si existe, NO se eliminará." = "Le sujet du forum, s'il existe, ne sera PAS supprimé."
            "¿Eliminar del panel " = "Retirer "; " registros de esta página?" = " enregistrements de cette page ?"; "No se eliminará ningún tema del foro." = "Aucun sujet du forum ne sera supprimé."; "Esto eliminará todos los registros publicados, cancelados y fallidos." = "Cela supprimera tous les enregistrements publiés, annulés et échoués."; "Los pendientes, pausados y en proceso se conservarán." = "Les éléments en attente, en pause et en traitement seront conservés."; "Escribe ELIMINAR para continuar:" = "Tapez ELIMINAR pour continuer :"
            "Elimina solo los registros visibles en el panel según los filtros seleccionados. No borra temas del foro." = "Supprime uniquement les enregistrements visibles dans le panneau selon les filtres sélectionnés. Ne supprime aucun sujet du forum."; "Elimina todo el historial finalizado del panel: registros publicados, cancelados y fallidos. Conserva pendientes, pausados y en proceso." = "Supprime tout l'historique terminé du panneau : enregistrements publiés, annulés et échoués. Conserve les éléments en attente, en pause et en traitement."
        }
        "DE" = @{
            "Pendiente" = "Ausstehend"; "Pausado" = "Pausiert"; "Procesando" = "In Bearbeitung"; "Publicado" = "Veröffentlicht"; "Fallido" = "Fehlgeschlagen"; "Cancelado" = "Abgebrochen"
            "Editar" = "Bearbeiten"; "Publicar ahora" = "Jetzt veröffentlichen"; "Pausar" = "Pausieren"; "Reanudar" = "Fortsetzen"; "Ver tema" = "Thema ansehen"; "Eliminar del panel" = "Aus Panel entfernen"; "Sin acciones disponibles" = "Keine Aktionen verfügbar"
            "Publicando..." = "Veröffentlichen..."; "Publicando el tema. Espera unos segundos..." = "Thema wird veröffentlicht. Bitte einige Sekunden warten..."; "Tema publicado correctamente." = "Thema erfolgreich veröffentlicht."
            "Tema pausado correctamente." = "Thema erfolgreich pausiert."; "Tema reanudado correctamente." = "Thema erfolgreich fortgesetzt."; "Tema cancelado correctamente." = "Thema erfolgreich abgebrochen."; "Registro eliminado del panel." = "Eintrag aus dem Panel entfernt."
            "Selecciona al menos un estado para limpiar." = "Wählen Sie mindestens einen Status zum Bereinigen."; "No hay registros de esos estados en esta página." = "Auf dieser Seite gibt es keine Einträge mit diesen Status."; "Registros eliminados del panel." = "Einträge aus dem Panel entfernt."; "Historial limpiado correctamente." = "Verlauf erfolgreich geleert."
            "Completa todos los campos obligatorios." = "Füllen Sie alle Pflichtfelder aus."; "Guardando..." = "Speichern..."; "Tema actualizado." = "Thema aktualisiert."; "Error inesperado al guardar: " = "Unerwarteter Fehler beim Speichern: "; "Editar tema #" = "Thema bearbeiten #"
            '¿Publicar ahora el tema "' = 'Thema jetzt veröffentlichen "'; '¿Pausar el tema "' = 'Thema pausieren "'; '¿Reanudar el tema "' = 'Thema fortsetzen "'; '¿Cancelar el tema "' = 'Thema abbrechen "'; '¿Eliminar del panel el registro "' = 'Eintrag aus dem Panel entfernen "'; "Solo se eliminará el registro del panel. " = "Nur der Panel-Eintrag wird entfernt. "; "El tema del foro, si existe, NO se eliminará." = "Das Forum-Thema wird, falls vorhanden, NICHT gelöscht."
            "¿Eliminar del panel " = "Entfernen "; " registros de esta página?" = " Einträge von dieser Seite?"; "No se eliminará ningún tema del foro." = "Kein Forum-Thema wird gelöscht."; "Esto eliminará todos los registros publicados, cancelados y fallidos." = "Dadurch werden alle veröffentlichten, abgebrochenen und fehlgeschlagenen Einträge gelöscht."; "Los pendientes, pausados y en proceso se conservarán." = "Ausstehende, pausierte und laufende Einträge bleiben erhalten."; "Escribe ELIMINAR para continuar:" = "Geben Sie ELIMINAR ein, um fortzufahren:"
            "Elimina solo los registros visibles en el panel según los filtros seleccionados. No borra temas del foro." = "Löscht nur die im Panel sichtbaren Einträge entsprechend den ausgewählten Filtern. Es werden keine Forum-Themen gelöscht."; "Elimina todo el historial finalizado del panel: registros publicados, cancelados y fallidos. Conserva pendientes, pausados y en proceso." = "Löscht den gesamten abgeschlossenen Verlauf des Panels: veröffentlichte, abgebrochene und fehlgeschlagene Einträge. Ausstehende, pausierte und laufende Einträge bleiben erhalten."
        }
        "RO" = @{
            "Pendiente" = "În așteptare"; "Pausado" = "Pauzat"; "Procesando" = "În procesare"; "Publicado" = "Publicat"; "Fallido" = "Eșuat"; "Cancelado" = "Anulat"
            "Editar" = "Editează"; "Publicar ahora" = "Publică acum"; "Pausar" = "Pauzează"; "Reanudar" = "Reia"; "Ver tema" = "Vezi subiectul"; "Eliminar del panel" = "Elimină din panou"; "Sin acciones disponibles" = "Nu există acțiuni disponibile"
            "Publicando..." = "Se publică..."; "Publicando el tema. Espera unos segundos..." = "Se publică subiectul. Așteaptă câteva secunde..."; "Tema publicado correctamente." = "Subiect publicat cu succes."
            "Tema pausado correctamente." = "Subiect pauzat cu succes."; "Tema reanudado correctamente." = "Subiect reluat cu succes."; "Tema cancelado correctamente." = "Subiect anulat cu succes."; "Registro eliminado del panel." = "Înregistrare eliminată din panou."
            "Selecciona al menos un estado para limpiar." = "Selectează cel puțin o stare de curățat."; "No hay registros de esos estados en esta página." = "Nu există înregistrări cu aceste stări pe această pagină."; "Registros eliminados del panel." = "Înregistrări eliminate din panou."; "Historial limpiado correctamente." = "Istoric curățat cu succes."
            "Completa todos los campos obligatorios." = "Completează toate câmpurile obligatorii."; "Guardando..." = "Se salvează..."; "Tema actualizado." = "Subiect actualizat."; "Error inesperado al guardar: " = "Eroare neașteptată la salvare: "; "Editar tema #" = "Editează subiectul #"
            '¿Publicar ahora el tema "' = 'Publici acum subiectul "'; '¿Pausar el tema "' = 'Pauzezi subiectul "'; '¿Reanudar el tema "' = 'Reiei subiectul "'; '¿Cancelar el tema "' = 'Anulezi subiectul "'; '¿Eliminar del panel el registro "' = 'Elimini din panou înregistrarea "'; "Solo se eliminará el registro del panel. " = "Se va elimina doar înregistrarea din panou. "; "El tema del foro, si existe, NO se eliminará." = "Subiectul din forum, dacă există, NU va fi șters."
            "¿Eliminar del panel " = "Elimini "; " registros de esta página?" = " înregistrări din această pagină?"; "No se eliminará ningún tema del foro." = "Nu se va șterge niciun subiect din forum."; "Esto eliminará todos los registros publicados, cancelados y fallidos." = "Aceasta va șterge toate înregistrările publicate, anulate și eșuate."; "Los pendientes, pausados y en proceso se conservarán." = "Cele în așteptare, pauzate și în procesare vor fi păstrate."; "Escribe ELIMINAR para continuar:" = "Scrie ELIMINAR pentru a continua:"
            "Elimina solo los registros visibles en el panel según los filtros seleccionados. No borra temas del foro." = "Șterge doar înregistrările vizibile în panou conform filtrelor selectate. Nu șterge subiecte din forum."; "Elimina todo el historial finalizado del panel: registros publicados, cancelados y fallidos. Conserva pendientes, pausados y en proceso." = "Șterge tot istoricul finalizat din panou: înregistrări publicate, anulate și eșuate. Păstrează cele în așteptare, pauzate și în procesare."
        }
        "NL" = @{
            "Pendiente" = "In behandeling"; "Pausado" = "Gepauzeerd"; "Procesando" = "Wordt verwerkt"; "Publicado" = "Gepubliceerd"; "Fallido" = "Mislukt"; "Cancelado" = "Geannuleerd"
            "Editar" = "Bewerken"; "Publicar ahora" = "Nu publiceren"; "Pausar" = "Pauzeren"; "Reanudar" = "Hervatten"; "Ver tema" = "Onderwerp bekijken"; "Eliminar del panel" = "Uit paneel verwijderen"; "Sin acciones disponibles" = "Geen acties beschikbaar"
            "Publicando..." = "Publiceren..."; "Publicando el tema. Espera unos segundos..." = "Het onderwerp wordt gepubliceerd. Wacht enkele seconden..."; "Tema publicado correctamente." = "Onderwerp succesvol gepubliceerd."
            "Tema pausado correctamente." = "Onderwerp succesvol gepauzeerd."; "Tema reanudado correctamente." = "Onderwerp succesvol hervat."; "Tema cancelado correctamente." = "Onderwerp succesvol geannuleerd."; "Registro eliminado del panel." = "Record uit het paneel verwijderd."
            "Selecciona al menos un estado para limpiar." = "Selecteer minstens één status om op te schonen."; "No hay registros de esos estados en esta página." = "Er zijn geen records met die status op deze pagina."; "Registros eliminados del panel." = "Records uit het paneel verwijderd."; "Historial limpiado correctamente." = "Geschiedenis succesvol gewist."
            "Completa todos los campos obligatorios." = "Vul alle verplichte velden in."; "Guardando..." = "Opslaan..."; "Tema actualizado." = "Onderwerp bijgewerkt."; "Error inesperado al guardar: " = "Onverwachte fout tijdens opslaan: "; "Editar tema #" = "Onderwerp bewerken #"
            '¿Publicar ahora el tema "' = 'Onderwerp nu publiceren "'; '¿Pausar el tema "' = 'Onderwerp pauzeren "'; '¿Reanudar el tema "' = 'Onderwerp hervatten "'; '¿Cancelar el tema "' = 'Onderwerp annuleren "'; '¿Eliminar del panel el registro "' = 'Record uit paneel verwijderen "'; "Solo se eliminará el registro del panel. " = "Alleen het paneelrecord wordt verwijderd. "; "El tema del foro, si existe, NO se eliminará." = "Het forumonderwerp, als het bestaat, wordt NIET verwijderd."
            "¿Eliminar del panel " = "Verwijder "; " registros de esta página?" = " records van deze pagina?"; "No se eliminará ningún tema del foro." = "Er wordt geen forumonderwerp verwijderd."; "Esto eliminará todos los registros publicados, cancelados y fallidos." = "Dit verwijdert alle gepubliceerde, geannuleerde en mislukte records."; "Los pendientes, pausados y en proceso se conservarán." = "Records in behandeling, gepauzeerd en in verwerking blijven bewaard."; "Escribe ELIMINAR para continuar:" = "Typ ELIMINAR om door te gaan:"
            "Elimina solo los registros visibles en el panel según los filtros seleccionados. No borra temas del foro." = "Verwijdert alleen de records die zichtbaar zijn in het paneel volgens de geselecteerde filters. Forumonderwerpen worden niet verwijderd."; "Elimina todo el historial finalizado del panel: registros publicados, cancelados y fallidos. Conserva pendientes, pausados y en proceso." = "Verwijdert de volledige afgeronde geschiedenis uit het paneel: gepubliceerde, geannuleerde en mislukte records. Records in behandeling, gepauzeerd en in verwerking blijven bewaard."
        }
        "RU" = @{
            "Pendiente" = "Ожидает"; "Pausado" = "На паузе"; "Procesando" = "Обработка"; "Publicado" = "Опубликовано"; "Fallido" = "Ошибка"; "Cancelado" = "Отменено"
            "Editar" = "Редактировать"; "Publicar ahora" = "Опубликовать сейчас"; "Pausar" = "Пауза"; "Reanudar" = "Возобновить"; "Ver tema" = "Открыть тему"; "Eliminar del panel" = "Удалить из панели"; "Sin acciones disponibles" = "Нет доступных действий"
            "Publicando..." = "Публикация..."; "Publicando el tema. Espera unos segundos..." = "Тема публикуется. Подождите несколько секунд..."; "Tema publicado correctamente." = "Тема успешно опубликована."
            "Tema pausado correctamente." = "Тема поставлена на паузу."; "Tema reanudado correctamente." = "Тема возобновлена."; "Tema cancelado correctamente." = "Тема отменена."; "Registro eliminado del panel." = "Запись удалена из панели."
            "Selecciona al menos un estado para limpiar." = "Выберите хотя бы один статус для очистки."; "No hay registros de esos estados en esta página." = "На этой странице нет записей с такими статусами."; "Registros eliminados del panel." = "Записи удалены из панели."; "Historial limpiado correctamente." = "История успешно очищена."
            "Completa todos los campos obligatorios." = "Заполните все обязательные поля."; "Guardando..." = "Сохранение..."; "Tema actualizado." = "Тема обновлена."; "Error inesperado al guardar: " = "Неожиданная ошибка при сохранении: "; "Editar tema #" = "Редактировать тему #"
            '¿Publicar ahora el tema "' = 'Опубликовать тему сейчас "'; '¿Pausar el tema "' = 'Поставить тему на паузу "'; '¿Reanudar el tema "' = 'Возобновить тему "'; '¿Cancelar el tema "' = 'Отменить тему "'; '¿Eliminar del panel el registro "' = 'Удалить из панели запись "'; "Solo se eliminará el registro del panel. " = "Будет удалена только запись в панели. "; "El tema del foro, si existe, NO se eliminará." = "Тема форума, если она существует, НЕ будет удалена."
            "¿Eliminar del panel " = "Удалить "; " registros de esta página?" = " записей с этой страницы?"; "No se eliminará ningún tema del foro." = "Ни одна тема форума не будет удалена."; "Esto eliminará todos los registros publicados, cancelados y fallidos." = "Это удалит все опубликованные, отмененные и ошибочные записи."; "Los pendientes, pausados y en proceso se conservarán." = "Ожидающие, приостановленные и обрабатываемые записи будут сохранены."; "Escribe ELIMINAR para continuar:" = "Введите ELIMINAR для продолжения:"
            "Elimina solo los registros visibles en el panel según los filtros seleccionados. No borra temas del foro." = "Удаляет только видимые в панели записи согласно выбранным фильтрам. Темы форума не удаляются."; "Elimina todo el historial finalizado del panel: registros publicados, cancelados y fallidos. Conserva pendientes, pausados y en proceso." = "Удаляет всю завершенную историю панели: опубликованные, отмененные и ошибочные записи. Ожидающие, приостановленные и обрабатываемые записи сохраняются."
        }
    }

    if ($panelExtra.ContainsKey($lang)) {
        foreach ($entry in $panelExtra[$lang].GetEnumerator()) {
            Add-TextReplacement $map $entry.Key $entry.Value
        }
    }

    $panelLocales = @{
        "ES" = "es-ES"; "EN" = "en-US"; "PT" = "pt-PT"; "IT" = "it-IT";
        "FR" = "fr-FR"; "DE" = "de-DE"; "RO" = "ro-RO"; "RU" = "ru-RU"; "NL" = "nl-NL"
    }
    if ($panelLocales.ContainsKey($lang)) {
        Add-TextReplacement $map 'toLocaleString("es-ES"' ('toLocaleString("' + $panelLocales[$lang] + '"')
    }

    $html = [Regex]::Replace(
        $html,
        "Target\s+forums\s+and\s+publishing\s+accounts\s+are\s+loaded\s+automatically\s+from\s+the\s+project\s+installer\.",
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) Get-LocalizedPhrase $lang "loadedAutomatically" },
        "IgnoreCase"
    )

    Add-TextReplacement $map "20 registros" ("20 " + (Get-LocalizedPhrase $lang "records"))
    Add-TextReplacement $map "50 registros" ("50 " + (Get-LocalizedPhrase $lang "records"))
    Add-TextReplacement $map "100 registros" ("100 " + (Get-LocalizedPhrase $lang "records"))
    Add-TextReplacement $map "200 registros" ("200 " + (Get-LocalizedPhrase $lang "records"))
    Add-TextReplacement $map "Comprobando..." (Get-LocalizedPhrase $lang "checking")
    Add-TextReplacement $map "← Back to source topic" (Get-LocalizedPhrase $lang "backSource")
    Add-TextReplacement $map "Complete the initial configuration before scheduling a topic." (Get-LocalizedPhrase $lang "completeConfig")
    Add-TextReplacement $map "Minimum title length: 10 characters. Current: " ((Get-LocalizedPhrase $lang "minTitle0").Replace("0.", ""))
    Add-TextReplacement $map "Initial configuration is required." (Get-LocalizedPhrase $lang "completeConfig")
    Add-TextReplacement $map "The system uses the time zone selected during installation. The scheduler checks every minute; Cloudflare may launch the cron a little after the exact minute, so publication and panel refresh can take up to one or two minutes." (Get-CronDelayNote $lang)
    Add-TextReplacement $map "FA_DATE_FORMAT" (Get-DateInputFormat $lang)
    Add-TextReplacement $map "FA_DATE_HELP" (Get-DateInputHelp $lang)
    Add-TextReplacement $map "FA_DATE_HELP_TEMPLATE" (Get-DateInputHelpTemplate $lang)
    Add-TextReplacement $map "FA_DATE_FORMAT_LABEL" (Get-DateFormatLabel $lang)
    Add-TextReplacement $map 'return "Contraseña no válida.";' ('return "' + (Get-PanelRuntimeText $lang "invalidAdmin") + '";')
    Add-TextReplacement $map 'return "Falta configurar el Secret ADMIN_API_KEY.";' ('return "' + (Get-PanelRuntimeText $lang "missingAdminSecret") + '";')
    Add-TextReplacement $map "Publication manager" (Get-LocalizedPhrase $lang "manager")
    Add-TextReplacement $map "Gestor de publicaciones" (Get-LocalizedPhrase $lang "manager")
    Add-TextReplacement $map "Forumotion" (Get-ForumBrand $lang)
    Add-TextReplacement $map "Foroactivo" (Get-ForumBrand $lang)
    Add-TextReplacement $map "v1 multi-account form for the publication manager: SCEditor, full smileys, Servimg and portable first-run configuration." (Get-HtmlCommentText $lang "formIntro")
    Add-TextReplacement $map "Forumotion SCEditor styles" (Get-HtmlCommentText $lang "sceditorStyles")
    Add-TextReplacement $map "Forumotion SCEditor icon positions" (Get-HtmlCommentText $lang "sceditorIcons")
    Add-TextReplacement $map "Prevent compressed buttons inside the scheduler" (Get-HtmlCommentText $lang "compressedButtons")
    Add-TextReplacement $map "Custom Servimg panel used when the native Forumotion command cannot open inside an HTML page." (Get-HtmlCommentText $lang "servimgPanel")
    Add-TextReplacement $map "Forumotion SCEditor variables used by the original scripts." (Get-HtmlCommentText $lang "sceditorVariables")
    Add-TextReplacement $map "Local toolbar string. Do not use window.toolbar because Forumotion may already define it as an object." (Get-HtmlCommentText $lang "toolbarString")
    Add-TextReplacement $map "Best path for old Forumotion SCEditor: insert HTML directly in WYSIWYG." (Get-HtmlCommentText $lang "wysiwygInsert")
    Add-TextReplacement $map "This is the same essential parameter structure used by Forumotion's own Servimg iframe." (Get-HtmlCommentText $lang "servimgParams")
    $brandForComments = Get-ForumBrand $lang
    Add-TextReplacement $map "$brandForComments SCEditor styles" (Get-HtmlCommentText $lang "sceditorStyles")
    Add-TextReplacement $map "$brandForComments SCEditor icon positions" (Get-HtmlCommentText $lang "sceditorIcons")
    Add-TextReplacement $map "Custom Servimg panel used when the native $brandForComments command cannot open inside an HTML page." (Get-HtmlCommentText $lang "servimgPanel")
    Add-TextReplacement $map "$brandForComments SCEditor variables used by the original scripts." (Get-HtmlCommentText $lang "sceditorVariables")
    Add-TextReplacement $map "Local toolbar string. Do not use window.toolbar because $brandForComments may already define it as an object." (Get-HtmlCommentText $lang "toolbarString")
    Add-TextReplacement $map "Best path for old $brandForComments SCEditor: insert HTML directly in WYSIWYG." (Get-HtmlCommentText $lang "wysiwygInsert")
    Add-TextReplacement $map "This is the same essential parameter structure used by $brandForComments's own Servimg iframe." (Get-HtmlCommentText $lang "servimgParams")

    $runtimeKeys = @(
        "searchSmiley","serviceMissing","configLoadError","emptyPublicConfig",
        "publicConfigLoaded","scriptLoadError","postPageError","servimgMissing",
        "servimgLoading","editorBlocked","editorLoaded","toolbarError",
        "editorInitError","formConfigFirst","savingSchedule","saving",
        "scheduleSaved","httpError","unknownError","editorLoadPrefix",
        "imageInserted","imagePrompt","invalidImageUrl","configSavedLoading","loadingPublicConfig",
        "configSavedListsError","servimgOpenError"
    )
    foreach ($runtimeKey in $runtimeKeys) {
        Add-TextReplacement $map (Get-FormRuntimeText "EN" $runtimeKey) (Get-FormRuntimeText $lang $runtimeKey)
    }
    Add-TextReplacement $map "FA_IMAGE_URL_LABEL" (Get-FormRuntimeText $lang "imageUrlLabel")
    Add-TextReplacement $map "FA_IMAGE_WIDTH_LABEL" (Get-FormRuntimeText $lang "imageWidthLabel")
    Add-TextReplacement $map "FA_IMAGE_HEIGHT_LABEL" (Get-FormRuntimeText $lang "imageHeightLabel")
    Add-TextReplacement $map "FA_IMAGE_INSERT_BUTTON" (Get-FormRuntimeText $lang "imageInsertButton")
    Add-TextReplacement $map "Schedule saved successfully. Returning to source topic..." (Get-FormRuntimeText $lang "scheduleSaved")
    Add-TextReplacement $map "Could not open the $brandForComments post page to read Servimg session data." (Get-FormRuntimeText $lang "postPageError")
    Add-TextReplacement $map "SCEditor could not be loaded. Open the browser console and check which $brandForComments SCEditor file is blocked or missing." (Get-FormRuntimeText $lang "editorBlocked")
    Add-TextReplacement $map "$brandForComments editor loaded." (Get-FormRuntimeText $lang "editorLoaded")

    foreach ($entry in ($map.GetEnumerator() | Sort-Object { $_.Key.Length } -Descending)) {
        $html = $html.Replace($entry.Key, $entry.Value)
    }

    $html = [Regex]::Replace(
        $html,
        "Eliminar\s+(?:registros|records)\s+de\s+la\s+p[áa]gina",
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) Get-LocalizedPhrase $lang "deletePage" },
        "IgnoreCase"
    )
    $html = [Regex]::Replace(
        $html,
        "Vaciar\s+historial",
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) Get-LocalizedPhrase $lang "clearHistory" },
        "IgnoreCase"
    )

    $cancelledSingular = @{
        "ES" = "Cancelado"
        "EN" = "Cancelled"
        "PT" = "Cancelado"
        "IT" = "Annullato"
        "RU" = "Отменено"
        "FR" = "Annulé"
        "DE" = "Abgebrochen"
        "RO" = "Anulat"
        "NL" = "Geannuleerd"
    }
    if (-not $cancelledSingular.ContainsKey($lang)) { $cancelledSingular[$lang] = $cancelledSingular["EN"] }

    $cancelAction = @{
        "ES" = "Cancelar"
        "EN" = "Cancel"
        "PT" = "Cancelar"
        "IT" = "Annulla"
        "RU" = "Отменить"
        "FR" = "Annuler"
        "DE" = "Abbrechen"
        "RO" = "Anulează"
        "NL" = "Annuleren"
    }
    if (-not $cancelAction.ContainsKey($lang)) { $cancelAction[$lang] = $cancelAction["EN"] }

    $html = $html.
        Replace("countCancelarados", "countCancelled").
        Replace("cleanCancelarados", "cleanCancelled").
        Replace("countAnnullaados", "countCancelled").
        Replace("cleanAnnullaados", "cleanCancelled").
        Replace("countAnnulerled", "countCancelled").
        Replace("cleanAnnulerled", "cleanCancelled").
        Replace("countAbbrechenled", "countCancelled").
        Replace("cleanAbbrechenled", "cleanCancelled").
        Replace("countAnuleazăled", "countCancelled").
        Replace("cleanAnuleazăled", "cleanCancelled").
        Replace("countОтменитьled", "countCancelled").
        Replace("cleanОтменитьled", "cleanCancelled")

    $html = $html.
        Replace("Cancelarados", (Get-LocalizedPhrase $lang "cancelled")).
        Replace("Cancelarado", $cancelledSingular[$lang]).
        Replace("Cancelarar", $cancelAction[$lang])

    $html = $html.
        Replace("showEstado", "showStatus").
        Replace("showÉtat", "showStatus").
        Replace("showStato", "showStatus").
        Replace("showStatusul", "showStatus")

    if ($kind -eq "form" -and $lang -ne "ES") {
        $html = $html.Replace("var FORCE_BACK_TO_INDEX = false;", "var FORCE_BACK_TO_INDEX = true;")
    }
    if (-not [string]::IsNullOrWhiteSpace($projectTitle) -or -not [string]::IsNullOrWhiteSpace($workerUrl)) {
        $storageSuffix = Get-StorageSuffix $projectTitle
        $html = $html.Replace("publication_manager_config_v1", "publication_manager_config_$storageSuffix")
        $html = $html.Replace("publication_manager_form_config_v1", "publication_manager_form_config_$storageSuffix")
        $html = $html.Replace("publication_manager_admin_hash_v1", "publication_manager_admin_hash_$storageSuffix")
        $html = $html.Replace("publication_manager_panel_source_v1", "publication_manager_panel_source_$storageSuffix")

        $jsProjectTitle = ConvertTo-JavaScriptString $projectTitle
        $jsWorkerUrl = ConvertTo-JavaScriptString $workerUrl

        if (-not [string]::IsNullOrWhiteSpace($projectTitle)) {
            $html = $html.Replace('var INSTALLED_PROJECT_NAME = "";', 'var INSTALLED_PROJECT_NAME = "' + $jsProjectTitle + '";')
        }
        if (-not [string]::IsNullOrWhiteSpace($workerUrl)) {
            $html = $html.Replace('var INSTALLED_WORKER_URL = "";', 'var INSTALLED_WORKER_URL = "' + $jsWorkerUrl + '";')
        }

        if ($kind -eq "panel") {
            if (-not [string]::IsNullOrWhiteSpace($workerUrl)) {
                $html = [Regex]::Replace(
                    $html,
                    'var WORKER_URL = String\(\s*savedConfig\.workerUrl \|\|\s*"[^"]*"\s*\);',
                    'var WORKER_URL = String(savedConfig.workerUrl || "' + $jsWorkerUrl + '");',
                    "Singleline"
                )
            }
            if (-not [string]::IsNullOrWhiteSpace($projectTitle)) {
                $html = [Regex]::Replace(
                    $html,
                    'var PROJECT_NAME = String\(\s*savedConfig\.projectName \|\|\s*"[^"]*"\s*\);',
                    'var PROJECT_NAME = String(savedConfig.projectName || "' + $jsProjectTitle + '");',
                    "Singleline"
                )
            }
        }

        if ($kind -eq "form") {
            if (-not [string]::IsNullOrWhiteSpace($projectTitle)) {
                $html = [Regex]::Replace(
                    $html,
                    'sharedConfig\.projectName\s*\|\|\s*"[^"]*"',
                    'sharedConfig.projectName || "' + $jsProjectTitle + '"'
                )
                $html = [Regex]::Replace(
                    $html,
                    'projectName:\s*projectName\s*\|\|\s*"[^"]*"',
                    'projectName: projectName || "' + $jsProjectTitle + '"'
                )
            }
            if (-not [string]::IsNullOrWhiteSpace($workerUrl)) {
                $html = [Regex]::Replace(
                    $html,
                    'sharedConfig\.workerUrl\s*\|\|\s*""',
                    'sharedConfig.workerUrl || "' + $jsWorkerUrl + '"'
                )
                $html = [Regex]::Replace(
                    $html,
                    'workerUrl:\s*workerUrl',
                    'workerUrl: workerUrl'
                )
            }
        }
    }

    if ($kind -eq "panel" -and $lang -eq "EN") {
        $html = [Regex]::Replace(
            $html,
            '<p class="small-note">.*?</p>',
            '<p class="small-note">' + (Get-LocalizedPhrase $lang "loginNote") + '</p>',
            "Singleline"
        )

        $englishPanelReplacements = [ordered]@{
            "CONFIGURACIÓN" = "CONFIGURATION"
            "(Sin título)" = "(Untitled)"
            "Pausado" = "Paused"
            "Publicado" = "Published"
            "Fallido" = "Failed"
            "Cancelado" = "Cancelled"
            "Editar" = "Edit"
            "Publicar ahora" = "Publish now"
            "Publicando..." = "Publishing..."
            "Publicando el tema. Espera unos segundos..." = "Publishing the topic. Please wait a few seconds..."
            "Tema publicado correctamente." = "Topic published successfully."
            "Pausar" = "Pause"
            "Reanudar" = "Resume"
            "Ver tema" = "View topic"
            "Eliminar del panel" = "Delete from panel"
            "Sin acciones disponibles" = "No actions available"
            "¿Publicar ahora el tema " = "Publish topic now "
            "¿Pausar el tema " = "Pause topic "
            "¿Reanudar el tema " = "Resume topic "
            "¿Cancelar el tema " = "Cancel topic "
            "¿Eliminar del panel el registro " = "Delete this record from the panel "
            "Solo se eliminará el registro del panel. " = "Only the panel record will be deleted. "
            "El tema del foro, si existe, NO se eliminará." = "The forum topic, if it exists, will NOT be deleted."
            "Registro eliminado del panel." = "Record deleted from the panel."
            "Selecciona al menos un estado para limpiar." = "Select at least one status to clean."
            "No hay registros de esos estados en esta página." = "There are no records with those statuses on this page."
            "No hay records de esos estados en esta página." = "There are no records with those statuses on this page."
            "¿Eliminar del panel " = "Delete from the panel "
            " registros visibles del panel?" = " visible records from the panel?"
            " records de esta página?" = " records from this page?"
            "No se eliminará ningún tema del foro." = "No forum topic will be deleted."
            "Registros eliminados del panel." = "Records deleted from the panel."
            "Esto eliminará todo el historial finalizado del panel." = "This will delete the full completed history from the panel."
            "Se eliminarán los registros publicados, cancelados y fallidos." = "Published, cancelled and failed records will be deleted."
            "Los pendientes, pausados y en proceso se conservarán." = "Pending, paused and processing records will be kept."
            "Escribe ELIMINAR para continuar:" = "Type DELETE to continue:"
            "ELIMINAR" = "DELETE"
            "Historial limpiado correctamente." = "History cleared successfully."
            "Editar tema #" = "Edit topic #"
            "Completa todos los campos obligatorios." = "Complete all required fields."
            "Guardando..." = "Saving..."
            "Tema actualizado." = "Topic updated."
            "Error inesperado al guardar: " = "Unexpected error while saving: "
            "La sesión ha caducado. Introduce de nuevo la clave." = "The session has expired. Enter the key again."
            "¿Qué nombre deseas poner al proyecto?" = "What name do you want for the project?"
            "Pega la dirección creada para el servicio:" = "Paste the address created for the service:"
            "La dirección no es válida. Debe comenzar por https://" = "The address is not valid. It must start with https://"
            "El Worker devolvió una respuesta no válida. HTTP " = "The Worker returned an invalid response. HTTP "
            "No has introducido ninguna clave." = "You did not enter a key."
            "Limpieza del panel:" = "Panel cleanup:"
            "Eliminar registros de la pagina" = "Delete page records"
            "Eliminar registros de la página" = "Delete page records"
            "Vaciar historial" = "Clear history"
            "Guardar cambios" = "Save changes"
            "Pendiente" = "Pending"
            "Pendientes" = "Pending"
            "Publicados" = "Published"
            "Cancelados" = "Cancelled"
            "Fallidos" = "Failed"
            "Todos los estados" = "All statuses"
            "Buscar por título, autor o URL..." = "Search by title, author or URL..."
            "Actualizar" = "Refresh"
            "No hay registros para mostrar." = "No records to show."
            "Clave administrativa no válida." = "Invalid admin key."
        }

        foreach ($entry in $englishPanelReplacements.GetEnumerator()) {
            $html = $html.Replace($entry.Key, $entry.Value)
        }

        $html = $html.Replace('return date.toLocaleString("es-ES"', 'return date.toLocaleString("en-US"')
    }

    $legalComment = "<!--`r`n" +
        "  " + (Get-GeneratedLanguageLabelForHtml $lang) + ": " + $lang + "`r`n" +
        "  " + (Get-LegalTitleForHtml $lang) + ":`r`n" +
        "  " + ((Get-LegalBodyForHtml $lang) -replace "`n", "`r`n  ") + "`r`n" +
        "-->`r`n"

    $html = [Regex]::Replace($html, "<!--\s*(Autoría|Authorship|Autoria|Autoria e|Auteur|Urheberschaft|Авторство|Autor|Projeto|Proyecto|Open Source|Open-Source|Projet).*?-->\s*", "", "Singleline")
    $html = $legalComment + $html
    if ($kind -eq "panel") {
        $html = [Regex]::Replace($html, '<html lang="[^"]*">', '<html lang="' + $lang.ToLowerInvariant() + '">')
    }
    if ($kind -eq "form") {
        $locale = $lang.ToLowerInvariant()
        $html = [Regex]::Replace($html, 'window\.locale = window\.locale \|\| "[^"]+";', 'window.locale = window.locale || "' + $locale + '";')
    }
    return $html
}

function Get-LocalizedInstructions([string]$lang, [string]$workerUrl) {
    switch ($lang) {
        "EN" { return @"
TOPIC SCHEDULER FOR FOROACTIVO
INSTALLATION INSTRUCTIONS

1. FORMULARIO_DE_PROGRAMACION.html
   Create an HTML page in Foroactivo for the scheduling form.
   Paste the full content of FORMULARIO_DE_PROGRAMACION.html.
   When requested, enter the Worker URL.

2. PANEL_DE_CONTROL.html
   Create another HTML page in Foroactivo for the control panel.
   Paste the full content of PANEL_DE_CONTROL.html.
   When requested, enter the same Worker URL and the admin key chosen in the installer.

WORKER URL
$workerUrl

ADMIN KEY
For security reasons, the admin key is not written in this file.
Save the key you entered in the installer. You will need it to access the control panel.

AUTHORSHIP AND TERMS OF USE
Open Source Project, developed with ChatGPT + the Firefox console, under the full supervision and multiple tests of Jucarese, Foroactivo Administrator. © 2026
All rights reserved. Reproduction, distribution, modification or publication, in whole or in part, is prohibited without express authorization from the author.
"@ }
        "PT" { return @"
PROGRAMADOR DE TÓPICOS PARA FOROACTIVO
INSTRUÇÕES DE INSTALAÇÃO

1. FORMULARIO_DE_PROGRAMACION.html
   Crie uma página HTML no Foroactivo para o formulário de programação.
   Cole o conteúdo completo de FORMULARIO_DE_PROGRAMACION.html.
   Quando solicitado, introduza a URL do Worker.

2. PANEL_DE_CONTROL.html
   Crie outra página HTML no Foroactivo para o painel de controle.
   Cole o conteúdo completo de PANEL_DE_CONTROL.html.
   Quando solicitado, introduza a mesma URL do Worker e a chave administrativa escolhida no instalador.

URL DO WORKER
$workerUrl

CHAVE ADMINISTRATIVA
Por segurança, a chave administrativa não é escrita neste arquivo.
Guarde a chave que introduziu no instalador. Você precisará dela para entrar no painel de controle.

AUTORIA E CONDIÇÕES DE USO
Projeto de Código Aberto, desenvolvido com ChatGPT + a consola do Firefox, com a supervisão total e múltiplos testes de Jucarese, Administrador de Foroactivo. © 2026
Todos os direitos reservados. É proibida a reprodução, distribuição, modificação ou divulgação, total ou parcial, sem autorização expressa do autor.
"@ }
        "IT" { return @"
PROGRAMMATORE DI ARGOMENTI PER FOROACTIVO
ISTRUZIONI DI INSTALLAZIONE

1. FORMULARIO_DE_PROGRAMACION.html
   Crea una pagina HTML in Foroactivo per il modulo di programmazione.
   Incolla tutto il contenuto di FORMULARIO_DE_PROGRAMACION.html.
   Quando richiesto, inserisci l'URL del Worker.

2. PANEL_DE_CONTROL.html
   Crea un'altra pagina HTML in Foroactivo per il pannello di controllo.
   Incolla tutto il contenuto di PANEL_DE_CONTROL.html.
   Quando richiesto, inserisci lo stesso URL del Worker e la chiave amministrativa scelta nell'installer.

URL DEL WORKER
$workerUrl

CHIAVE AMMINISTRATIVA
Per sicurezza, la chiave amministrativa non viene scritta in questo file.
Conserva la chiave inserita nell'installer. Ti servirà per accedere al pannello di controllo.

AUTORIA E CONDIZIONI D'USO
Progetto Open Source, sviluppato con ChatGPT + la console di Firefox, con la supervisione totale e molteplici test di Jucarese, Amministratore di Foroactivo. © 2026
Tutti i diritti riservati. È vietata la riproduzione, distribuzione, modifica o diffusione, totale o parziale, senza autorizzazione espressa dell'autore.
"@ }
        "RU" { return @"
ПЛАНИРОВЩИК ТЕМ ДЛЯ FOROACTIVO
ИНСТРУКЦИИ ПО УСТАНОВКЕ

1. FORMULARIO_DE_PROGRAMACION.html
   Создайте HTML-страницу в Foroactivo для формы планирования.
   Вставьте полное содержимое FORMULARIO_DE_PROGRAMACION.html.
   Когда форма попросит, введите URL Worker.

2. PANEL_DE_CONTROL.html
   Создайте вторую HTML-страницу в Foroactivo для панели управления.
   Вставьте полное содержимое PANEL_DE_CONTROL.html.
   Когда панель попросит, введите тот же URL Worker и административный ключ, выбранный в установщике.

URL WORKER
$workerUrl

АДМИНИСТРАТИВНЫЙ КЛЮЧ
В целях безопасности административный ключ не записывается в этот файл.
Сохраните ключ, введенный в установщике. Он понадобится для входа в панель управления.

АВТОРСТВО И УСЛОВИЯ ИСПОЛЬЗОВАНИЯ
Проект с открытым исходным кодом, разработанный с помощью ChatGPT + консоли Firefox, при полном надзоре и многочисленных тестах Jucarese, администратора Foroactivo. © 2026
Все права защищены. Воспроизведение, распространение, изменение или публикация полностью или частично запрещены без явного разрешения автора.
"@ }
        "FR" { return @"
PLANIFICATEUR DE SUJETS POUR FOROACTIVO
INSTRUCTIONS D'INSTALLATION

1. FORMULARIO_DE_PROGRAMACION.html
   Créez une page HTML dans Foroactivo pour le formulaire de programmation.
   Collez tout le contenu de FORMULARIO_DE_PROGRAMACION.html.
   Lorsque le formulaire le demande, saisissez l'URL du Worker.

2. PANEL_DE_CONTROL.html
   Créez une autre page HTML dans Foroactivo pour le panneau de contrôle.
   Collez tout le contenu de PANEL_DE_CONTROL.html.
   Lorsque le panneau le demande, saisissez la même URL du Worker et la clé administrative choisie dans l'installateur.

URL DU WORKER
$workerUrl

CLÉ ADMINISTRATIVE
Pour des raisons de sécurité, la clé administrative n'est pas écrite dans ce fichier.
Conservez la clé saisie dans l'installateur. Elle sera nécessaire pour accéder au panneau de contrôle.

AUTEUR ET CONDITIONS D'UTILISATION
Projet Open Source, développé avec ChatGPT + la console Firefox, sous la supervision totale et après de multiples tests de Jucarese, Administrateur de Foroactivo. © 2026
Tous droits réservés. La reproduction, distribution, modification ou diffusion, totale ou partielle, est interdite sans autorisation expresse de l'auteur.
"@ }
        "DE" { return @"
THEMENPLANER FÜR FOROACTIVO
INSTALLATIONSANLEITUNG

1. FORMULARIO_DE_PROGRAMACION.html
   Erstellen Sie in Foroactivo eine HTML-Seite für das Planungsformular.
   Fügen Sie den vollständigen Inhalt von FORMULARIO_DE_PROGRAMACION.html ein.
   Geben Sie bei Aufforderung die Worker-URL ein.

2. PANEL_DE_CONTROL.html
   Erstellen Sie eine weitere HTML-Seite in Foroactivo für das Kontrollpanel.
   Fügen Sie den vollständigen Inhalt von PANEL_DE_CONTROL.html ein.
   Geben Sie bei Aufforderung dieselbe Worker-URL und den im Installer gewählten Admin-Schlüssel ein.

WORKER-URL
$workerUrl

ADMIN-SCHLÜSSEL
Aus Sicherheitsgründen wird der Admin-Schlüssel nicht in diese Datei geschrieben.
Bewahren Sie den im Installer eingegebenen Schlüssel auf. Sie benötigen ihn für den Zugriff auf das Kontrollpanel.

URHEBERSCHAFT UND NUTZUNGSBEDINGUNGEN
Open-Source-Projekt, entwickelt mit ChatGPT + der Firefox-Konsole, unter vollständiger Aufsicht und mit zahlreichen Tests von Jucarese, Foroactivo-Administrator. © 2026
Alle Rechte vorbehalten. Vervielfältigung, Verbreitung, Änderung oder Veröffentlichung, ganz oder teilweise, ist ohne ausdrückliche Genehmigung des Autors untersagt.
"@ }
        "RO" { return @"
PROGRAMATOR DE SUBIECTE PENTRU FOROACTIVO
INSTRUCȚIUNI DE INSTALARE

1. FORMULARIO_DE_PROGRAMACION.html
   Creează o pagină HTML în Foroactivo pentru formularul de programare.
   Lipește conținutul complet din FORMULARIO_DE_PROGRAMACION.html.
   Când formularul solicită acest lucru, introdu URL-ul Worker.

2. PANEL_DE_CONTROL.html
   Creează o altă pagină HTML în Foroactivo pentru panoul de control.
   Lipește conținutul complet din PANEL_DE_CONTROL.html.
   Când panoul solicită acest lucru, introdu același URL Worker și cheia administrativă aleasă în instalator.

URL WORKER
$workerUrl

CHEIE ADMINISTRATIVĂ
Din motive de securitate, cheia administrativă nu este scrisă în acest fișier.
Păstrează cheia introdusă în instalator. Vei avea nevoie de ea pentru a accesa panoul de control.

AUTOR ȘI CONDIȚII DE UTILIZARE
Proiect Open Source, dezvoltat cu ChatGPT + consola Firefox, sub supravegherea totală și cu multiple teste de Jucarese, Administrator Foroactivo. © 2026
Toate drepturile rezervate. Reproducerea, distribuirea, modificarea sau publicarea, totală sau parțială, este interzisă fără autorizația expresă a autorului.
"@ }
        "NL" { return @"
ONDERWERPPLANNER VOOR FOROACTIVO
INSTALLATIE-INSTRUCTIES

1. FORMULARIO_DE_PROGRAMACION.html
   Maak een HTML-pagina in Foroactivo voor het planningsformulier.
   Plak de volledige inhoud van FORMULARIO_DE_PROGRAMACION.html.
   Voer de Worker-URL in wanneer het formulier daarom vraagt.

2. PANEL_DE_CONTROL.html
   Maak nog een HTML-pagina in Foroactivo voor het controlepaneel.
   Plak de volledige inhoud van PANEL_DE_CONTROL.html.
   Voer dezelfde Worker-URL en de beheerderssleutel in die u in het installatieprogramma hebt gekozen.

WORKER-URL
$workerUrl

BEHEERDERSSLEUTEL
Om veiligheidsredenen wordt de beheerderssleutel niet in dit bestand geschreven.
Bewaar de sleutel die u in het installatieprogramma hebt ingevoerd. U hebt deze nodig om toegang te krijgen tot het controlepaneel.

AUTEURSCHAP EN GEBRUIKSVOORWAARDEN
Open Source Project, ontwikkeld met ChatGPT + de Firefox-console, onder volledige supervisie en met meerdere tests van Jucarese, Administrator van Foroactivo. © 2026
Alle rechten voorbehouden. Reproductie, distributie, wijziging of publicatie, geheel of gedeeltelijk, is verboden zonder uitdrukkelijke toestemming van de auteur.
"@ }
        default { return @"
PROGRAMADOR DE TEMAS PARA FOROACTIVO
INSTRUCCIONES DE INSTALACIÓN

1. FORMULARIO_DE_PROGRAMACION.html
   Crea una página HTML en Foroactivo para el formulario de programación.
   Pega el contenido completo de FORMULARIO_DE_PROGRAMACION.html.
   Cuando el formulario te lo pida, introduce la URL del Worker.

2. PANEL_DE_CONTROL.html
   Crea otra página HTML en Foroactivo para el panel de control.
   Pega el contenido completo de PANEL_DE_CONTROL.html.
   Cuando el panel te lo pida, introduce la misma URL del Worker y la clave administrativa elegida durante la instalación.

URL DEL WORKER
$workerUrl

CLAVE ADMINISTRATIVA
Por seguridad, la clave administrativa no se escribe en este archivo.
Debes guardar la clave que escribiste en el instalador. La necesitarás para entrar en el panel de control.

AUTORÍA Y CONDICIONES DE USO
Proyecto de Código Abierto, desarrollado con ChatGPT + la consola de Firefox, con la supervisión total y múltiples pruebas de Jucarese, Administrador de Foroactivo. © 2026
Todos los derechos reservados. Queda prohibida la reproducción, distribución, modificación o difusión, total o parcial, sin autorización expresa del autor.
"@ }
    }
}

function Show-StartupLanguageDialog {
    $languageCodes = @("ES", "EN", "PT", "IT", "RU", "FR", "DE", "RO", "NL")
    $languageLabels = @{
        "ES" = "ES - Español"
        "EN" = "EN - English"
        "PT" = "PT - Português"
        "IT" = "IT - Italiano"
        "RU" = "RU - Русский"
        "FR" = "FR - Français"
        "DE" = "DE - Deutsch"
        "RO" = "RO - Română"
        "NL" = "NL - Nederlands"
    }
    $cultureMap = @{
        "es" = "ES"
        "en" = "EN"
        "pt" = "PT"
        "it" = "IT"
        "ru" = "RU"
        "fr" = "FR"
        "de" = "DE"
        "ro" = "RO"
        "nl" = "NL"
    }

    $detectedCulture = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName.ToLowerInvariant()
    if ($cultureMap.ContainsKey($detectedCulture)) {
        $script:CurrentLanguage = $cultureMap[$detectedCulture]
    }

    $languageForm = New-Object System.Windows.Forms.Form
    $languageForm.Text = Get-UiText "startupTitle"
    $languageForm.StartPosition = "CenterScreen"
    $languageForm.ClientSize = New-Object System.Drawing.Size(500, 280)
    $languageForm.FormBorderStyle = "FixedDialog"
    $languageForm.MaximizeBox = $false
    $languageForm.MinimizeBox = $false
    $languageForm.BackColor = $script:UiSurface
    $languageForm.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $languageForm.TopMost = $true

    $iconPath = Join-Path $root "assets\foroactivo_installer.ico"
    if (Test-Path $iconPath) {
        try {
            $languageForm.Icon = New-Object System.Drawing.Icon($iconPath)
        } catch {}
    }

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = Get-UiText "startupTitle"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14)
    $titleLabel.ForeColor = $script:UiBlue
    $titleLabel.Location = New-Object System.Drawing.Point(26, 22)
    $titleLabel.Size = New-Object System.Drawing.Size(445, 44)
    $languageForm.Controls.Add($titleLabel)

    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-UiText "startupDescription"
    $descriptionLabel.ForeColor = $script:UiText
    $descriptionLabel.Location = New-Object System.Drawing.Point(28, 76)
    $descriptionLabel.Size = New-Object System.Drawing.Size(445, 48)
    $languageForm.Controls.Add($descriptionLabel)

    $languageCombo = New-Object System.Windows.Forms.ComboBox
    $languageCombo.DropDownStyle = "DropDownList"
    $languageCombo.Location = New-Object System.Drawing.Point(30, 134)
    $languageCombo.Size = New-Object System.Drawing.Size(438, 30)
    foreach ($code in $languageCodes) {
        $languageCombo.Items.Add($languageLabels[$code]) | Out-Null
    }
    $selectedIndex = [Array]::IndexOf($languageCodes, $script:CurrentLanguage)
    if ($selectedIndex -lt 0) {
        $selectedIndex = 0
    }
    $languageCombo.SelectedIndex = $selectedIndex
    $languageForm.Controls.Add($languageCombo)

    $continueButton = New-Object System.Windows.Forms.Button
    $continueButton.Text = Get-UiText "startupContinue"
    $continueButton.Location = New-Object System.Drawing.Point(276, 202)
    $continueButton.Size = New-Object System.Drawing.Size(192, 42)
    $continueButton.BackColor = $script:UiBlue
    $continueButton.ForeColor = [System.Drawing.Color]::White
    $continueButton.FlatStyle = "Flat"
    $continueButton.FlatAppearance.BorderSize = 0
    $continueButton.Add_Click({
        if ($languageCombo.SelectedItem -match "^([A-Z]{2})") {
            $script:CurrentLanguage = $Matches[1]
        }
        $languageForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $languageForm.Close()
    })
    $languageForm.AcceptButton = $continueButton
    $languageForm.Controls.Add($continueButton)

    [void]$languageForm.ShowDialog()
}

Show-StartupLanguageDialog
Set-InstallerOutputFolderForLanguage $script:CurrentLanguage

$form = New-Object System.Windows.Forms.Form
$form.Text = "Programador de temas para Foroactivo"
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(1120, 760)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 700)
$form.BackColor = $script:UiSurface
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$iconPath = Join-Path $root "assets\foroactivo_installer.ico"
if (Test-Path $iconPath) {
    try {
        $form.Icon = New-Object System.Drawing.Icon($iconPath)
    } catch {}
}

$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = "Top"
$headerPanel.Height = 128
$headerPanel.BackColor = $script:UiBlue
$headerPanel.Add_Paint({
    param($sender, $paintEvent)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        ([System.Drawing.Color]::FromArgb(0, 126, 205)),
        ([System.Drawing.Color]::FromArgb(0, 72, 132)),
        0
    )
    $paintEvent.Graphics.FillRectangle($brush, $rect)
    $brush.Dispose()
})
$form.Controls.Add($headerPanel)

$logoPanel = New-Object System.Windows.Forms.Panel
$logoPanel.Location = New-Object System.Drawing.Point(30, 24)
$logoPanel.Size = New-Object System.Drawing.Size(80, 80)
$logoPanel.BackColor = [System.Drawing.Color]::FromArgb(52, 166, 216)
$headerPanel.Controls.Add($logoPanel)

$logoImage = New-Object System.Windows.Forms.PictureBox
$logoImage.Dock = "Fill"
$logoImage.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$logoImage.Padding = New-Object System.Windows.Forms.Padding(8)
$logoPath = Join-Path $root "assets\foroactivo_installer.png"
if (Test-Path $logoPath) {
    try {
        $logoImage.Image = [System.Drawing.Image]::FromFile($logoPath)
    } catch {}
}
$logoPanel.Controls.Add($logoImage)

$title = New-Object System.Windows.Forms.Label
$title.Text = Get-UiText "title"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 21, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.ForeColor = [System.Drawing.Color]::White
$title.Location = New-Object System.Drawing.Point(136, 30)
$headerPanel.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = Get-UiText "subtitle"
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(224, 243, 253)
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$subtitle.Location = New-Object System.Drawing.Point(140, 76)
$headerPanel.Controls.Add($subtitle)

$productBadge = New-Object System.Windows.Forms.Label
$productBadge.Text = Get-UiText "productBadge"
$productBadge.AutoSize = $true
$productBadge.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
$productBadge.ForeColor = [System.Drawing.Color]::FromArgb(225, 246, 255)
$productBadge.BackColor = [System.Drawing.Color]::FromArgb(0, 82, 143)
$productBadge.Location = New-Object System.Drawing.Point(140, 98)
$productBadge.Visible = $false

$languageLabel = New-Object System.Windows.Forms.Label
$languageLabel.Text = Get-UiText "languageLabel"
$languageLabel.ForeColor = [System.Drawing.Color]::White
$languageLabel.Location = New-Object System.Drawing.Point(884, 28)
$languageLabel.Size = New-Object System.Drawing.Size(170, 22)
$languageLabel.Anchor = "Top,Right"
$headerPanel.Controls.Add($languageLabel)

$languageSelector = New-Object System.Windows.Forms.ComboBox
$languageSelector.DropDownStyle = "DropDownList"
$languageSelector.Location = New-Object System.Drawing.Point(884, 54)
$languageSelector.Size = New-Object System.Drawing.Size(190, 28)
$languageSelector.Anchor = "Top,Right"
$languageSelector.Items.Add("ES - Español") | Out-Null
$languageSelector.Items.Add("EN - English") | Out-Null
$languageSelector.Items.Add("PT - Português") | Out-Null
$languageSelector.Items.Add("IT - Italiano") | Out-Null
$languageSelector.Items.Add("RU - Русский") | Out-Null
$languageSelector.Items.Add("FR - Français") | Out-Null
$languageSelector.Items.Add("DE - Deutsch") | Out-Null
$languageSelector.Items.Add("RO - Română") | Out-Null
$languageSelector.Items.Add("NL - Nederlands") | Out-Null
$languageSelectorMap = @{
    "ES" = 0
    "EN" = 1
    "PT" = 2
    "IT" = 3
    "RU" = 4
    "FR" = 5
    "DE" = 6
    "RO" = 7
    "NL" = 8
}
if ($languageSelectorMap.ContainsKey($script:CurrentLanguage)) {
    $languageSelector.SelectedIndex = $languageSelectorMap[$script:CurrentLanguage]
} else {
    $languageSelector.SelectedIndex = 0
}
$headerPanel.Controls.Add($languageSelector)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(24, 148)
$tabs.Size = New-Object System.Drawing.Size(1072, 520)
$tabs.Anchor = "Top,Bottom,Left,Right"
$tabs.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$tabs.Padding = New-Object System.Drawing.Point(18, 7)
$form.Controls.Add($tabs)

$tabProject = New-Object System.Windows.Forms.TabPage
$tabProject.Text = "⚙  Proyecto"
$tabProject.BackColor = $script:UiSurface
$tabProject.AutoScroll = $true
$tabs.TabPages.Add($tabProject)

$legalCard = New-Object System.Windows.Forms.Panel
$legalCard.Location = New-Object System.Drawing.Point(18, 18)
$legalCard.Size = New-Object System.Drawing.Size(1012, 134)
$legalCard.Anchor = "Top,Left,Right"
$legalCard.BackColor = [System.Drawing.Color]::White
$legalCard.BorderStyle = "FixedSingle"
$tabProject.Controls.Add($legalCard)

$legalTitle = New-Object System.Windows.Forms.Label
$legalTitle.Text = "Autoría y condiciones de uso"
$legalTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$legalTitle.ForeColor = $script:UiBlue
$legalTitle.Location = New-Object System.Drawing.Point(18, 14)
$legalTitle.AutoSize = $true
$legalCard.Controls.Add($legalTitle)

$legalText = New-Object System.Windows.Forms.Label
$legalText.Text = Get-UiText "legalBody"
$legalText.Location = New-Object System.Drawing.Point(18, 44)
$legalText.Size = New-Object System.Drawing.Size(930, 56)
$legalText.Anchor = "Top,Left,Right"
$legalText.ForeColor = $script:UiText
$legalCard.Controls.Add($legalText)

$generalCard = New-Object System.Windows.Forms.Panel
$generalCard.Location = New-Object System.Drawing.Point(18, 166)
$generalCard.Size = New-Object System.Drawing.Size(1012, 114)
$generalCard.Anchor = "Top,Left,Right"
$generalCard.BackColor = [System.Drawing.Color]::White
$generalCard.BorderStyle = "FixedSingle"
$tabProject.Controls.Add($generalCard)

$generalTitle = New-Object System.Windows.Forms.Label
$generalTitle.Text = "Datos generales del proyecto"
$generalTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$generalTitle.ForeColor = $script:UiBlue
$generalTitle.Location = New-Object System.Drawing.Point(18, 14)
$generalTitle.AutoSize = $true
$generalCard.Controls.Add($generalTitle)

$projectNameLabel = New-Object System.Windows.Forms.Label
$projectNameLabel.Text = "Nombre técnico del proyecto"
$projectNameLabel.Location = New-Object System.Drawing.Point(18, 48)
$projectNameLabel.AutoSize = $true
$generalCard.Controls.Add($projectNameLabel)

$projectName = New-Object System.Windows.Forms.TextBox
$projectName.Text = ""
$projectName.Location = New-Object System.Drawing.Point(18, 72)
$projectName.Size = New-Object System.Drawing.Size(380, 28)
Style-TextBox $projectName
$generalCard.Controls.Add($projectName)

$timezoneLabel = New-Object System.Windows.Forms.Label
$timezoneLabel.Text = "Zona horaria"
$timezoneLabel.Location = New-Object System.Drawing.Point(440, 48)
$timezoneLabel.AutoSize = $true
$generalCard.Controls.Add($timezoneLabel)

$timezone = New-Object System.Windows.Forms.ComboBox
$timezone.DropDownStyle = "DropDown"
$timezone.AutoCompleteMode = "SuggestAppend"
$timezone.AutoCompleteSource = "ListItems"
$timezone.Text = ""
$timezone.Location = New-Object System.Drawing.Point(440, 72)
$timezone.Size = New-Object System.Drawing.Size(300, 30)
[void]$timezone.Items.AddRange([object[]](Get-IanaTimeZones))
Style-ComboBox $timezone
$generalCard.Controls.Add($timezone)

$securityCard = New-Object System.Windows.Forms.Panel
$securityCard.Location = New-Object System.Drawing.Point(18, 294)
$securityCard.Size = New-Object System.Drawing.Size(1012, 114)
$securityCard.Anchor = "Top,Left,Right"
$securityCard.BackColor = [System.Drawing.Color]::White
$securityCard.BorderStyle = "FixedSingle"
$tabProject.Controls.Add($securityCard)

$securityTitle = New-Object System.Windows.Forms.Label
$securityTitle.Text = "Acceso al panel de control"
$securityTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$securityTitle.ForeColor = $script:UiBlue
$securityTitle.Location = New-Object System.Drawing.Point(18, 14)
$securityTitle.AutoSize = $true
$securityCard.Controls.Add($securityTitle)

$adminKeyLabel = New-Object System.Windows.Forms.Label
$adminKeyLabel.Text = "Clave administrativa del panel"
$adminKeyLabel.Location = New-Object System.Drawing.Point(18, 48)
$adminKeyLabel.AutoSize = $true
$securityCard.Controls.Add($adminKeyLabel)

$adminKey = New-Object System.Windows.Forms.TextBox
$adminKey.UseSystemPasswordChar = $false
$adminKey.Location = New-Object System.Drawing.Point(18, 72)
$adminKey.Size = New-Object System.Drawing.Size(590, 28)
Style-TextBox $adminKey
$securityCard.Controls.Add($adminKey)

$hideAdminKey = New-Object System.Windows.Forms.CheckBox
$hideAdminKey.Text = "Ocultar clave"
$hideAdminKey.Location = New-Object System.Drawing.Point(632, 74)
$hideAdminKey.AutoSize = $true
$hideAdminKey.Checked = $false
$hideAdminKey.Cursor = [System.Windows.Forms.Cursors]::Hand
$securityCard.Controls.Add($hideAdminKey)

$adminKeyWarning = New-Object System.Windows.Forms.Label
$adminKeyWarning.Text = "IMPORTANTE: guarda esta clave. La necesitarás después para entrar en el panel de control."
$adminKeyWarning.Location = New-Object System.Drawing.Point(18, 96)
$adminKeyWarning.Size = New-Object System.Drawing.Size(760, 16)
$adminKeyWarning.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
$adminKeyWarning.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
$securityCard.Controls.Add($adminKeyWarning)

$hideAdminKey.Add_CheckedChanged({
    $adminKey.UseSystemPasswordChar = $hideAdminKey.Checked
})

$publisherCard = New-Object System.Windows.Forms.Panel
$publisherCard.Location = New-Object System.Drawing.Point(18, 422)
$publisherCard.Size = New-Object System.Drawing.Size(1012, 114)
$publisherCard.Anchor = "Top,Left,Right"
$publisherCard.BackColor = [System.Drawing.Color]::White
$publisherCard.BorderStyle = "FixedSingle"
$tabProject.Controls.Add($publisherCard)

$publisherTitle = New-Object System.Windows.Forms.Label
$publisherTitle.Text = "Cuenta publicadora principal"
$publisherTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$publisherTitle.ForeColor = $script:UiBlue
$publisherTitle.Location = New-Object System.Drawing.Point(18, 14)
$publisherTitle.AutoSize = $true
$publisherCard.Controls.Add($publisherTitle)

$mainUserLabel = New-Object System.Windows.Forms.Label
$mainUserLabel.Text = "Cuenta publicadora principal"
$mainUserLabel.Location = New-Object System.Drawing.Point(18, 48)
$mainUserLabel.AutoSize = $true
$publisherCard.Controls.Add($mainUserLabel)

$mainUser = New-Object System.Windows.Forms.TextBox
$mainUser.Location = New-Object System.Drawing.Point(18, 72)
$mainUser.Size = New-Object System.Drawing.Size(340, 28)
Style-TextBox $mainUser
$publisherCard.Controls.Add($mainUser)

$mainPassLabel = New-Object System.Windows.Forms.Label
$mainPassLabel.Text = "Contraseña de la cuenta principal"
$mainPassLabel.Location = New-Object System.Drawing.Point(400, 48)
$mainPassLabel.AutoSize = $true
$publisherCard.Controls.Add($mainPassLabel)

$mainPass = New-Object System.Windows.Forms.TextBox
$mainPass.UseSystemPasswordChar = $true
$mainPass.Location = New-Object System.Drawing.Point(400, 72)
$mainPass.Size = New-Object System.Drawing.Size(340, 28)
Style-TextBox $mainPass
$publisherCard.Controls.Add($mainPass)

$noteCard = New-Object System.Windows.Forms.Panel
$noteCard.Location = New-Object System.Drawing.Point(18, 550)
$noteCard.Size = New-Object System.Drawing.Size(1012, 66)
$noteCard.Anchor = "Top,Left,Right"
$noteCard.BackColor = $script:UiBlueSoft
$noteCard.BorderStyle = "FixedSingle"
$tabProject.Controls.Add($noteCard)

$noteIcon = New-Object System.Windows.Forms.Label
$noteIcon.Text = "ⓘ"
$noteIcon.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 18, [System.Drawing.FontStyle]::Bold)
$noteIcon.ForeColor = $script:UiBlue
$noteIcon.Location = New-Object System.Drawing.Point(18, 15)
$noteIcon.Size = New-Object System.Drawing.Size(38, 34)
$noteIcon.TextAlign = "MiddleCenter"
$noteCard.Controls.Add($noteIcon)

$note = New-Object System.Windows.Forms.Label
$note.Text = "Si Node.js no está instalado, se instalará automáticamente mediante Windows Package Manager. Cloudflare abrirá una sola ventana del navegador para autorizar la cuenta."
$note.Location = New-Object System.Drawing.Point(64, 14)
$note.Size = New-Object System.Drawing.Size(860, 42)
$note.ForeColor = [System.Drawing.Color]::FromArgb(16, 70, 110)
$noteCard.Controls.Add($note)

$tabForums = New-Object System.Windows.Forms.TabPage
$tabForums.Text = "🌐  Foros"
$tabForums.BackColor = $script:UiSurface
$tabs.TabPages.Add($tabForums)

$forumsHelp = New-Object System.Windows.Forms.Label
$forumsHelp.Text = "Añade todos los foros donde se publicarán los temas. Cada URL debe comenzar por https://"
$forumsHelp.Location = New-Object System.Drawing.Point(22, 18)
$forumsHelp.Size = New-Object System.Drawing.Size(980, 26)
$forumsHelp.Anchor = "Top,Left,Right"
$forumsHelp.ForeColor = $script:UiMuted
$tabForums.Controls.Add($forumsHelp)

$forumsGrid = New-Object System.Windows.Forms.DataGridView
$forumsGrid.Location = New-Object System.Drawing.Point(22, 106)
$forumsGrid.Size = New-Object System.Drawing.Size(1000, 310)
$forumsGrid.Anchor = "Top,Bottom,Left,Right"
$forumsGrid.AllowUserToAddRows = $true
$forumsGrid.AllowUserToDeleteRows = $true
$forumsGrid.AutoSizeColumnsMode = "Fill"
$forumsGrid.RowHeadersVisible = $false
$forumsGrid.EditMode = "EditOnEnter"
$forumsGrid.SelectionMode = "CellSelect"
$forumsGrid.MultiSelect = $false
$forumsGrid.Columns.Add("Label", "Nombre visible") | Out-Null
$forumsGrid.Columns.Add("Url", "URL completa del foro") | Out-Null
Style-Grid $forumsGrid
$tabForums.Controls.Add($forumsGrid)

$deactivateForumButton = New-Object System.Windows.Forms.Button
$deactivateForumButton.Text = Get-UiText "deactivateForumButton"
$deactivateForumButton.Location = New-Object System.Drawing.Point(282, 56)
$deactivateForumButton.Size = New-Object System.Drawing.Size(250, 38)
$deactivateForumButton.Anchor = "Top,Left"
Style-Button $deactivateForumButton $false
$tabForums.Controls.Add($deactivateForumButton)

$loadForumsButton = New-Object System.Windows.Forms.Button
$loadForumsButton.Text = Get-UiText "loadInstalledDataButton"
$loadForumsButton.Location = New-Object System.Drawing.Point(22, 56)
$loadForumsButton.Size = New-Object System.Drawing.Size(240, 38)
$loadForumsButton.Anchor = "Top,Left"
Style-Button $loadForumsButton $false
$tabForums.Controls.Add($loadForumsButton)
$loadForumsButton.BringToFront()
$deactivateForumButton.BringToFront()

$tabAccounts = New-Object System.Windows.Forms.TabPage
$tabAccounts.Text = "👤  Cuentas adicionales"
$tabAccounts.BackColor = $script:UiSurface
$tabs.TabPages.Add($tabAccounts)

$accountsHelp = New-Object System.Windows.Forms.Label
$accountsHelp.Text = "Añade una fila por cada cuenta publicadora adicional. El identificador se generará a partir del usuario."
$accountsHelp.Location = New-Object System.Drawing.Point(22, 18)
$accountsHelp.Size = New-Object System.Drawing.Size(980, 26)
$accountsHelp.Anchor = "Top,Left,Right"
$accountsHelp.ForeColor = $script:UiMuted
$tabAccounts.Controls.Add($accountsHelp)

$accountsGrid = New-Object System.Windows.Forms.DataGridView
$accountsGrid.Location = New-Object System.Drawing.Point(22, 106)
$accountsGrid.Size = New-Object System.Drawing.Size(1000, 310)
$accountsGrid.Anchor = "Top,Bottom,Left,Right"
$accountsGrid.AllowUserToAddRows = $true
$accountsGrid.AllowUserToDeleteRows = $true
$accountsGrid.AutoSizeColumnsMode = "Fill"
$accountsGrid.RowHeadersVisible = $false
$accountsGrid.EditMode = "EditOnEnter"
$accountsGrid.SelectionMode = "CellSelect"
$accountsGrid.MultiSelect = $false
$accountsGrid.Columns.Add("Username", "Usuario Foroactivo") | Out-Null
$accountsGrid.Columns.Add("Password", "Contraseña") | Out-Null
$accountsGrid.Columns.Add("AccountKey", "Clave interna") | Out-Null
$accountsGrid.Columns["AccountKey"].Visible = $false
Style-Grid $accountsGrid
$tabAccounts.Controls.Add($accountsGrid)

$deactivateAccountButton = New-Object System.Windows.Forms.Button
$deactivateAccountButton.Text = Get-UiText "deactivateAccountButton"
$deactivateAccountButton.Location = New-Object System.Drawing.Point(282, 56)
$deactivateAccountButton.Size = New-Object System.Drawing.Size(270, 38)
$deactivateAccountButton.Anchor = "Top,Left"
Style-Button $deactivateAccountButton $false
$tabAccounts.Controls.Add($deactivateAccountButton)

$loadAccountsButton = New-Object System.Windows.Forms.Button
$loadAccountsButton.Text = Get-UiText "loadInstalledDataButton"
$loadAccountsButton.Location = New-Object System.Drawing.Point(22, 56)
$loadAccountsButton.Size = New-Object System.Drawing.Size(240, 38)
$loadAccountsButton.Anchor = "Top,Left"
Style-Button $loadAccountsButton $false
$tabAccounts.Controls.Add($loadAccountsButton)
$loadAccountsButton.BringToFront()
$deactivateAccountButton.BringToFront()

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = "▶  Progreso"
$tabLog.BackColor = $script:UiSurface
$tabs.TabPages.Add($tabLog)

$progressTitle = New-Object System.Windows.Forms.Label
$progressTitle.Text = Get-UiText "ready"
$progressTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$progressTitle.ForeColor = $script:UiText
$progressTitle.Location = New-Object System.Drawing.Point(22, 18)
$progressTitle.Size = New-Object System.Drawing.Size(730, 30)
$progressTitle.Anchor = "Top,Left,Right"
$tabLog.Controls.Add($progressTitle)

$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = Get-UiText "backupButton"
$backupButton.Location = New-Object System.Drawing.Point(802, 14)
$backupButton.Size = New-Object System.Drawing.Size(220, 36)
$backupButton.Anchor = "Top,Right"
Style-Button $backupButton $false
$tabLog.Controls.Add($backupButton)

$installProgress = New-Object System.Windows.Forms.ProgressBar
$installProgress.Location = New-Object System.Drawing.Point(22, 56)
$installProgress.Size = New-Object System.Drawing.Size(1000, 22)
$installProgress.Anchor = "Top,Left,Right"
$installProgress.Minimum = 0
$installProgress.Maximum = 100
$installProgress.Value = 0
$tabLog.Controls.Add($installProgress)

$stepsList = New-Object System.Windows.Forms.ListView
$stepsList.Location = New-Object System.Drawing.Point(22, 92)
$stepsList.Size = New-Object System.Drawing.Size(1000, 210)
$stepsList.Anchor = "Top,Left,Right"
$stepsList.View = "Details"
$stepsList.HeaderStyle = "None"
$stepsList.FullRowSelect = $false
$stepsList.GridLines = $false
$stepsList.BackColor = [System.Drawing.Color]::White
$stepsList.BorderStyle = "FixedSingle"
$stepsList.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$stepsList.Columns.Add("", 46) | Out-Null
$stepsList.Columns.Add("", 900) | Out-Null

$stepNames = @(
    (Get-UiText "step1"),
    (Get-UiText "step2"),
    (Get-UiText "step3"),
    (Get-UiText "step4"),
    (Get-UiText "step5"),
    (Get-UiText "step6"),
    (Get-UiText "step7"),
    (Get-UiText "step8"),
    (Get-UiText "step9"),
    (Get-UiText "step10")
)

foreach ($stepName in $stepNames) {
    $item = New-Object System.Windows.Forms.ListViewItem("○")
    $item.SubItems.Add($stepName) | Out-Null
    $item.ForeColor = $script:UiMuted
    $stepsList.Items.Add($item) | Out-Null
}

$tabLog.Controls.Add($stepsList)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = "Detalles técnicos"
$logLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$logLabel.ForeColor = $script:UiMuted
$logLabel.Location = New-Object System.Drawing.Point(22, 316)
$logLabel.Size = New-Object System.Drawing.Size(980, 22)
$logLabel.Anchor = "Top,Left,Right"
$tabLog.Controls.Add($logLabel)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Location = New-Object System.Drawing.Point(22, 342)
$logBox.Size = New-Object System.Drawing.Size(1000, 130)
$logBox.Anchor = "Top,Bottom,Left,Right"
$logBox.BackColor = [System.Drawing.Color]::FromArgb(18, 30, 42)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(214, 238, 251)
$logBox.BorderStyle = "FixedSingle"
$tabLog.Controls.Add($logBox)

$bottomPanel = New-Object System.Windows.Forms.Panel
$bottomPanel.Dock = "Bottom"
$bottomPanel.Height = 78
$bottomPanel.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($bottomPanel)
$bottomPanel.BringToFront()

$actionHint = New-Object System.Windows.Forms.Label
$actionHint.Text = Get-UiText "actionHint"
$actionHint.Location = New-Object System.Drawing.Point(176, 19)
$actionHint.Size = New-Object System.Drawing.Size(280, 40)
$actionHint.ForeColor = $script:UiMuted
$actionHint.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$bottomPanel.Controls.Add($actionHint)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "＋  Nueva instalación"
$installButton.Size = New-Object System.Drawing.Size(220, 46)
$installButton.Location = New-Object System.Drawing.Point(852, 16)
$installButton.Anchor = "Top,Right"
Style-Button $installButton $true
$bottomPanel.Controls.Add($installButton)

$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = "✓  Actualizar instalación"
$updateButton.Size = New-Object System.Drawing.Size(250, 46)
$updateButton.Location = New-Object System.Drawing.Point(582, 16)
$updateButton.Anchor = "Top,Right"
Style-Button $updateButton $true
$updateButton.BackColor = [System.Drawing.Color]::FromArgb(15, 139, 91)
$updateButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(10, 112, 72)
$updateButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(8, 91, 59)
$bottomPanel.Controls.Add($updateButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Cerrar"
$closeButton.Size = New-Object System.Drawing.Size(130, 44)
$closeButton.Location = New-Object System.Drawing.Point(24, 17)
$closeButton.Anchor = "Top,Left"
Style-Button $closeButton $false
$bottomPanel.Controls.Add($closeButton)

$actionToolTip = New-Object System.Windows.Forms.ToolTip
$actionToolTip.SetToolTip($updateButton, (Get-UiText "updateToolTip"))
$actionToolTip.SetToolTip($installButton, (Get-UiText "installToolTip"))
$actionToolTip.SetToolTip($backupButton, (Get-UiText "backupToolTip"))

function Apply-InstallerLanguage {
    $form.Text = Get-UiText "windowTitle"
    $title.Text = Get-UiText "windowTitle"
    $subtitle.Text = Get-UiText "subtitle"
    $productBadge.Text = Get-UiText "productBadge"
    $languageLabel.Text = Get-UiText "languageLabel"
    $tabProject.Text = Get-UiText "tabProject"
    $tabForums.Text = Get-UiText "tabForums"
    $tabAccounts.Text = Get-UiText "tabAccounts"
    $tabLog.Text = Get-UiText "tabProgress"
    $legalTitle.Text = Get-UiText "legalTitle"
    $legalText.Text = Get-UiText "legalBody"
    $generalTitle.Text = Get-UiText "generalTitle"
    $securityTitle.Text = Get-UiText "securityTitle"
    $publisherTitle.Text = Get-UiText "publisherTitle"
    $projectNameLabel.Text = Get-UiText "projectNameLabel"
    $timezoneLabel.Text = Get-UiText "timezoneLabel"
    $adminKeyLabel.Text = Get-UiText "adminKeyLabel"
    $hideAdminKey.Text = Get-UiText "hideAdminKey"
    $adminKeyWarning.Text = Get-UiText "adminKeyWarning"
    $mainUserLabel.Text = Get-UiText "mainUserLabel"
    $mainPassLabel.Text = Get-UiText "mainPassLabel"
    $note.Text = Get-UiText "note"
    $forumsHelp.Text = Get-UiText "forumsHelp"
    $accountsHelp.Text = Get-UiText "accountsHelp"
    $forumsGrid.Columns["Label"].HeaderText = Get-UiText "forumLabelColumn"
    $forumsGrid.Columns["Url"].HeaderText = Get-UiText "forumUrlColumn"
    $accountsGrid.Columns["Username"].HeaderText = Get-UiText "accountUsernameColumn"
    $accountsGrid.Columns["Password"].HeaderText = Get-UiText "accountPasswordColumn"
    $accountsGrid.Columns["AccountKey"].HeaderText = Get-UiText "accountKeyColumn"
    $deactivateForumButton.Text = Get-UiText "deactivateForumButton"
    $deactivateAccountButton.Text = Get-UiText "deactivateAccountButton"
    $loadForumsButton.Text = Get-UiText "loadInstalledDataButton"
    $loadAccountsButton.Text = Get-UiText "loadInstalledDataButton"
    $logLabel.Text = Get-UiText "logLabel"
    $installButton.Text = Get-UiText "installButton"
    $updateButton.Text = Get-UiText "updateButton"
    $backupButton.Text = Get-UiText "backupButton"
    $actionHint.Text = Get-UiText "actionHint"
    $actionToolTip.SetToolTip($updateButton, (Get-UiText "updateToolTip"))
    $actionToolTip.SetToolTip($installButton, (Get-UiText "installToolTip"))
    $actionToolTip.SetToolTip($backupButton, (Get-UiText "backupToolTip"))
    $closeButton.Text = Get-UiText "closeButton"

    if ($installProgress.Value -eq 0) {
        Set-ProgressStepList @(
            (Get-UiText "step1"),
            (Get-UiText "step2"),
            (Get-UiText "step3"),
            (Get-UiText "step4"),
            (Get-UiText "step5"),
            (Get-UiText "step6"),
            (Get-UiText "step7"),
            (Get-UiText "step8"),
            (Get-UiText "step9"),
            (Get-UiText "step10")
        ) (Get-UiText "ready")
    }
}

$languageSelector.Add_SelectedIndexChanged({
    if ($languageSelector.SelectedItem -match "^([A-Z]{2})") {
        $script:CurrentLanguage = $Matches[1]
        Apply-InstallerLanguage
    }
})

Apply-InstallerLanguage

$form.Add_FormClosing({
    $script:InstallerIsClosing = $true
    Stop-InstallerChildProcesses
})

$closeButton.Add_Click({ $form.Close() })

function Test-MaintenanceD1Connection([string]$databaseName, [string]$workerUrl, $identity, $config, [string]$configPath) {
    Ensure-CloudflareSessionForIdentity $identity
    Set-WranglerAccountBinding $config $identity
    Save-WranglerConfig $config $configPath

    try {
        Execute-Sql "SELECT 1;"
        return
    }
    catch {
        Append-Log($_.Exception.Message)
        Append-Log("La D1 no respondió con el ID/configuración actual. Se buscará por nombre en la cuenta activa.")
    }

    $reconciledId = Reconcile-D1DatabaseBinding $identity $config $configPath
    if (-not [string]::IsNullOrWhiteSpace($reconciledId)) {
        try {
            Execute-Sql "SELECT 1;"
            Append-Log("La D1 vinculada respondió correctamente tras actualizar su ID interno.")
            return
        }
        catch {
            Append-Log($_.Exception.Message)
        }
    }

    Append-Log("La D1 no respondió en la cuenta activa. Se forzará una nueva autorización de Cloudflare y se reintentará una vez.")
    $script:CloudflareWhoamiOutput = ""
    $null = Invoke-CloudflareLogin $true

    $reconciledId = Reconcile-D1DatabaseBinding $identity $config $configPath
    if (-not [string]::IsNullOrWhiteSpace($reconciledId)) {
        try {
            Execute-Sql "SELECT 1;"
            Append-Log("La D1 vinculada respondió correctamente tras renovar Cloudflare y actualizar su ID interno.")
            return
        }
        catch {
            Append-Log($_.Exception.Message)
        }
    }

    try {
        Execute-Sql "SELECT 1;"
        Append-Log("La D1 vinculada respondió correctamente tras renovar la autorización de Cloudflare.")
    }
    catch {
        Append-Log($_.Exception.Message)
        throw "La base D1 vinculada a esta instalación no respondió en la cuenta activa.`n`nD1 usada por esta instalación: $databaseName`nWorker vinculado: $workerUrl`n`nComprueba que Wrangler esté autorizado en la cuenta Cloudflare correcta. No se ha modificado nada."
    }
}

function Get-SafeBackupNamePart([string]$value) {
    $name = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return "d1" }
    $name = [Regex]::Replace($name, "[^A-Za-z0-9_-]+", "-")
    $name = $name.Trim("-")
    if ([string]::IsNullOrWhiteSpace($name)) { return "d1" }
    return $name
}

function Get-D1BackupFolder {
    $base = $script:OutputFolder
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = $script:OutputBaseFolder
    }
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = $root
    }

    $folder = Join-Path $base "d1_backups"
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    return $folder
}

function New-D1Backup([string]$reason) {
    Set-InstallerOutputFolderForLanguage $script:CurrentLanguage
    $identity = Load-InstallationIdentity
    $databaseName = [string]$identity.d1_database_name
    if ([string]::IsNullOrWhiteSpace($databaseName)) {
        throw "No se encontró el nombre de la base D1 vinculada a esta instalación."
    }

    $configPath = Join-Path $root "wrangler.jsonc"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $config.name = [string]$identity.worker_name
    Set-WranglerAccountBinding $config $identity
    $config.d1_databases[0].database_name = $databaseName
    if (-not [string]::IsNullOrWhiteSpace([string]$identity.d1_database_id)) {
        $config.d1_databases[0] | Add-Member -NotePropertyName "database_id" -NotePropertyValue ([string]$identity.d1_database_id) -Force
    }
    Save-WranglerConfig $config $configPath

    $script:D1ExecuteTarget = "DB"
    Test-MaintenanceD1Connection $databaseName ([string]$identity.worker_url) $identity $config $configPath

    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $safeName = Get-SafeBackupNamePart $databaseName
    $safeReason = Get-SafeBackupNamePart $reason
    $backupPath = Join-Path (Get-D1BackupFolder) ($safeName + "_" + $stamp + "_" + $safeReason + ".sql")

    Append-Log("Creating D1 backup: $backupPath")
    Run-Command $script:NpxCommand "wrangler d1 export `"$databaseName`" --remote --output `"$backupPath`" --skip-confirmation"

    if (-not (Test-Path -LiteralPath $backupPath)) {
        throw "Wrangler finished the export, but the backup file was not found: $backupPath"
    }

    return $backupPath
}

function Initialize-MaintenanceD1Context {
    Ensure-NodeTools

    if (-not (Test-Path (Join-Path $root "node_modules"))) {
        Append-Log(Get-LogText "preparingDeps")
        Run-Command $script:NpmCommand "install"
    }

    $whoamiOutput = Invoke-CloudflareLogin
    $identity = Load-InstallationIdentity
    $project = [string]$identity.worker_name
    $databaseName = [string]$identity.d1_database_name
    $databaseId = [string]$identity.d1_database_id
    $script:D1ExecuteTarget = "DB"

    $configPath = Join-Path $root "wrangler.jsonc"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $config.name = $project
    Set-WranglerAccountBinding $config $identity
    $config.d1_databases[0].database_name = $databaseName
    if ([string]::IsNullOrWhiteSpace($databaseId)) {
        if ($config.d1_databases[0].PSObject.Properties["database_id"]) {
            $config.d1_databases[0].PSObject.Properties.Remove("database_id")
        }
    } else {
        $config.d1_databases[0] | Add-Member -NotePropertyName "database_id" -NotePropertyValue $databaseId -Force
    }
    Save-WranglerConfig $config $configPath

    Test-MaintenanceD1Connection $databaseName ([string]$identity.worker_url) $identity $config $configPath
}

function Get-SelectedGridRow([System.Windows.Forms.DataGridView]$grid) {
    if ($null -eq $grid.CurrentRow -or $grid.CurrentRow.IsNewRow) {
        return $null
    }
    return $grid.CurrentRow
}

function Load-InstalledDataFromD1 {
    $loadForumsButton.Enabled = $false
    $loadAccountsButton.Enabled = $false
    $deactivateForumButton.Enabled = $false
    $deactivateAccountButton.Enabled = $false
    $installButton.Enabled = $false
    $updateButton.Enabled = $false
    $backupButton.Enabled = $false

    try {
        $tabs.SelectedTab = $tabLog
        $logBox.Clear()
        Initialize-MaintenanceD1Context

        $forumRows = Get-D1Rows "SELECT label, forum_url FROM publication_forums WHERE active = 1 ORDER BY label COLLATE NOCASE, forum_url COLLATE NOCASE;"
        $accountRows = Get-D1Rows "SELECT label, account_key FROM publication_accounts WHERE active = 1 ORDER BY label COLLATE NOCASE, account_key COLLATE NOCASE;"

        $forumsGrid.Rows.Clear()
        $script:InstalledDataLoaded = $true
        foreach ($item in @($forumRows)) {
            $label = [string]$item.label
            $url = [string]$item.forum_url
            if (-not [string]::IsNullOrWhiteSpace($url)) {
                [void]$forumsGrid.Rows.Add($label, $url)
            }
        }

        $accountsGrid.Rows.Clear()
        foreach ($item in @($accountRows)) {
            $label = [string]$item.label
            $key = [string]$item.account_key
            $name = if (-not [string]::IsNullOrWhiteSpace($label)) { $label } else { $key }
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                [void]$accountsGrid.Rows.Add($name, "", $key)
            }
        }

        $forumCount = [Math]::Max(0, $forumsGrid.Rows.Count - 1)
        $accountCount = [Math]::Max(0, $accountsGrid.Rows.Count - 1)
        Append-Log([string]::Format((Get-UiText "installedDataLoaded"), $forumCount, $accountCount))
        Show-Info([string]::Format((Get-UiText "installedDataLoaded"), $forumCount, $accountCount))
    }
    catch {
        $script:InstalledDataLoaded = $false
        Show-Error($_.Exception.Message)
    }
    finally {
        $loadForumsButton.Enabled = $true
        $loadAccountsButton.Enabled = $true
        $deactivateForumButton.Enabled = $true
        $deactivateAccountButton.Enabled = $true
        $installButton.Enabled = $true
        $updateButton.Enabled = $true
        $backupButton.Enabled = $true
    }
}

$loadForumsButton.Add_Click({
    Load-InstalledDataFromD1
    $tabs.SelectedTab = $tabForums
})

$loadAccountsButton.Add_Click({
    Load-InstalledDataFromD1
    $tabs.SelectedTab = $tabAccounts
})

$backupButton.Add_Click({
    try {
        $backupButton.Enabled = $false
        $installButton.Enabled = $false
        $updateButton.Enabled = $false
        $tabs.SelectedTab = $tabLog
        $logBox.Clear()
        Initialize-MaintenanceD1Context
        $backupPath = New-D1Backup "manual"
        Append-Log([string]::Format((Get-UiText "backupCreated"), $backupPath))
        Show-Info([string]::Format((Get-UiText "backupCreated"), $backupPath))
    }
    catch {
        Append-Log((Get-LogText "errorPrefix") + $_.Exception.Message)
        Show-Error($_.Exception.Message)
    }
    finally {
        $backupButton.Enabled = $true
        $installButton.Enabled = $true
        $updateButton.Enabled = $true
    }
})

$deactivateForumButton.Add_Click({
    $row = Get-SelectedGridRow $forumsGrid
    if ($null -eq $row) {
        Show-Error(Get-UiText "selectForumToDeactivate")
        return
    }

    $label = [string]$row.Cells["Label"].Value
    $url = [string]$row.Cells["Url"].Value

    if ([string]::IsNullOrWhiteSpace($url)) {
        Show-Error(Get-UiText "selectForumToDeactivate")
        return
    }

    $answer = Show-AppDialog `
        ((Get-UiText "confirmDeactivateForum") + "`n`n" + $label + "`n" + $url) `
        (Get-UiText "deactivateForumButton") `
        "YesNo" `
        "Warning" `
        $form
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $deactivateForumButton.Enabled = $false
        $installButton.Enabled = $false
        $updateButton.Enabled = $false
        $backupButton.Enabled = $false
        $tabs.SelectedTab = $tabLog
        $logBox.Clear()
        Initialize-MaintenanceD1Context
        $backupPath = New-D1Backup "antes-desactivar-foro"
        Append-Log([string]::Format((Get-UiText "backupAutoCreated"), $backupPath))
        Execute-Sql ("DELETE FROM publication_forums WHERE forum_url = " + (Sql-Text $url) + ";")
        Append-Log(Get-UiText "forumDeactivated")
        $forumsGrid.Rows.Remove($row)
        Show-Info(Get-UiText "forumDeactivated")
    }
    catch {
        Append-Log((Get-LogText "errorPrefix") + $_.Exception.Message)
        Show-Error($_.Exception.Message)
    }
    finally {
        $deactivateForumButton.Enabled = $true
        $installButton.Enabled = $true
        $updateButton.Enabled = $true
        $backupButton.Enabled = $true
    }
})

$deactivateAccountButton.Add_Click({
    $row = Get-SelectedGridRow $accountsGrid
    if ($null -eq $row) {
        Show-Error(Get-UiText "selectAccountToDeactivate")
        return
    }

    $username = [string]$row.Cells["Username"].Value

    if ([string]::IsNullOrWhiteSpace($username)) {
        Show-Error(Get-UiText "selectAccountToDeactivate")
        return
    }

    $key = ""
    if ($accountsGrid.Columns.Contains("AccountKey")) {
        $key = [string]$row.Cells["AccountKey"].Value
    }
    if ([string]::IsNullOrWhiteSpace($key)) {
        $key = Normalize-Key $username
    }
    if ($key -eq "default") {
        Show-Error(Get-UiText "mainAccountCannotDelete")
        return
    }
    $answer = Show-AppDialog `
        ((Get-UiText "confirmDeactivateAccount") + "`n`n" + $username) `
        (Get-UiText "deactivateAccountButton") `
        "YesNo" `
        "Warning" `
        $form
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $deactivateAccountButton.Enabled = $false
        $installButton.Enabled = $false
        $updateButton.Enabled = $false
        $backupButton.Enabled = $false
        $tabs.SelectedTab = $tabLog
        $logBox.Clear()
        Initialize-MaintenanceD1Context
        $backupPath = New-D1Backup "antes-desactivar-cuenta"
        Append-Log([string]::Format((Get-UiText "backupAutoCreated"), $backupPath))
        Execute-Sql ("DELETE FROM publication_accounts WHERE account_key = " + (Sql-Text $key) + " AND account_key <> 'default';")
        if ($key -ne "default") {
            Remove-SecretIfExists ("FOROACTIVO_USERNAME_" + $key)
            Remove-SecretIfExists ("FOROACTIVO_PASSWORD_" + $key)
        }
        Append-Log(Get-UiText "accountDeactivated")
        $accountsGrid.Rows.Remove($row)
        Show-Info(Get-UiText "accountDeactivated")
    }
    catch {
        Append-Log((Get-LogText "errorPrefix") + $_.Exception.Message)
        Show-Error($_.Exception.Message)
    }
    finally {
        $deactivateAccountButton.Enabled = $true
        $installButton.Enabled = $true
        $updateButton.Enabled = $true
        $backupButton.Enabled = $true
    }
})

$updateButton.Add_Click({
    try {
        $updateButton.Enabled = $false
        $installButton.Enabled = $false
        $backupButton.Enabled = $false
        $tabs.SelectedTab = $tabLog
        $logBox.Clear()
        Reset-InstallProgress

        Set-InstallStep 1 (Get-UiText "step1") "working"
        Ensure-NodeTools
        Complete-InstallStep 1 (Get-UiText "step1")

        Set-InstallStep 2 (Get-UiText "step2") "working"
        if (-not (Test-Path (Join-Path $root "node_modules"))) {
            Append-Log(Get-LogText "preparingDeps")
            Run-Command $script:NpmCommand "install"
        }
        Complete-InstallStep 2 (Get-UiText "step2")

        Set-InstallStep 4 (Get-UiText "step4") "working"
        $whoamiOutput = Invoke-CloudflareLogin
        Complete-InstallStep 4 (Get-UiText "step4")

        $identity = Load-InstallationIdentity
        $project = [string]$identity.worker_name
        $databaseName = [string]$identity.d1_database_name
        $databaseId = [string]$identity.d1_database_id
        $script:D1ExecuteTarget = "DB"
        $projectName.Text = $project

        $configPath = Join-Path $root "wrangler.jsonc"
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.name = $project
        Set-WranglerAccountBinding $config $identity
        $config.d1_databases[0].database_name = $databaseName
        if ([string]::IsNullOrWhiteSpace($databaseId)) {
            if ($config.d1_databases[0].PSObject.Properties["database_id"]) {
                $config.d1_databases[0].PSObject.Properties.Remove("database_id")
            }
        } else {
            $config.d1_databases[0] | Add-Member -NotePropertyName "database_id" -NotePropertyValue $databaseId -Force
        }
        Save-WranglerConfig $config $configPath

        Test-MaintenanceD1Connection $databaseName ([string]$identity.worker_url) $identity $config $configPath

        Set-InstallStep 8 (Get-UiText "step8") "working"
        $backupPath = New-D1Backup "antes-actualizar"
        Append-Log([string]::Format((Get-UiText "backupAutoCreated"), $backupPath))
        $changes = 0
        $desiredForumUrls = New-StringSet
        $desiredAccountKeys = New-StringSet

        $adminUpdate = $adminKey.Text
        $mainUserUpdate = $mainUser.Text.Trim()
        $mainPassUpdate = $mainPass.Text

        if (-not [string]::IsNullOrWhiteSpace($adminUpdate)) {
            Put-Secret "ADMIN_API_KEY" $adminUpdate
            Set-AdminKeyHashInD1 $adminUpdate
            Append-Log(Get-UiText "maintenanceAdminUpdated")
            $changes++
        }

        if (-not [string]::IsNullOrWhiteSpace($mainUserUpdate) -or
            -not [string]::IsNullOrWhiteSpace($mainPassUpdate)) {
            if ([string]::IsNullOrWhiteSpace($mainUserUpdate) -or
                [string]::IsNullOrWhiteSpace($mainPassUpdate)) {
                throw (Get-UiText "maintenanceMainIncomplete")
            }

            Put-Secret "FOROACTIVO_USERNAME" $mainUserUpdate
            Put-Secret "FOROACTIVO_PASSWORD" $mainPassUpdate
            Execute-Sql (
                "INSERT INTO publication_accounts " +
                "(label, account_key, active) VALUES (" +
                (Sql-Text $mainUserUpdate) + ", 'default', 1) " +
                "ON CONFLICT(account_key) DO UPDATE SET " +
                "label = excluded.label, active = 1;"
            )
            [void]$desiredAccountKeys.Add("default")
            Append-Log(Get-UiText "maintenanceMainUpdated")
            $changes++
        }

        foreach ($row in $forumsGrid.Rows) {
            if ($row.IsNewRow) { continue }

            $label = [string]$row.Cells["Label"].Value
            $url = [string]$row.Cells["Url"].Value

            if ([string]::IsNullOrWhiteSpace($label) -and
                [string]::IsNullOrWhiteSpace($url)) {
                continue
            }

            if ([string]::IsNullOrWhiteSpace($label)) {
                throw "Falta el nombre visible de un foro."
            }

            if ([string]::IsNullOrWhiteSpace($url)) {
                throw "Falta la URL del foro '$label'."
            }

            if (-not $url.StartsWith("https://")) {
                throw "La URL del foro '$label' debe comenzar por https://"
            }

            Execute-Sql (
                "INSERT INTO publication_forums " +
                "(label, forum_url, active) VALUES (" +
                (Sql-Text $label) + ", " +
                (Sql-Text $url) + ", 1) " +
                "ON CONFLICT(forum_url) DO UPDATE SET " +
                "label = excluded.label, active = 1;"
            )
            [void]$desiredForumUrls.Add($url)
            $changes++
        }

        foreach ($row in $accountsGrid.Rows) {
            if ($row.IsNewRow) { continue }

            $username = ([string]$row.Cells["Username"].Value).Trim()
            $password = [string]$row.Cells["Password"].Value
            $existingKey = ""
            if ($accountsGrid.Columns.Contains("AccountKey")) {
                $existingKey = [string]$row.Cells["AccountKey"].Value
            }

            if ([string]::IsNullOrWhiteSpace($username) -and
                [string]::IsNullOrWhiteSpace($password)) {
                continue
            }

            if ([string]::IsNullOrWhiteSpace($username)) {
                throw "Falta el usuario de una cuenta publicadora adicional."
            }

            $key = if (-not [string]::IsNullOrWhiteSpace($existingKey)) {
                $existingKey
            } else {
                Normalize-Key $username
            }

            [void]$desiredAccountKeys.Add($key)

            if ([string]::IsNullOrWhiteSpace($password)) {
                if ([string]::IsNullOrWhiteSpace($existingKey)) {
                    throw "Falta la contraseña de la cuenta '$username'."
                }
            } else {
                if ($key -eq "default") {
                    Put-Secret "FOROACTIVO_USERNAME" $username
                    Put-Secret "FOROACTIVO_PASSWORD" $password
                } else {
                    Put-Secret "FOROACTIVO_USERNAME_$key" $username
                    Put-Secret "FOROACTIVO_PASSWORD_$key" $password
                }
            }

            Execute-Sql (
                "INSERT INTO publication_accounts " +
                "(label, account_key, active) VALUES (" +
                (Sql-Text $username) + ", " +
                (Sql-Text $key) + ", 1) " +
                "ON CONFLICT(account_key) DO UPDATE SET " +
                "label = excluded.label, active = 1;"
            )
            $changes++
        }

        if ($script:InstalledDataLoaded) {
            $activeForums = Get-D1Rows "SELECT forum_url FROM publication_forums WHERE active = 1;"
            foreach ($item in @($activeForums)) {
                $oldUrl = [string]$item.forum_url
                if (-not [string]::IsNullOrWhiteSpace($oldUrl) -and
                    -not $desiredForumUrls.Contains($oldUrl)) {
                    Execute-Sql ("DELETE FROM publication_forums WHERE forum_url = " + (Sql-Text $oldUrl) + ";")
                    Append-Log("Foro eliminado de D1: $oldUrl")
                    $changes++
                }
            }

            $activeAccounts = Get-D1Rows "SELECT account_key FROM publication_accounts WHERE active = 1 AND account_key <> 'default';"
            foreach ($item in @($activeAccounts)) {
                $oldKey = [string]$item.account_key
                if (-not [string]::IsNullOrWhiteSpace($oldKey) -and
                    -not $desiredAccountKeys.Contains($oldKey)) {
                    Execute-Sql ("DELETE FROM publication_accounts WHERE account_key = " + (Sql-Text $oldKey) + ";")
                    Remove-SecretIfExists ("FOROACTIVO_USERNAME_" + $oldKey)
                    Remove-SecretIfExists ("FOROACTIVO_PASSWORD_" + $oldKey)
                    Append-Log("Cuenta eliminada de D1: $oldKey")
                    $changes++
                }
            }

            $inactiveAccounts = Get-D1Rows "SELECT account_key FROM publication_accounts WHERE active = 0 AND account_key <> 'default';"
            foreach ($item in @($inactiveAccounts)) {
                $oldKey = [string]$item.account_key
                if (-not [string]::IsNullOrWhiteSpace($oldKey)) {
                    Execute-Sql ("DELETE FROM publication_accounts WHERE account_key = " + (Sql-Text $oldKey) + ";")
                    Remove-SecretIfExists ("FOROACTIVO_USERNAME_" + $oldKey)
                    Remove-SecretIfExists ("FOROACTIVO_PASSWORD_" + $oldKey)
                    Append-Log("Cuenta inactiva purgada de D1: $oldKey")
                    $changes++
                }
            }

            Execute-Sql "DELETE FROM publication_forums WHERE active = 0;"
        }

        if ($changes -eq 0) {
            throw (Get-UiText "maintenanceNoChanges")
        }

        Complete-InstallStep 8 (Get-UiText "step8")
        $installProgress.Value = 100
        $progressTitle.Text = Get-UiText "updateDone"
        Append-Log("")
        Append-Log(Get-LogText "updateDoneLog")

        Show-Info(Get-UiText "maintenanceDone")
    }
    catch {
        foreach ($item in $stepsList.Items) {
            if ($item.SubItems[0].Text -eq "●") {
                $item.SubItems[0].Text = "✕"
                $item.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
            }
        }
        Append-Log("")
        Append-Log((Get-LogText "errorPrefix") + $_.Exception.Message)
        Show-Error($_.Exception.Message)
    }
    finally {
        $updateButton.Enabled = $true
        $installButton.Enabled = $true
        $backupButton.Enabled = $true
    }
})

$installButton.Add_Click({
    if (Test-Path -LiteralPath (Get-InstallationIdentityPath)) {
        $answer = Show-AppDialog `
            (Get-UiText "confirmNewInstallMessage") `
            (Get-UiText "confirmNewInstallTitle") `
            "YesNo" `
            "Warning" `
            $form
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    try {
        $installButton.Enabled = $false
        $updateButton.Enabled = $false
        $backupButton.Enabled = $false
        $tabs.SelectedTab = $tabLog
        $logBox.Clear()
        Reset-InstallProgress

        $projectInput = $projectName.Text.Trim()
        $project = Normalize-ProjectName $projectInput
        $tz = $timezone.Text.Trim()
        $admin = $adminKey.Text
        $user = $mainUser.Text.Trim()
        $pass = $mainPass.Text

        if ([string]::IsNullOrWhiteSpace($projectInput) -or
            [string]::IsNullOrWhiteSpace($tz) -or
            [string]::IsNullOrWhiteSpace($admin) -or
            [string]::IsNullOrWhiteSpace($user) -or
            [string]::IsNullOrWhiteSpace($pass)) {
            throw "Completa todos los campos obligatorios de la pestaña Proyecto."
        }

        if ([string]::IsNullOrWhiteSpace($project)) {
            throw (Get-LogText "projectNameInvalid")
        }

        if ($project -ne $projectInput) {
            $projectName.Text = $project
            Append-Log(([string]::Format((Get-LogText "projectNameNormalized"), $projectInput, $project)))
            Show-AppDialog `
                ([string]::Format((Get-LogText "projectNameWarning"), $projectInput, $project)) `
                (Get-LogText "projectNameWarningTitle") `
                "OK" `
                "Warning" `
                $form | Out-Null
        }

        $script:D1ExecuteTarget = "DB"

        Set-InstallStep 1 (Get-UiText "step1") "working"
        Ensure-NodeTools
        Complete-InstallStep 1 (Get-UiText "step1")

        Set-InstallStep 2 (Get-UiText "step2") "working"
        if (-not (Test-Path (Join-Path $root "node_modules"))) {
            Append-Log(Get-LogText "preparingDeps")
            Run-Command $script:NpmCommand "install"
        }
        Complete-InstallStep 2 (Get-UiText "step2")

        Set-InstallStep 3 (Get-UiText "step3") "working"
        $configPath = Join-Path $root "wrangler.jsonc"
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $databaseName = "$project-db"
        $config.name = $project
        $config.vars.TIME_ZONE = $tz
        $config.d1_databases[0].database_name = $databaseName
        if ($config.d1_databases[0].PSObject.Properties["database_id"]) {
            $config.d1_databases[0].PSObject.Properties.Remove("database_id")
        }
        Save-WranglerConfig $config $configPath
        Complete-InstallStep 3 (Get-UiText "step3")

        Set-InstallStep 4 (Get-UiText "step4") "working"
        $whoamiOutput = Invoke-CloudflareLogin $true
        $accountId = Get-CloudflareAccountIdFromText $whoamiOutput
        if (-not [string]::IsNullOrWhiteSpace($accountId)) {
            $installIdentity = [pscustomobject]@{ account_id = $accountId }
            Set-WranglerAccountBinding $config $installIdentity
            Save-WranglerConfig $config $configPath
        }
        Complete-InstallStep 4 (Get-UiText "step4")

        $databaseId = Ensure-D1Database $config $configPath $databaseName

        Set-InstallStep 5 (Get-UiText "step5") "working"
        Append-Log(Get-LogText "deployWorker")
        $deployOutput = Invoke-DeployWithWorkersDevSubdomain $project
        Complete-InstallStep 5 (Get-UiText "step5")

        Set-InstallStep 6 (Get-UiText "step6") "working"
        Append-Log(Get-LogText "d1Migrations")
        Append-Log(Get-LogText "migrationConfirm")
        Run-Command $script:NpxCommand "wrangler d1 migrations apply DB --remote" "y"
        Complete-InstallStep 6 (Get-UiText "step6")

        Set-InstallStep 7 (Get-UiText "step7") "working"
        Append-Log(Get-LogText "savingSecrets")
        Put-Secret "FOROACTIVO_USERNAME" $user
        Put-Secret "FOROACTIVO_PASSWORD" $pass
        Put-Secret "ADMIN_API_KEY" $admin
        Set-AdminKeyHashInD1 $admin
        Complete-InstallStep 7 (Get-UiText "step7")

        Set-InstallStep 8 (Get-UiText "step8") "working"
        Execute-Sql (
            "INSERT INTO publication_accounts " +
            "(label, account_key, active) VALUES (" +
            (Sql-Text $user) + ", 'default', 1) " +
            "ON CONFLICT(account_key) DO UPDATE SET " +
            "label = excluded.label, active = 1;"
        )

        foreach ($row in $forumsGrid.Rows) {
            if ($row.IsNewRow) { continue }

            $label = [string]$row.Cells["Label"].Value
            $url = [string]$row.Cells["Url"].Value

            if ([string]::IsNullOrWhiteSpace($label) -or
                [string]::IsNullOrWhiteSpace($url)) {
                continue
            }

            if (-not $url.StartsWith("https://")) {
                throw "La URL del foro '$label' debe comenzar por https://"
            }

            Execute-Sql (
                "INSERT INTO publication_forums " +
                "(label, forum_url, active) VALUES (" +
                (Sql-Text $label) + ", " +
                (Sql-Text $url) + ", 1) " +
                "ON CONFLICT(forum_url) DO UPDATE SET " +
                "label = excluded.label, active = 1;"
            )
        }

        foreach ($row in $accountsGrid.Rows) {
            if ($row.IsNewRow) { continue }

            $username = [string]$row.Cells["Username"].Value
            $password = [string]$row.Cells["Password"].Value

            if ([string]::IsNullOrWhiteSpace($username) -or
                [string]::IsNullOrWhiteSpace($password)) {
                continue
            }

            $label = $username

            $key = Normalize-Key $username

            Put-Secret "FOROACTIVO_USERNAME_$key" $username
            Put-Secret "FOROACTIVO_PASSWORD_$key" $password

            Execute-Sql (
                "INSERT INTO publication_accounts " +
                "(label, account_key, active) VALUES (" +
                (Sql-Text $label) + ", " +
                (Sql-Text $key) + ", 1) " +
                "ON CONFLICT(account_key) DO UPDATE SET " +
                "label = excluded.label, active = 1;"
            )
        }
        Complete-InstallStep 8 (Get-UiText "step8")

        Set-InstallStep 9 (Get-UiText "step9") "working"
        Append-Log(Get-LogText "deployFinal")
        $deployOutput = Invoke-DeployWithWorkersDevSubdomain $project
        Complete-InstallStep 9 (Get-UiText "step9")

        Set-InstallStep 10 (Get-UiText "step10") "working"

        $workerUrl = ""
        $urlMatch = [Regex]::Match(
            [string]$deployOutput,
            "https://[a-zA-Z0-9.-]+\.workers\.dev"
        )
        if ($urlMatch.Success) {
            $workerUrl = $urlMatch.Value.TrimEnd("/")
        }

        Save-InstallationIdentity $accountId $project $workerUrl $databaseName $databaseId

        Set-InstallerOutputFolderForLanguage $script:CurrentLanguage
        $installFolder = $script:OutputFolder
        if (-not (Test-Path $installFolder)) {
            New-Item -ItemType Directory -Path $installFolder -Force | Out-Null
        }
        else {
            Get-ChildItem -LiteralPath $installFolder -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $installFolder -Directory -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        $panelSource = Join-Path $root "panel\panel-control.html"
        $formSource = Join-Path $root "panel\formulario-programacion.html"
        $selectedLanguage = $script:CurrentLanguage
        $panelTarget = Join-Path $installFolder (Get-PanelFileName $selectedLanguage)
        $formTarget = Join-Path $installFolder (Get-FormFileName $selectedLanguage)

        if (Test-Path $panelSource) {
            Convert-LocalizedHtml $panelSource $selectedLanguage "panel" $project $workerUrl |
                Set-Content -LiteralPath $panelTarget -Encoding UTF8
        }
        if (Test-Path $formSource) {
            Convert-LocalizedHtml $formSource $selectedLanguage "form" $project $workerUrl |
                Set-Content -LiteralPath $formTarget -Encoding UTF8
        }

        $instructionsText = Get-LocalizedInstructions $selectedLanguage $workerUrl
        $instructionsText = $instructionsText.Replace(
            $workerUrl,
            ($workerUrl + [Environment]::NewLine + [Environment]::NewLine + "D1 DATABASE" + [Environment]::NewLine + $databaseName)
        )
        $instructionsText = Apply-ForumBrand $instructionsText $selectedLanguage
        $instructionsText = $instructionsText.
            Replace("FORMULARIO_DE_PROGRAMACION.html", (Get-FormFileName $selectedLanguage)).
            Replace("PANEL_DE_CONTROL.html", (Get-PanelFileName $selectedLanguage))
        $instructionsText |
            Set-Content -LiteralPath (Join-Path $installFolder (Get-InstructionFileName $selectedLanguage)) -Encoding UTF8

        Complete-InstallStep 10 (Get-UiText "step10")

        Append-Log("")
        Append-Log(Get-LogText "installDoneLog")
        $installProgress.Value = 100
        $progressTitle.Text = Get-UiText "installDone"

        Show-InstallationResult $workerUrl $installFolder
    }
    catch {
        foreach ($item in $stepsList.Items) {
            if ($item.SubItems[0].Text -eq "●") {
                $item.SubItems[0].Text = "✕"
                $item.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
            }
        }
        Append-Log("")
        Append-Log((Get-LogText "errorPrefix") + $_.Exception.Message)
        Show-Error($_.Exception.Message)
    }
    finally {
        $installButton.Enabled = $true
        $updateButton.Enabled = $true
        $backupButton.Enabled = $true
    }
})

[void]$form.ShowDialog()


























