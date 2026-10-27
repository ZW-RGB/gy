@echo off
REM ======================================================================
REM 工业设备预测维护平台 — Windows 本地后端启动（单机版，无 Hadoop/Flink）
REM 前提：已装好 JDK 17+, Maven 3.9+, MySQL 8+, Redis 7+
REM 双击即可启动 Spring Boot（端口 2006, context-path /api）
REM ======================================================================

chcp 65001 >nul
setlocal

REM ---- 可调参数 ----
set JAVA_HOME=C:\Program Files\Java\jdk-17
set PATH=%JAVA_HOME%\bin;%PATH%

set APP_HOME=%~dp0..\..
set BACKEND_DIR=%APP_HOME%\backend

REM ---- 1. MySQL + Redis 存活检查 ----
where mysql >nul 2>&1
if errorlevel 1 (
  echo [X] 未检测到 mysql，请先装 MySQL 8+ 并加入 PATH
  pause & exit /b 1
)
where redis-cli >nul 2>&1
if errorlevel 1 (
  echo [X] 未检测到 redis-cli，请先装 Redis 并加入 PATH
  pause & exit /b 1
)

REM ---- 2. 初始化数据库（首次运行）----
mysql -u root -p"" -e "SELECT 1;" >nul 2>&1
if errorlevel 1 (
  echo [!] 无法连接 MySQL root@localhost，请检查密码配置
  pause & exit /b 1
)
echo CREATE DATABASE IF NOT EXISTS predictive_maintenance CHARACTER SET utf8mb4; | mysql -u root
if not exist %TEMP%\tables_init.ok (
  mysql -u root predictive_maintenance < "%APP_HOME%\create_tables.sql" >nul 2>&1
  REM 插 100 台设备（Python 已装好的话）
  where python >nul 2>&1 && python "%APP_HOME%\insert_devices.py" >nul 2>&1
  type nul > %TEMP%\tables_init.ok
  echo [OK] 数据库初始化完成
)

REM ---- 3. 确保 Redis 跑着 ----
redis-cli ping >nul 2>&1
if errorlevel 1 (
  echo [*] 启动 Redis...
  start "" redis-server
  timeout /t 2 >nul
)

REM ---- 4. Spring Boot 启动 ----
cd /d %BACKEND_DIR%
if not exist target\predictive-maintenance-backend-1.0.0.jar (
  echo [*] 第一次运行，正在打包后端...
  call mvn -q clean package -DskipTests
  if errorlevel 1 ( echo [X] Maven 打包失败 & pause & exit /b 1)
)

echo.
echo ============================================
echo   🚀 后端启动中...  http://localhost:2006/api/
echo   Ctrl+C 退出
echo ============================================
echo.
REM 用 dev-local profile（MySQL/Redis 都是 localhost，无密码，SQL 日志开启）
java -jar target\predictive-maintenance-backend-1.0.0.jar --spring.profiles.active=dev-local

endlocal
pause
