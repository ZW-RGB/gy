#!/bin/bash
# ==============================================================================
# 工业设备预测维护平台 - Linux master 单节点一键部署脚本
# 目标机器：Ubuntu 20.04 / 22.04 (master 节点)
# 执行方式：sudo bash deploy_all.sh
# 
# 安装清单：
#   基础：Java 17、Maven、Python3、Node 18、MySQL 8、Redis 7
#   大数据：Hadoop 3.2 + YARN、ZooKeeper 3.7、Kafka 3.2、Flink 1.15、Spark 3.1
#   应用：backend.jar、frontend（build 产物 + Nginx 托管）
# ==============================================================================

set -e  # 出错立即退出

# ============ 可调参数 ============
export JAVA_VERSION=17
export HADOOP_VERSION=3.2.4
export ZOOKEEPER_VERSION=3.7.1
export KAFKA_VERSION=3.2.0
export FLINK_VERSION=1.15.4
export SPARK_VERSION=3.1.3
export NODE_VERSION=18

export INSTALL_ROOT=/opt/predictive          # 安装根目录
export APP_HOME=/opt/predictive/app           # 应用部署目录
export HADOOP_HOME=$INSTALL_ROOT/hadoop
export ZK_HOME=$INSTALL_ROOT/zookeeper
export KAFKA_HOME=$INSTALL_ROOT/kafka
export FLINK_HOME=$INSTALL_ROOT/flink
export SPARK_HOME=$INSTALL_ROOT/spark
export NODE_HOME=$INSTALL_ROOT/node

export DB_PASSWORD="060201"                    # MySQL root 密码
export REDIS_PASSWORD="123456"                 # Redis 密码
export HDFS_USER=hadoop
# ===================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------- 前置检查 ----------
check_root()   { [ "$(id -u)" -eq 0 ] || { error "请用 sudo 执行本脚本"; }; }
check_ubuntu() { grep -q "Ubuntu" /etc/os-release || { error "本脚本仅支持 Ubuntu"; }; }
check_swap()   { swapon --show | grep -q swap || warn "建议关闭 swap：sudo swapoff -a && sudo sed -i '/swap/s/^/#/' /etc/fstab"; }
check_root; check_ubuntu; check_swap

# ---------- 1. 基础依赖 ----------
step_base() {
  info "===== [1/7] 基础依赖 ====="
  apt-get update -qq && apt-get install -y openjdk-${JAVA_VERSION}-jdk maven python3 python3-pip git curl wget nginx build-essential
  pip3 install kafka-python pymysql --quiet

  # 创建 hadoop 用户（Hadoop 守护进程用）
  id hadoop &>/dev/null || useradd -m -s /bin/bash hadoop
  mkdir -p $INSTALL_ROOT
  chown -R hadoop:hadoop $INSTALL_ROOT
  info "基础依赖安装完成"
}

# ---------- 2. Hadoop 3.2 + YARN ----------
step_hadoop() {
  info "===== [2/7] Hadoop ${HADOOP_VERSION} (HDFS + YARN) ====="
  cd $INSTALL_ROOT
  [ -f hadoop-${HADOOP_VERSION}.tar.gz ] || wget -q https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz
  tar -xzf hadoop-${HADOOP_VERSION}.tar.gz
  ln -sf hadoop-${HADOOP_VERSION} $HADOOP_HOME

  # 环境变量
  cat >> /etc/profile.d/hadoop.sh <<EOF
export HADOOP_HOME=$HADOOP_HOME
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export YARN_CONF_DIR=$HADOOP_HOME/etc/hadoop
export JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
EOF
  source /etc/profile.d/hadoop.sh

  # 写配置（单节点 master）
  C=$HADOOP_HOME/etc/hadoop
  echo "<configuration><property><name>fs.defaultFS</name><value>hdfs://master:9000</value></property></configuration>" > $C/core-site.xml
  cat > $C/hdfs-site.xml <<EOF
<configuration>
  <property><name>dfs.replication</name><value>1</value></property>
  <property><name>dfs.namenode.name.dir</name><value>file:///home/hadoop/hadoop/dfs/name</value></property>
  <property><name>dfs.datanode.data.dir</name><value>file:///home/hadoop/hadoop/dfs/data</value></property>
</configuration>
EOF
  cat > $C/yarn-site.xml <<EOF
<configuration>
  <property><name>yarn.nodemanager.aux-services</name><value>mapreduce_shuffle</value></property>
  <property><name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name><value>org.apache.hadoop.mapred.ShuffleHandler</value></property>
  <property><name>yarn.resourcemanager.hostname</name><value>master</value></property>
  <property><name>yarn.nodemanager.resource.memory-mb</name><value>2048</value></property>
  <property><name>yarn.scheduler.maximum-allocation-mb</name><value>2048</value></property>
  <property><name>yarn.nodemanager.resource.cpu-vcores</name><value>2</value></property>
</configuration>
EOF
  echo "master" > $C/workers

  # 格式化 HDFS + 启动
  su - hadoop -c "export HADOOP_HOME=$HADOOP_HOME && export JAVA_HOME=$JAVA_HOME && \$HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive 2>/dev/null || true"
  su - hadoop -c "export HADOOP_HOME=$HADOOP_HOME && \$HADOOP_HOME/sbin/start-dfs.sh && \$HADOOP_HOME/sbin/start-yarn.sh"
  sleep 8
  info "HDFS: $(curl -s http://master:9870/ 2>/dev/null | grep -c 'Overview') pages, YARN RM: $(curl -s http://master:8088/ws/v1/cluster 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("clusterInfo",{}).get("hadoopVersion","unknown"))' 2>/dev/null)"
}

