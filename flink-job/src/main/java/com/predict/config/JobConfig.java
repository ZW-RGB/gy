package com.predict.config;

import java.io.IOException;
import java.io.InputStream;
import java.io.Serializable;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Properties;

/**
 * 统一 Flink 作业配置加载器。
 * 优先级：系统属性 -Dconfig.file > 环境变量 PREDICTIVE_CONFIG > classpath:flink-job.properties
 *
 * 使用方式：
 *   # 集群部署（加载外部文件）
 *   flink run -Dconfig.file=/opt/flink/config/cluster.properties ...
 *
 *   # 本地运行（默认 classpath）
 *   java -jar flink-job.jar
 */
public class JobConfig implements Serializable {

    private static volatile Properties props = load();

    private static Properties load() {
        Properties p = new Properties();

        // 1) 优先读取 -Dconfig.file=/path/to/file.properties
        String sysPath = System.getProperty("config.file");
        if (sysPath != null && !sysPath.isEmpty()) {
            try (InputStream in = Files.newInputStream(Paths.get(sysPath))) {
                p.load(in);
                return p;
            } catch (IOException e) {
                System.err.println("[JobConfig] 读取 -Dconfig.file 失败：" + sysPath + "，回退默认");
            }
        }

        // 2) 环境变量
        String envPath = System.getenv("PREDICTIVE_CONFIG");
        if (envPath != null && !envPath.isEmpty()) {
            try (InputStream in = Files.newInputStream(Paths.get(envPath))) {
                p.load(in);
                return p;
            } catch (IOException e) {
                System.err.println("[JobConfig] 读取 PREDICTIVE_CONFIG 失败：" + envPath + "，回退默认");
            }
        }

        // 3) classpath 默认（打包进去的 flink-job.properties）
        InputStream in = JobConfig.class.getClassLoader().getResourceAsStream("flink-job.properties");
        if (in != null) {
            try {
                p.load(in);
                return p;
            } catch (IOException e) {
                System.err.println("[JobConfig] classpath flink-job.properties 解析失败：" + e.getMessage());
            }
        }

        // 4) 最后兜底：代码里的默认值（保持向后兼容）
        System.err.println("[JobConfig] 未找到外部配置，使用代码内默认值（开发/测试专用）");
        return defaults();
    }

    private static Properties defaults() {
        Properties p = new Properties();
        p.setProperty("kafka.bootstrap.servers", "localhost:9092");
        p.setProperty("kafka.topic", "device-sensor");
        p.setProperty("kafka.group.id", "flink-device-group");

        p.setProperty("mysql.url", "jdbc:mysql://localhost:3306/predictive_maintenance?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true");
        p.setProperty("mysql.user", "root");
        p.setProperty("mysql.password", "");

        p.setProperty("redis.host", "localhost");
        p.setProperty("redis.port", "6379");
        p.setProperty("redis.password", "");

        p.setProperty("hdfs.uri", "hdfs://localhost:9000");
        p.setProperty("hdfs.model.index.path", "/tmp/models/anomaly_current_version.txt");
        p.setProperty("hdfs.checkpoint.path", "/flink/checkpoints/");
        p.setProperty("hdfs.sensor.output.path", "hdfs://localhost:9000/data/history/sensor");

        p.setProperty("window.size.ms", "30000");
        p.setProperty("window.slide.ms", "10000");
        p.setProperty("alarm.threshold", "0.8");
        p.setProperty("model.reload.interval.ms", "60000");

        p.setProperty("cep.temp.rise.threshold", "2.0");
        p.setProperty("cep.temp.rise.count", "3");
        p.setProperty("cep.vibration.threshold", "5.0");
        p.setProperty("cep.current.threshold", "3.5");
        p.setProperty("cep.pressure.drop.threshold", "10.0");
        return p;
    }

    /** 重新加载配置（需要在作业启动前调用一次） */
    public static void reload() {
        props = load();
    }

    public static String get(String key, String def) {
        return props.getProperty(key, def);
    }

    public static int getInt(String key, int def) {
        try { return Integer.parseInt(props.getProperty(key, String.valueOf(def))); }
        catch (NumberFormatException e) { return def; }
    }

    public static long getLong(String key, long def) {
        try { return Long.parseLong(props.getProperty(key, String.valueOf(def))); }
        catch (NumberFormatException e) { return def; }
    }

    public static double getDouble(String key, double def) {
        try { return Double.parseDouble(props.getProperty(key, String.valueOf(def))); }
        catch (NumberFormatException e) { return def; }
    }

    // ============ 便捷访问器（保留旧代码的使用习惯） ============

    public static String KAFKA_BOOTSTRAP_SERVERS()        { return get("kafka.bootstrap.servers", "localhost:9092"); }
    public static String KAFKA_TOPIC()                     { return get("kafka.topic", "device-sensor"); }
    public static String KAFKA_GROUP_ID()                  { return get("kafka.group.id", "flink-device-group"); }

    public static String MYSQL_URL()                       { return get("mysql.url", "jdbc:mysql://localhost:3306/predictive_maintenance"); }
    public static String MYSQL_USER()                      { return get("mysql.user", "root"); }
    public static String MYSQL_PASSWORD()                  { return get("mysql.password", ""); }

    public static String REDIS_HOST()                      { return get("redis.host", "localhost"); }
    public static int    REDIS_PORT()                      { return getInt("redis.port", 6379); }
    public static String REDIS_PASSWORD()                  { return get("redis.password", ""); }

    public static String HDFS_URI()                       { return get("hdfs.uri", "hdfs://localhost:9000"); }
    public static String HDFS_MODEL_INDEX_PATH()           { return get("hdfs.model.index.path", "/tmp/models/anomaly_current_version.txt"); }
    public static String HDFS_CHECKPOINT_PATH()            { return get("hdfs.checkpoint.path", "/flink/checkpoints/"); }
    public static String HDFS_SENSOR_OUTPUT_PATH()         { return get("hdfs.sensor.output.path", "hdfs://localhost:9000/data/history/sensor"); }

    public static long   WINDOW_SIZE_MS()                  { return getLong("window.size.ms", 30000); }
    public static long   WINDOW_SLIDE_MS()                 { return getLong("window.slide.ms", 10000); }
    public static double ALARM_THRESHOLD()                 { return getDouble("alarm.threshold", 0.8); }
    public static long   MODEL_RELOAD_INTERVAL_MS()        { return getLong("model.reload.interval.ms", 60000); }

    public static double CEP_TEMP_RISE_THRESHOLD()         { return getDouble("cep.temp.rise.threshold", 2.0); }
    public static int    CEP_TEMP_RISE_COUNT()             { return getInt("cep.temp.rise.count", 3); }
    public static double CEP_VIBRATION_THRESHOLD()         { return getDouble("cep.vibration.threshold", 5.0); }
    public static double CEP_CURRENT_THRESHOLD()           { return getDouble("cep.current.threshold", 3.5); }
    public static double CEP_PRESSURE_DROP_THRESHOLD()     { return getDouble("cep.pressure.drop.threshold", 10.0); }
}
