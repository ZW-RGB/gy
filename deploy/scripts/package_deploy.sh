#!/bin/bash
# 生成跨平台部署包：deployables.zip
# 包含：配置文件 + 部署脚本 + 数据库 SQL +（可选）构建产物
set -e
ROOT=$(cd $(dirname $0)/../.. && pwd)
OUT=$ROOT/deploy_out
rm -rf $OUT && mkdir -p $OUT
cd $ROOT

echo "[1/5] 拷贝配置..."
cp -r deploy/configs $OUT/configs
echo "[2/5] 拷贝 Linux 脚本..."
cp -r deploy/scripts/linux $OUT/scripts-linux
echo "[3/5] 拷贝 Windows 脚本..."
cp -r deploy/scripts/windows $OUT/scripts-windows
echo "[4/5] 拷贝数据库、Python 训练/生产脚本与 README..."
cp create_tables.sql $OUT/
cp README.md $OUT/
cp producer.py train_init_model.py register_model.py deploy_model.sh create_tables.sql $OUT/ 2>/dev/null || true
cp spark-offline-job/submit_daily_stats.sh spark-offline-job/submit_model_training.sh $OUT/ 2>/dev/null || true

# 后端 jar（如果已经打包好）
if [ -f backend/target/predictive-maintenance-backend-1.0.0.jar ]; then
  cp backend/target/predictive-maintenance-backend-1.0.0.jar $OUT/backend.jar
  echo "  已附带 backend.jar"
fi
# 前端 dist
if [ -d frontend/dist ]; then
  cp -r frontend/dist $OUT/frontend-dist
  echo "  已附带 frontend-dist"
fi

echo "[5/5] 生成 deployables.zip ..."
cd $OUT && zip -q -r ../deployables.zip .
echo ""
echo "✅ 交付物：$ROOT/deployables.zip"
echo "   直接传到 Linux master 解压即可 sudo bash scripts-linux/deploy_all.sh"