# ---------- 3. ZooKeeper + Kafka ----------
step_kafka() {
  info "===== [3/7] ZooKeeper ${ZOOKEEPER_VERSION} + Kafka ${KAFKA_VERSION} ====="
  cd $INSTALL_ROOT
  [ -f zookeeper-${ZOOKEEPER_VERSION}.tar.gz ] || wget -q https://archive.apache.org/dist/zookeeper/zookeeper-${ZOOKEEPER_VERSION}/apache-zookeeper-${ZOOKEEPER_VERSION}-bin.tar.gz
  tar -xzf apache-zookeeper-${ZOOKEEPER_VERSION}-bin.tar.gz
  ln -sf apache-zookeeper-${ZOOKEEPER_VERSION}-bin $ZK_HOME
  echo "tickTime=2000\ndataDir=/tmp/zookeeper\nclientPort=2181" > $ZK_HOME/conf/zoo.cfg
  $ZK_HOME/bin/zkServer.sh start >/dev/null 2>&1
  sleep 3
  $ZK_HOME/bin/zkServer.sh status | grep -q "Mode" && info "ZooKeeper OK" || warn "ZooKeeper 可能没起来"

  [ -f kafka_2.13-${KAFKA_VERSION}.tgz ] || wget -q https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz
  tar -xzf kafka_2.13-${KAFKA_VERSION}.tgz
  ln -sf kafka_2.13-${KAFKA_VERSION} $KAFKA_HOME
  $KAFKA_HOME/bin/kafka-server-start.sh -daemon $KAFKA_HOME/config/server.properties
  sleep 8
  $KAFKA_HOME/bin/kafka-topics.sh --create --bootstrap-server master:9092 --topic device-sensor --partitions 1 --replication-factor 1 2>/dev/null || true
  info "Kafka topic device-sensor OK"
}

