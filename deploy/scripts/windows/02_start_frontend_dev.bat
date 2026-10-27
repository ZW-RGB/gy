@echo off
REM ======================================================================
REM Windows 本地前端开发（Vite dev server + 代理后端 localhost:2006）
REM 前提：Node.js 18+，且后端已跑在 localhost:2006
REM 启动后：http://localhost:2005
REM ======================================================================
chcp 65001 >nul
cd /d "%~dp0..\..\frontend"

where node >nul 2>&1 || (echo [X] 未检测到 Node.js & pause & exit /b 1)

if not exist node_modules (
  echo [*] 第一次运行，npm install...
  call npm install
  if errorlevel 1 (echo [X] npm install 失败 & pause & exit /b 1)
)

echo.
echo ============================================
echo   🎨 前端开发服务器
echo   http://localhost:2005
echo   Ctrl+C 退出
echo ============================================
echo.
call npm run dev
pause
