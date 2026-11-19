# host-shell-mcp

Windows 네이티브 호스트 세션(`WinSta0\Default`)에서 PowerShell/CMD 실행과 정식 UAC 권한 상승(`runas`)을 제공하는 초경량 무의존성 stdio MCP(Model Context Protocol) 서버입니다.

> A lightweight, zero-dependency Windows stdio MCP server for running PowerShell/CMD commands in the native Windows desktop session (`WinSta0\Default`) and triggering standard Windows UAC elevation prompts.

## 제공 도구 (Tools)

| 도구명 | 설명 |
| --- | --- |
| `execute_command` | PowerShell 또는 CMD 명령을 호스트 데스크톱 세션에서 실행하고 stdout/stderr 및 종료 코드를 반환합니다. |
| `execute_elevated` | Windows 정식 UAC 승인 창(`Verb = "runas"`)을 띄워 사용자 승인 후 관리자 권한 PowerShell 명령을 실행하고 결과를 반환합니다. |
| `get_session_info` | 현재 프로세스의 `WindowStation`, `ThreadDesktop`, 관리자 여부(`IsAdmin`), `IsProcessInJob` 상태를 진단 출력합니다. |

## 빌드 방법 (Windows 10/11 기본 내장 컴파일러, 별도 SDK 불필요)

Windows에 기본 포함된 `.NET Framework 4.x` C# 컴파일러(`csc.exe`)만 사용하므로 .NET SDK나 Visual Studio 없이 1초 만에 빌드됩니다.

```bat
git clone https://github.com/servaltullius/host-shell-mcp.git
cd host-shell-mcp
build.bat
```

성공하면 같은 폴더에 `host-shell-mcp.exe`가 생성됩니다.  
(또는 GitHub **Releases**에서 미리 빌드된 `host-shell-mcp.exe`를 내려받을 수 있습니다.)

## MCP 등록 예시 (Antigravity)

`%USERPROFILE%\.gemini\config\mcp_config.json`의 `mcpServers`에 아래 항목을 추가한 뒤 앱을 재시작하세요.

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

## 보안 주의사항

- 이 MCP 서버는 연결된 클라이언트에 로컬 PowerShell/CMD 실행 및 UAC 권한 상승 요청 인터페이스를 노출합니다.
- **신뢰할 수 있는 본인 전용 PC 환경에서만** 사용자가 직접 `mcp_config.json`에 등록해 사용하세요.
- `execute_elevated`는 Windows UAC를 우회하지 않으며, 실행 시 매번 실제 사용자 데스크톱에 표준 UAC 승인 창을 띄웁니다.