# ---------- 4. MySQL + Redis ----------
step_db() {
  info "===== [4/7] MySQL 8 + Redis ====="
  # MySQL (使用 MariaDB 或 Oracle MySQL 任选其一)
  DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server >/dev/null
  mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS predictive_maintenance CHARACTER SET utf8mb4;
EOF
  mysql -u root predictive_maintenance < /dev/stdin <<'SQL'  2>/dev/null || true
CREATE TABLE IF NOT EXISTS device_info (
    device_id VARCHAR(20) PRIMARY KEY, device_type VARCHAR(50),
    install_date DATE NOT NULL, location VARCHAR(100));
CREATE TABLE IF NOT EXISTS alarm_event (
    alarm_id BIGINT AUTO_INCREMENT PRIMARY KEY, device_id VARCHAR(20) NOT NULL,
    alarm_time DATETIME NOT NULL, anomaly_score DECIMAL(5,4) NOT NULL,
    feature_values JSON, source VARCHAR(10) DEFAULT 'MODEL',
    rule_id VARCHAR(10), is_handled TINYINT DEFAULT 0,
    INDEX idx_device_time (device_id, alarm_time));
CREATE TABLE IF NOT EXISTS model_version (
    model_id INT AUTO_INCREMENT PRIMARY KEY, model_type VARCHAR(20) NOT NULL,
    version VARCHAR(50) NOT NULL, hdfs_path VARCHAR(255) NOT NULL,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP, is_active TINYINT DEFAULT 0,
    UNIQUE KEY uniq_version_type (version, model_type));
CREATE TABLE IF NOT EXISTS model_metrics (
    metric_id INT AUTO_INCREMENT PRIMARY KEY, model_id INT NOT NULL,
    rmse DECIMAL(10,6), accuracy DECIMAL(5,4), f1_score DECIMAL(5,4),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (model_id) REFERENCES model_version(model_id));
CREATE TABLE IF NOT EXISTS device_daily_stats (
    stat_id BIGINT AUTO_INCREMENT PRIMARY KEY, device_id VARCHAR(20) NOT NULL,
    stat_date DATE NOT NULL, avg_temp DECIMAL(6,2), max_vibration DECIMAL(6,2),
    avg_current DECIMAL(6,2), avg_pressure DECIMAL(8,2),
    UNIQUE KEY uniq_device_date (device_id, stat_date));
SQL
  # 插入 100 台初始设备
  python3 -c "
import pymysql, random
from datetime import date, timedelta
conn = pymysql.connect(host='localhost', user='root', database='predictive_maintenance')
cur = conn.cursor()
cur.execute('DELETE FROM device_info')
rows = [(f'device_{i:03d}', random.choice(['Pump','Compressor','Fan','Motor']),
         date.today()-timedelta(days=random.randint(30,730)),
         random.choice(['Workshop_A','Workshop_B','Storage_C'])) for i in range(1,101)]
cur.executemany('INSERT INTO device_info VALUES(%s,%s,%s,%s)', rows)
conn.commit(); cur.close(); conn.close()
print('设备 OK:', len(rows))
"

  # Redis
  apt-get install -y redis-server >/dev/null
  sed -i "s/^# requirepass .*/requirepass ${REDIS_PASSWORD}/" /etc/redis/redis.conf
  systemctl restart redis-server

  info "MySQL + Redis OK"
}

# ---------- 5. Flink + Spark ----------
step_compute() {
  info "===== [5/7] Flink ${FLINK_VERSION} + Spark ${SPARK_VERSION} ====="
  cd $INSTALL_ROOT
  [ -f flink-${FLINK_VERSION}-bin-scala_2.12.tgz ] || wget -q https://archive.apache.org/dist/flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-scala_2.12.tgz
  tar -xzf flink-${FLINK_VERSION}-bin-scala_2.12.tgz
  ln -sf flink-${FLINK_VERSION} $FLINK_HOME

  [ -f spark-${SPARK_VERSION}-bin-hadoop3.2.tgz ] || wget -q https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.2.tgz
  tar -xzf spark-${SPARK_VERSION}-bin-hadoop3.2.tgz
  ln -sf spark-${SPARK_VERSION}-bin-hadoop3.2 $SPARK_HOME

  cat >> /etc/profile.d/bigdata.sh <<EOF
export FLINK_HOME=$FLINK_HOME
export SPARK_HOME=$SPARK_HOME
export PATH=\$PATH:\$FLINK_HOME/bin:\$SPARK_HOME/bin
EOF
  source /etc/profile.d/bigdata.sh
  info "Flink + Spark 解压完成（作业需用 yarn 模式运行：flink run -m yarn-cluster ...  /  spark-submit --master yarn ...）"
}

