using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace HostShellMcp
{
    class Program
    {
        [DllImport("user32.dll")] static extern IntPtr GetProcessWindowStation();
        [DllImport("user32.dll")] static extern IntPtr GetThreadDesktop(uint dwThreadId);
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool GetUserObjectInformation(IntPtr hObj, int nIndex, StringBuilder pvInfo, int nLength, out int lpnLengthNeeded);
        [DllImport("kernel32.dll")] static extern bool IsProcessInJob(IntPtr ProcessHandle, IntPtr JobHandle, out bool Result);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();

        static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 100 };
        static readonly object WriteLock = new object();
        static Stream StdoutStream;

        static int Main(string[] args)
        {
            UTF8Encoding utf8NoBom = new UTF8Encoding(false);
            Console.InputEncoding = utf8NoBom;
            Console.OutputEncoding = utf8NoBom;
            StdoutStream = Console.OpenStandardOutput();

            using (Stream stdin = Console.OpenStandardInput())
            using (StreamReader reader = new StreamReader(stdin, utf8NoBom, false, 65536))
            {
                string line;
                while ((line = reader.ReadLine()) != null)
                {
                    line = line.TrimStart('\uFEFF').Trim();
                    if (string.IsNullOrEmpty(line)) continue;
                    HandleMessage(line);
                }
            }
            return 0;
        }

        static void SendJson(object payload)
        {
            string serialized = Json.Serialize(payload);
            UTF8Encoding utf8NoBom = new UTF8Encoding(false);
            byte[] bytes = utf8NoBom.GetBytes(serialized + "\n");
            lock (WriteLock)
            {
                StdoutStream.Write(bytes, 0, bytes.Length);
                StdoutStream.Flush();
            }
        }

        static void SendResult(object id, object result)
        {
            SendJson(new Dictionary<string, object>
            {
                { "jsonrpc", "2.0" },
                { "id", id },
                { "result", result }
            });
        }

        static void SendError(object id, int code, string message)
        {
            SendJson(new Dictionary<string, object>
            {
                { "jsonrpc", "2.0" },
                { "id", id },
                { "error", new Dictionary<string, object> { { "code", code }, { "message", message } } }
            });
        }

        static void HandleMessage(string rawJson)
        {
            Dictionary<string, object> req;
            try { req = Json.Deserialize<Dictionary<string, object>>(rawJson); }
            catch (Exception ex) { SendError(null, -32700, "Parse error: " + ex.Message); return; }
            if (req == null || !req.ContainsKey("id")) return;

            object id = req["id"];
            string method = req.ContainsKey("method") && req["method"] != null ? req["method"].ToString() : "";
            Dictionary<string, object> @params = req.ContainsKey("params") && req["params"] is Dictionary<string, object>
                ? (Dictionary<string, object>)req["params"] : null;

            try
            {
                switch (method)
                {
                    case "initialize": HandleInitialize(id, @params); break;
                    case "ping": SendResult(id, new Dictionary<string, object>()); break;
                    case "tools/list": HandleToolsList(id); break;
                    case "tools/call": HandleToolsCall(id, @params); break;
                    case "resources/list": SendResult(id, new Dictionary<string, object> { { "resources", new object[0] } }); break;
                    case "prompts/list": SendResult(id, new Dictionary<string, object> { { "prompts", new object[0] } }); break;
                    default: SendError(id, -32601, "Method not found: " + method); break;
                }
            }
            catch (Exception ex) { SendError(id, -32603, "Internal error: " + ex.Message); }
        }

        static void HandleInitialize(object id, Dictionary<string, object> @params)
        {
            string clientProto = "2024-11-05";
            if (@params != null && @params.ContainsKey("protocolVersion") && @params["protocolVersion"] != null)
            {
                string requested = @params["protocolVersion"].ToString();
                if (requested == "2025-03-26" || requested == "2024-11-05") clientProto = requested;
            }
            SendResult(id, new Dictionary<string, object>
            {
                { "protocolVersion", clientProto },
                { "capabilities", new Dictionary<string, object> { { "tools", new Dictionary<string, object>() } } },
                { "serverInfo", new Dictionary<string, object> { { "name", "host-shell" }, { "version", "1.0.0" } } }
            });
        }

        static void HandleToolsList(object id)
        {
            var tools = new object[]
            {
                new Dictionary<string, object>
                {
                    { "name", "execute_command" },
                    { "description", "Execute a PowerShell or CMD command directly in the native Windows host session (WinSta0\\Default) without exebox hidden-desktop isolation." },
                    { "inputSchema", new Dictionary<string, object>
                        {
                            { "type", "object" },
                            { "properties", new Dictionary<string, object>
                                {
                                    { "command", new Dictionary<string, object> { { "type", "string" }, { "description", "Command or script block to execute." } } },
                                    { "shell", new Dictionary<string, object> { { "type", "string" }, { "enum", new[] { "powershell", "cmd" } }, { "description", "Shell to use (default: powershell)." } } },
                                    { "cwd", new Dictionary<string, object> { { "type", "string" }, { "description", "Optional working directory path." } } },
                                    { "timeout_ms", new Dictionary<string, object> { { "type", "integer" }, { "description", "Timeout in milliseconds (default: 60000)." } } }
                                }
                            },
                            { "required", new[] { "command" } }
                        }
                    }
                },
                new Dictionary<string, object>
                {
                    { "name", "execute_elevated" },
                    { "description", "Execute a PowerShell command with Administrator privileges by triggering a native Windows UAC approval prompt on the user's desktop, capturing full stdout/stderr and exit code." },
                    { "inputSchema", new Dictionary<string, object>
                        {
                            { "type", "object" },
                            { "properties", new Dictionary<string, object>
                                {
                                    { "command", new Dictionary<string, object> { { "type", "string" }, { "description", "PowerShell command to execute as Administrator." } } },
                                    { "cwd", new Dictionary<string, object> { { "type", "string" }, { "description", "Optional working directory path." } } },
                                    { "timeout_ms", new Dictionary<string, object> { { "type", "integer" }, { "description", "Timeout in milliseconds including UAC prompt wait (default: 120000)." } } }
                                }
                            },
                            { "required", new[] { "command" } }
                        }
                    }
                },
                new Dictionary<string, object>
                {
                    { "name", "get_session_info" },
                    { "description", "Return diagnostic details of the current Windows session (WindowStation, ThreadDesktop name, Administrator status, and JobObject state)." },
                    { "inputSchema", new Dictionary<string, object> { { "type", "object" }, { "properties", new Dictionary<string, object>() } } }
                }
            };
            SendResult(id, new Dictionary<string, object> { { "tools", tools } });
        }

        static void HandleToolsCall(object id, Dictionary<string, object> @params)
        {
            if (@params == null || !@params.ContainsKey("name") || @params["name"] == null)
            {
                SendError(id, -32602, "Missing tool name"); return;
            }
            string toolName = @params["name"].ToString();
            Dictionary<string, object> args = @params.ContainsKey("arguments") && @params["arguments"] is Dictionary<string, object>
                ? (Dictionary<string, object>)@params["arguments"] : new Dictionary<string, object>();

            switch (toolName)
            {
                case "get_session_info": SendToolText(id, GetSessionInfoText(), false); break;
                case "execute_command": RunStandardCommand(id, args); break;
                case "execute_elevated": RunElevatedCommand(id, args); break;
                default: SendError(id, -32602, "Unknown tool: " + toolName); break;
            }
        }

        static void SendToolText(object id, string text, bool isError)
        {
            SendResult(id, new Dictionary<string, object>
            {
                { "content", new object[] { new Dictionary<string, object> { { "type", "text" }, { "text", text ?? "" } } } },
                { "isError", isError }
            });
        }

        static string GetSessionInfoText()
        {
            int needed;
            StringBuilder sbWinsta = new StringBuilder(256);
            GetUserObjectInformation(GetProcessWindowStation(), 2, sbWinsta, 256, out needed);
            StringBuilder sbDesk = new StringBuilder(256);
            GetUserObjectInformation(GetThreadDesktop(GetCurrentThreadId()), 2, sbDesk, 256, out needed);
            bool inJob = false;
            IsProcessInJob(GetCurrentProcess(), IntPtr.Zero, out inJob);
            bool isAdmin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);

            StringBuilder sb = new StringBuilder();
            sb.AppendLine("ProcessId     : " + Process.GetCurrentProcess().Id);
            sb.AppendLine("User          : " + WindowsIdentity.GetCurrent().Name);
            sb.AppendLine("IsAdmin       : " + isAdmin);
            sb.AppendLine("WindowStation : " + sbWinsta);
            sb.AppendLine("ThreadDesktop : " + sbDesk);
            sb.AppendLine("IsProcessInJob: " + inJob);
            return sb.ToString();
        }

        static void RunStandardCommand(object id, Dictionary<string, object> args)
        {
            string cmd = args.ContainsKey("command") && args["command"] != null ? args["command"].ToString() : "";
            if (string.IsNullOrWhiteSpace(cmd)) { SendToolText(id, "Error: 'command' argument cannot be empty.", true); return; }

            string shell = args.ContainsKey("shell") && args["shell"] != null ? args["shell"].ToString().ToLowerInvariant() : "powershell";
            string cwd = args.ContainsKey("cwd") && args["cwd"] != null ? args["cwd"].ToString() : "";
            int timeoutMs = 60000;
            if (args.ContainsKey("timeout_ms") && args["timeout_ms"] != null)
            {
                int parsed;
                if (int.TryParse(args["timeout_ms"].ToString(), out parsed) && parsed >= 1000 && parsed <= 600000) timeoutMs = parsed;
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            if (shell == "cmd")
            {
                psi.FileName = "cmd.exe";
                psi.Arguments = "/d /s /c \"" + cmd + "\"";
            }
            else
            {
                string wrapped = "$ProgressPreference = 'SilentlyContinue'; [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); $OutputEncoding = [Console]::OutputEncoding; " + cmd;
                string b64 = Convert.ToBase64String(Encoding.Unicode.GetBytes(wrapped));
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoLogo -NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand " + b64;
            }
            if (!string.IsNullOrWhiteSpace(cwd) && Directory.Exists(cwd)) psi.WorkingDirectory = cwd;

            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = new UTF8Encoding(false);
            psi.StandardErrorEncoding = new UTF8Encoding(false);

            try
            {
                using (Process proc = new Process { StartInfo = psi })
                {
                    StringBuilder stdout = new StringBuilder();
                    StringBuilder stderr = new StringBuilder();
                    proc.Start();
                    Task tOut = Task.Run(() => { stdout.Append(proc.StandardOutput.ReadToEnd()); });
                    Task tErr = Task.Run(() => { stderr.Append(proc.StandardError.ReadToEnd()); });

                    if (!proc.WaitForExit(timeoutMs))
                    {
                        KillProcessTree(proc.Id);
                        Task.WaitAll(new[] { tOut, tErr }, 2000);
                        SendToolText(id, string.Format("Command timed out after {0} ms.\nPartial stdout:\n{1}\nPartial stderr:\n{2}", timeoutMs, stdout, stderr), true);
                        return;
                    }
                    Task.WaitAll(new[] { tOut, tErr }, 5000);
                    int code = proc.ExitCode;
                    StringBuilder combined = new StringBuilder();
                    combined.AppendLine("ExitCode: " + code);
                    if (stdout.Length > 0) { combined.AppendLine("--- STDOUT ---"); combined.AppendLine(stdout.ToString().TrimEnd()); }
                    if (stderr.Length > 0) { combined.AppendLine("--- STDERR ---"); combined.AppendLine(stderr.ToString().TrimEnd()); }
                    SendToolText(id, combined.ToString().TrimEnd(), code != 0);
                }
            }
            catch (Exception ex) { SendToolText(id, "Failed to start command: " + ex.Message, true); }
        }

        static void RunElevatedCommand(object id, Dictionary<string, object> args)
        {
            string cmd = args.ContainsKey("command") && args["command"] != null ? args["command"].ToString() : "";
            if (string.IsNullOrWhiteSpace(cmd)) { SendToolText(id, "Error: 'command' argument cannot be empty.", true); return; }

            string cwd = args.ContainsKey("cwd") && args["cwd"] != null ? args["cwd"].ToString() : "";
            int timeoutMs = 120000;
            if (args.ContainsKey("timeout_ms") && args["timeout_ms"] != null)
            {
                int parsed;
                if (int.TryParse(args["timeout_ms"].ToString(), out parsed) && parsed >= 1000 && parsed <= 600000) timeoutMs = parsed;
            }

            string token = Guid.NewGuid().ToString("N");
            string tempDir = Path.GetTempPath();
            string scriptPath = Path.Combine(tempDir, "mcp_elev_" + token + ".ps1");
            string outPath = Path.Combine(tempDir, "mcp_elev_" + token + ".out");
            string exitPath = Path.Combine(tempDir, "mcp_elev_" + token + ".code");

            StringBuilder psScript = new StringBuilder();
            psScript.AppendLine("$ErrorActionPreference = 'Continue'");
            psScript.AppendLine("$global:LASTEXITCODE = 0");
            psScript.AppendLine("$utf8 = New-Object System.Text.UTF8Encoding($false)");
            if (!string.IsNullOrWhiteSpace(cwd) && Directory.Exists(cwd))
                psScript.AppendLine("Set-Location -LiteralPath '" + cwd.Replace("'", "''") + "'");
            psScript.AppendLine("$exitCode = 0");
            psScript.AppendLine("try {");
            psScript.AppendLine("    $output = & {");
            psScript.AppendLine(cmd);
            psScript.AppendLine("    } *>&1 | Out-String");
            psScript.AppendLine("    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { $exitCode = $LASTEXITCODE }");
            psScript.AppendLine("    [System.IO.File]::WriteAllText('" + outPath.Replace("'", "''") + "', $output, $utf8)");
            psScript.AppendLine("} catch {");
            psScript.AppendLine("    $exitCode = 1");
            psScript.AppendLine("    [System.IO.File]::WriteAllText('" + outPath.Replace("'", "''") + "', $_.ToString(), $utf8)");
            psScript.AppendLine("}");
            psScript.AppendLine("[System.IO.File]::WriteAllText('" + exitPath.Replace("'", "''") + "', $exitCode.ToString(), $utf8)");

            File.WriteAllText(scriptPath, psScript.ToString(), new UTF8Encoding(true));

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"",
                    UseShellExecute = true,
                    Verb = "runas",
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                using (Process proc = Process.Start(psi))
                {
                    if (proc == null) { SendToolText(id, "Failed to start elevated process.", true); return; }
                    if (!proc.WaitForExit(timeoutMs)) { SendToolText(id, "Elevated command timed out after " + timeoutMs + " ms.", true); return; }
                }

                string outputText = File.Exists(outPath) ? File.ReadAllText(outPath, new UTF8Encoding(false)) : "";
                int code = 0;
                if (File.Exists(exitPath)) int.TryParse(File.ReadAllText(exitPath).Trim(), out code);

                StringBuilder res = new StringBuilder();
                res.AppendLine("Elevated ExitCode: " + code);
                if (!string.IsNullOrWhiteSpace(outputText)) { res.AppendLine("--- OUTPUT ---"); res.Append(outputText.TrimEnd()); }
                SendToolText(id, res.ToString().TrimEnd(), code != 0);
            }
            catch (System.ComponentModel.Win32Exception wex)
            {
                if (wex.NativeErrorCode == 1223) SendToolText(id, "UAC prompt was declined/canceled by user (Error 1223).", true);
                else SendToolText(id, string.Format("Win32 error ({0}): {1}", wex.NativeErrorCode, wex.Message), true);
            }
            catch (Exception ex) { SendToolText(id, "Elevated execution failed: " + ex.Message, true); }
            finally { TryDelete(scriptPath); TryDelete(outPath); TryDelete(exitPath); }
        }

        static void KillProcessTree(int pid)
        {
            try
            {
                using (Process kp = Process.Start(new ProcessStartInfo { FileName = "taskkill.exe", Arguments = "/F /T /PID " + pid, CreateNoWindow = true, UseShellExecute = false }))
                {
                    if (kp != null) kp.WaitForExit(3000);
                }
            }
            catch { }
        }

        static void TryDelete(string path) { try { if (File.Exists(path)) File.Delete(path); } catch { } }
    }
}
