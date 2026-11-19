# host-shell-mcp

Windows 네이티브 호스트 세션(`WinSta0\Default`)에서 PowerShell/CMD 실행과 정식 Windows UAC 권한 상승(`runas`)을 제공하는 초경량 무의존성 stdio MCP(Model Context Protocol) 서버입니다.

> A lightweight, zero-dependency Windows stdio MCP server that runs PowerShell/CMD in the interactive Windows desktop session (`WinSta0\Default`) and triggers standard Windows UAC elevation prompts with full output capture.

---

## 왜 필요한가? (Why `host-shell-mcp`?)

Windows 환경의 Antigravity 내장 터미널(`run_command`)은 **`Turbo` 모드 + `Terminal Sandbox OFF` 상태에서도** 숨김 데스크톱(`exebox-*`) 안에서 실행됩니다. 이 때문에 일반 CLI 작업은 되지만 다음과 같은 일상적인 Windows 로컬 작업에서 막히거나 무한 대기(Hang)가 발생합니다.

| 작업 유형 | 내장 `run_command` (Windows) | `host-shell-mcp` 사용 시 |
| --- | --- | --- |
| GUI 앱 실행 (`Start-Process` 등) | 숨김 데스크톱에서 실행되어 화면에 안 뜨거나 실패 | 실제 사용자 데스크톱(`WinSta0\Default`)에 정상 표시 |
| 창·프로세스 제어 / GUI 자동화 | 데스크톱 세션이 달라 상호작용 불가 | 호스트 세션에서 바로 상호작용 가능 |
| 관리자 권한 작업 (`sudo` / `RunAs`) | 숨김 데스크톱에서 UAC 창이 안 보여 무한 대기(Hang) | 사용자 화면에 정식 Windows UAC 승인창 표시 후 결과(stdout/stderr/ExitCode) 반환 |

### 핵심 장점
- **무의존성 1초 로컬 빌드**: Git, Node.js, Python, .NET SDK가 전혀 필요 없습니다. Windows 10/11 기본 내장 `.NET Framework csc.exe`로 즉시 컴파일합니다.
- **완전 원터치 세팅**: PowerShell 한 줄로 빌드 → MCP 핸드셰이크 검증 → `mcp_config.json` 안전 병합(백업 포함) → `GEMINI.md` 전역 규칙 등록까지 한 번에 끝납니다.
- **정식 UAC 기반 설계**: UAC를 몰래 우회하지 않고 매번 표준 Windows UAC 승인 창(`Verb = "runas"`)을 띄워 사용자 확인을 거칩니다.

---

## 원터치 설치 (권장 — Git·SDK 불필요)

Windows PowerShell을 열고 아래 **한 줄**만 붙여넣고 실행한 뒤, Antigravity를 재시작하면 끝납니다.

```powershell
irm https://raw.githubusercontent.com/servaltullius/host-shell-mcp/main/install.ps1 | iex
```

설치 스크립트가 자동으로 수행하는 작업:
1. Windows 기본 내장 `.NET Framework csc.exe`로 `Program.cs`를 로컬 컴파일(실패 시 최신 Release 바이너리 자동 폴백) → `%USERPROFILE%\.gemini\antigravity\bin\host-shell-mcp\host-shell-mcp.exe`
2. MCP `initialize` 핸드셰이크 동작 자가 검증
3. `%USERPROFILE%\.gemini\config\mcp_config.json` 자동 백업 후 `host-shell` 항목 안전 병합 (기존 MCP 설정 유지, 레거시 경로가 존재하면 함께 반영)
4. `%USERPROFILE%\.gemini\GEMINI.md`에 `host-shell` 우선 사용 규칙 추가 (Lazy MCP 특성상 규칙이 있어야 Antigravity가 GUI/UAC 작업 시 자동으로 `host-shell`을 선택함; 기존 규칙이 있으면 건너뜀)

### 제거 (원터치)

```powershell
irm https://raw.githubusercontent.com/servaltullius/host-shell-mcp/main/uninstall.ps1 | iex
```

---

## 수동 / 오프라인 설치

리포지터리를 받은 뒤 `install.bat`을 더블클릭하면 동일하게 설치됩니다.

```bat
git clone https://github.com/servaltullius/host-shell-mcp.git
cd host-shell-mcp
install.bat
```

바이너리만 직접 빌드하려면 `build.bat`을 실행하거나, [Releases](https://github.com/servaltullius/host-shell-mcp/releases/latest)에서 `host-shell-mcp.exe`를 내려받아 `%USERPROFILE%\.gemini\config\mcp_config.json`에 등록하세요.

```json
{
  "mcpServers": {
    "host-shell": {
      "command": "C:\\path\\to\\host-shell-mcp\\host-shell-mcp.exe",
      "args": []
    }
  }
}
```

---

## 제공 도구 (Tools)

| 도구명 | 설명 |
| --- | --- |
| `execute_command` | PowerShell 또는 CMD 명령을 호스트 데스크톱 세션에서 실행하고 stdout/stderr 및 종료 코드를 반환합니다. (창이 유지되는 GUI 앱 실행은 `Start-Process` 사용 권장) |
| `execute_elevated` | Windows 정식 UAC 승인 창(`Verb = "runas"`)을 띄워 사용자 승인 후 관리자 권한 PowerShell 명령을 실행하고 결과를 반환합니다. |
| `get_session_info` | 현재 프로세스의 `WindowStation`, `ThreadDesktop`, 관리자 여부(`IsAdmin`), `IsProcessInJob` 상태를 진단 출력합니다. |

---

## 보안 주의사항

- 이 MCP 서버는 연결된 클라이언트에 로컬 PowerShell/CMD 실행 및 UAC 권한 상승 요청 인터페이스를 노출합니다.
- **신뢰할 수 있는 본인 전용 PC 환경에서만** 사용자가 직접 설치·등록해 사용하세요.
- `execute_elevated`는 Windows UAC를 우회하지 않으며, 실행 시 매번 실제 사용자 데스크톱에 표준 UAC 승인 창을 띄웁니다.