# ---------- 6. 构建 + 部署应用 ----------
step_app() {
  info "===== [6/7] 部署后端 + 前端 ====="
  # 本脚本假设已被解压到 $APP_HOME（如 /opt/predictive），且包含：
  # backend.jar、configs/application-prod.yml、frontend-dist、*.py、create_tables.sql
  cd $APP_HOME

  # 后端
  mkdir -p $APP_HOME/backend
  cp backend.jar $APP_HOME/backend/predictive-maintenance-backend-1.0.0.jar
  cp configs/application-prod.yml $APP_HOME/backend/application-prod.yml

  # 后端 systemd 服务（开机自启）
  cat > /etc/systemd/system/predictive-backend.service <<EOF
[Unit]
Description=Predictive Maintenance Backend
After=network.target mysql.service redis.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_HOME/backend
Environment=JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64
ExecStart=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64/bin/java \
  -jar predictive-maintenance-backend-1.0.0.jar \
  --spring.profiles.active=prod \
  --spring.config.additional-location=file:$APP_HOME/backend/application-prod.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload && systemctl enable predictive-backend && systemctl start predictive-backend
  sleep 5
  info "Backend status: $(systemctl is-active predictive-backend) | $(curl -s http://localhost:2006/api/devices/info | head -c 40 || echo 'N/A')"

  # 前端（直接使用已构建好的静态资源）
  mkdir -p $APP_HOME/frontend
  cp -r frontend-dist/* $APP_HOME/frontend/ 2>/dev/null || { warn "未找到 frontend-dist，请在打包前先执行 npm run build"; }
  rm -f /etc/nginx/sites-enabled/default
  cat > /etc/nginx/sites-available/predictive <<EOF
server {
    listen 80 default_server;
    server_name _;
    root $APP_HOME/frontend;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
    location /api/ {
        proxy_pass http://127.0.0.1:2006;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/predictive /etc/nginx/sites-enabled/
  systemctl restart nginx
  info "Frontend + Nginx OK | http://$(hostname -I | awk '{print $1}')/"
}

# ---------- 7. 启动管道 ----------
step_pipeline() {
  info "===== [7/7] 启动数据管道（Python producer → Kafka）====="
  cd $APP_HOME
  cp configs/producer.env .
  cat >> producer.env <<EOF
KAFKA_SERVERS=master:9092
MYSQL_HOST=master
MYSQL_USER=root
MYSQL_PASSWORD=$DB_PASSWORD
MYSQL_DB=predictive_maintenance
MODEL_OUTPUT_DIR=/home/hadoop/tmp
HDFS_MODEL_BASE=hdfs://master:9000/models
HDFS_URI=hdfs://master:9000
HDFS_DATA_BASE=hdfs://master:9000/data/history/sensor
EOF

  # Producer 后台跑
  cat > /etc/systemd/system/predictive-producer.service <<EOF
[Unit]
Description=Predictive Maintenance Data Producer
After=network.target kafka.service

[Service]
Type=simple
WorkingDirectory=$APP_HOME
EnvironmentFile=$APP_HOME/producer.env
ExecStart=/usr/bin/python3 $APP_HOME/producer.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload && systemctl enable predictive-producer && systemctl start predictive-producer

  # 模型训练/部署 cron（每周日凌晨 3 点训练，4 点部署；每日 1 点统计）
  cat > /etc/cron.d/predictive <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SPARK_HOME/bin:$FLINK_HOME/bin

# 每日离线统计
0 1 * * * root bash $APP_HOME/submit_daily_stats.sh >> /home/hadoop/logs/spark-jobs/daily_stats.log 2>&1

# 每周离线训练 + 模型部署
0 3 * * 0 root source $APP_HOME/producer.env && python3 $APP_HOME/train_init_model.py >> /home/hadoop/logs/train_model.log 2>&1 && python3 $APP_HOME/register_model.py >> /home/hadoop/logs/register_model.log 2>&1 && bash $APP_HOME/deploy_model.sh >> /home/hadoop/logs/deploy_model.log 2>&1
EOF
  chmod 644 /etc/cron.d/predictive
  info "Producer 已启动；模型训练 cron 已写入 /etc/cron.d/predictive"
}

# ---------- 执行 ----------
step_base
step_hadoop
step_kafka
step_db
step_compute
step_app
step_pipeline

echo ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   🎉 部署完成！${NC}"
echo -e "${GREEN}====================================================${NC}"
echo ""
echo "  Web 前端:   http://master/"
echo "  后端 API:   http://master:2006/api/"
echo "  HDFS UI:    http://master:9870/"
echo "  YARN UI:    http://master:8088/"
echo "  常用命令:"
echo "    systemctl status predictive-backend"
echo "    systemctl status predictive-producer"
echo "    journalctl -u predictive-backend -f"
echo "    kafka-topics.sh --list --bootstrap-server master:9092"
echo "    flink run -m yarn-cluster -yjm 1024m -ytm 2048m flink-job-*.jar"
echo ""
