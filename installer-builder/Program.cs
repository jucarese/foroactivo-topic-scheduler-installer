using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Management;
using System.Reflection;
using System.Windows.Forms;

namespace GestorForoactivoInstaller
{
    internal static class Program
    {
        private const string PayloadResourceName = "InstallerPayload.zip";
        private const string ProjectFolderName = "gestor-publicaciones-v1";

        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            try
            {
                string exeDirectory = Path.GetDirectoryName(Assembly.GetEntryAssembly().Location);
                CleanupTransientInstallerItems(exeDirectory);

                string installRoot = Path.Combine(exeDirectory, ".foroactivo_installer_runtime");
                string projectRoot = Path.Combine(installRoot, ProjectFolderName);
                string installerScript = Path.Combine(projectRoot, "scripts", "instalador-gui.ps1");

                StopProcessesUsingDirectory(installRoot);
                TryDeleteDirectoryWithRetries(installRoot);
                if (Directory.Exists(installRoot))
                {
                    throw new IOException("No se pudo limpiar la carpeta temporal del instalador. Cierra cualquier Node.js, PowerShell, Wrangler o ventana que use esta carpeta y vuelve a abrir el instalador:\r\n\r\n" + installRoot);
                }

                Directory.CreateDirectory(installRoot);
                File.SetAttributes(installRoot, File.GetAttributes(installRoot) | FileAttributes.Hidden);
                ExtractPayload(installRoot);
                File.SetAttributes(installRoot, File.GetAttributes(installRoot) | FileAttributes.Hidden);

                if (!File.Exists(installerScript))
                {
                    projectRoot = installRoot;
                    installerScript = Path.Combine(projectRoot, "scripts", "instalador-gui.ps1");
                }

                if (!File.Exists(installerScript))
                {
                    throw new FileNotFoundException("No se encontro la pantalla del instalador dentro del paquete.", installerScript);
                }

                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = ResolvePowerShellExecutable();
                startInfo.Arguments = "-NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + installerScript + "\"";
                startInfo.WorkingDirectory = projectRoot;
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = true;
                startInfo.EnvironmentVariables["FOROACTIVO_INSTALLER_OUTPUT_BASE_DIR"] = exeDirectory;
                startInfo.EnvironmentVariables["FOROACTIVO_INSTALLER_RUNTIME_DIR"] = installRoot;
                startInfo.EnvironmentVariables["TMP"] = installRoot;
                startInfo.EnvironmentVariables["TEMP"] = installRoot;
                startInfo.EnvironmentVariables["npm_config_cache"] = Path.Combine(installRoot, ".npm-cache");

                using (Process process = Process.Start(startInfo))
                {
                    if (process == null)
                    {
                        throw new InvalidOperationException("No se pudo iniciar la pantalla del instalador.");
                    }
                    process.WaitForExit();
                }

                StopProcessesUsingDirectory(installRoot);
                TryDeleteDirectoryWithRetries(installRoot);
            }
            catch (Exception ex)
            {
                ShowStartupError("Could not open the installer.\r\n\r\n" + ex.Message);
            }
            finally
            {
                try
                {
                    string exeDirectory = Path.GetDirectoryName(Assembly.GetEntryAssembly().Location);
                    CleanupTransientInstallerItems(exeDirectory);
                }
                catch { }
            }
        }

        private static void ShowStartupError(string message)
        {
            using (Form dialog = new Form())
            using (Label label = new Label())
            using (PictureBox icon = new PictureBox())
            using (Panel footer = new Panel())
            using (Button ok = new Button())
            {
                dialog.Text = "Foroactivo Installer";
                dialog.StartPosition = FormStartPosition.CenterScreen;
                dialog.ClientSize = new System.Drawing.Size(560, 230);
                dialog.FormBorderStyle = FormBorderStyle.FixedDialog;
                dialog.MaximizeBox = false;
                dialog.MinimizeBox = false;
                dialog.ShowInTaskbar = true;
                dialog.BackColor = System.Drawing.Color.White;
                dialog.Font = new System.Drawing.Font("Segoe UI", 9.5f);

                icon.Image = System.Drawing.SystemIcons.Error.ToBitmap();
                icon.Location = new System.Drawing.Point(28, 38);
                icon.Size = new System.Drawing.Size(48, 48);
                icon.SizeMode = PictureBoxSizeMode.CenterImage;
                dialog.Controls.Add(icon);

                label.Text = message;
                label.Location = new System.Drawing.Point(96, 28);
                label.Size = new System.Drawing.Size(430, 118);
                label.AutoEllipsis = true;
                dialog.Controls.Add(label);

                footer.Dock = DockStyle.Bottom;
                footer.Height = 70;
                footer.BackColor = System.Drawing.Color.FromArgb(246, 248, 251);
                dialog.Controls.Add(footer);

                ok.Text = "OK";
                ok.Size = new System.Drawing.Size(112, 34);
                ok.Location = new System.Drawing.Point(420, 18);
                ok.FlatStyle = FlatStyle.Flat;
                ok.BackColor = System.Drawing.Color.FromArgb(0, 119, 199);
                ok.ForeColor = System.Drawing.Color.White;
                ok.FlatAppearance.BorderSize = 0;
                ok.Click += delegate { dialog.Close(); };
                footer.Controls.Add(ok);

                dialog.AcceptButton = ok;
                dialog.CancelButton = ok;
                dialog.ShowDialog();
            }
        }

