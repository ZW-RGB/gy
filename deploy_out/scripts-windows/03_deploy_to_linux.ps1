# ======================================================================
# PowerShell：Windows 打包 → SCP 上传 → SSH 在 Linux master 上重启
# 用法：powershell -File 03_deploy_to_linux.ps1
# ======================================================================

# ==== 可调参数 ====
$LINUX_HOST   = "master"           # 改这里！Linux master 的 IP 或 hostname
$LINUX_USER   = "root"
$LINUX_APP    = "/opt/predictive/app"
$PROJECT_ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host "===== 打包上传到 $LINUX_HOST =====" -ForegroundColor Cyan

# 1) 前端 build
Write-Host "[1/4] 前端 npm run build ..." -ForegroundColor Green
Set-Location "$PROJECT_ROOT\frontend"
npm run build 2>&1 | Select-Object -Last 5
if ($LASTEXITCODE -ne 0) { exit 1 }

# 2) 后端 package
Write-Host "[2/4] 后端 mvn package ..." -ForegroundColor Green
Set-Location "$PROJECT_ROOT\backend"
mvn -q clean package -DskipTests 2>&1 | Select-Object -Last 5
if ($LASTEXITCODE -ne 0) { exit 1 }

# 3) 上传（需要 Linux master 已开 sshd；如果没有 ssh，建议用 WinSCP 手动拖）
Write-Host "[3/4] SCP 上传 ..." -ForegroundColor Green
$scp = "scp -o StrictHostKeyChecking=no"
Invoke-Expression "$scp $PROJECT_ROOT\backend\target\predictive-maintenance-backend-1.0.0.jar      ${LINUX_USER}@${LINUX_HOST}:${LINUX_APP}/backend/"
Invoke-Expression "$scp -r $PROJECT_ROOT\frontend\dist\*                                           ${LINUX_USER}@${LINUX_HOST}:${LINUX_APP}/frontend/dist/"
Invoke-Expression "$scp $PROJECT_ROOT\deploy\configs\application-prod.yml                            ${LINUX_USER}@${LINUX_HOST}:${LINUX_APP}/backend/"

# 4) SSH 重启后端 + Nginx reload
Write-Host "[4/4] SSH 重启服务 ..." -ForegroundColor Green
$ssh = "ssh -o StrictHostKeyChecking=no ${LINUX_USER}@${LINUX_HOST}"
Invoke-Expression "$ssh systemctl restart predictive-backend"
Invoke-Expression "$ssh systemctl restart nginx"

Write-Host "`n✅ 部署完成！http://$LINUX_HOST/" -ForegroundColor Green