        private static void ExtractPayload(string targetDirectory)
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            Stream stream = assembly.GetManifestResourceStream(PayloadResourceName);
            if (stream == null)
            {
                throw new InvalidOperationException("El instalador no contiene los archivos del proyecto.");
            }

            string payloadPath = Path.Combine(targetDirectory, "payload.zip");
            using (stream)
            using (FileStream file = File.Create(payloadPath))
            {
                stream.CopyTo(file);
            }
            ZipFile.ExtractToDirectory(payloadPath, targetDirectory);
            TryDeleteFileWithRetries(payloadPath);
        }

        private static string ResolvePowerShellExecutable()
        {
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string pwshPath = Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe");
            if (File.Exists(pwshPath))
            {
                return pwshPath;
            }
            return "powershell.exe";
        }

        private static void TryDeleteDirectory(string targetDirectory)
        {
            if (!Directory.Exists(targetDirectory))
            {
                return;
            }

            File.SetAttributes(targetDirectory, FileAttributes.Directory);
            foreach (string path in Directory.GetFileSystemEntries(targetDirectory, "*", SearchOption.AllDirectories))
            {
                try { File.SetAttributes(path, FileAttributes.Normal); } catch { }
            }
            Directory.Delete(targetDirectory, true);
        }

        private static void CleanupTransientInstallerItems(string exeDirectory)
        {
            if (string.IsNullOrWhiteSpace(exeDirectory) || !Directory.Exists(exeDirectory))
            {
                return;
            }

            foreach (string directory in Directory.GetDirectories(exeDirectory, ".foroactivo_installer_runtime*"))
            {
                StopProcessesUsingDirectory(directory);
                TryDeleteDirectoryWithRetries(directory);
            }

            string metadataDirectory = Path.Combine(exeDirectory, "metadata");
            if (Directory.Exists(metadataDirectory))
            {
                TryDeleteDirectoryWithRetries(metadataDirectory);
            }

            string metadataFile = Path.Combine(exeDirectory, "metadata");
            if (File.Exists(metadataFile))
            {
                TryDeleteFileWithRetries(metadataFile);
            }
        }

        private static void TryDeleteDirectoryWithRetries(string targetDirectory)
        {
            for (int attempt = 0; attempt < 20; attempt++)
            {
                try
                {
                    TryDeleteDirectory(targetDirectory);
                    return;
                }
                catch
                {
                    if (attempt == 5 || attempt == 10 || attempt == 15)
                    {
                        StopProcessesUsingDirectory(targetDirectory);
                    }
                    System.Threading.Thread.Sleep(500);
                }
            }
        }

        private static void StopProcessesUsingDirectory(string directory)
        {
            if (string.IsNullOrWhiteSpace(directory))
            {
                return;
            }

            string normalizedDirectory = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    "SELECT ProcessId, CommandLine, Name FROM Win32_Process"))
                {
                    foreach (ManagementObject processInfo in searcher.Get())
                    {
                        try
                        {
                            int processId = Convert.ToInt32(processInfo["ProcessId"]);
                            if (processId == Process.GetCurrentProcess().Id)
                            {
                                continue;
                            }

                            string name = Convert.ToString(processInfo["Name"]) ?? string.Empty;
                            string commandLine = Convert.ToString(processInfo["CommandLine"]) ?? string.Empty;
                            if (commandLine.IndexOf(normalizedDirectory, StringComparison.OrdinalIgnoreCase) < 0)
                            {
                                continue;
                            }

                            string lowerName = name.ToLowerInvariant();
                            if (lowerName == "node.exe" ||
                                lowerName == "cmd.exe" ||
                                lowerName == "npm.cmd" ||
                                lowerName == "npx.cmd" ||
                                lowerName == "powershell.exe" ||
                                lowerName == "pwsh.exe")
                            {
                                Process.GetProcessById(processId).Kill();
                            }
                        }
                        catch { }
                    }
                }
            }
            catch { }
        }

        private static void TryDeleteFileWithRetries(string targetFile)
        {
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    if (File.Exists(targetFile))
                    {
                        File.SetAttributes(targetFile, FileAttributes.Normal);
                        File.Delete(targetFile);
                    }
                    return;
                }
                catch
                {
                    System.Threading.Thread.Sleep(350);
                }
            }
        }
    }
}
