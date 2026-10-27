package com.predict.utils;

import com.predict.config.JobConfig;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.URI;

/**
 * HDFS 文件操作工具，HDFS URI 统一从 JobConfig 读取，
 * 避免在多个类里重复硬编码 master/slave 节点名。
 */
public class HdfsUtils {

    public static String readFileAsString(String hdfsPath) throws Exception {
        Configuration conf = new Configuration();
        try (FileSystem fs = FileSystem.get(URI.create(JobConfig.HDFS_URI()), conf)) {
            Path path = new Path(hdfsPath);
            if (!fs.exists(path)) {
                return null;
            }
            StringBuilder sb = new StringBuilder();
            try (BufferedReader br = new BufferedReader(new InputStreamReader(fs.open(path)))) {
                String line;
                while ((line = br.readLine()) != null) {
                    sb.append(line);
                }
            }
            return sb.toString();
        }
    }

    public static boolean exists(String hdfsPath) {
        try {
            Configuration conf = new Configuration();
            try (FileSystem fs = FileSystem.get(URI.create(JobConfig.HDFS_URI()), conf)) {
                return fs.exists(new Path(hdfsPath));
            }
        } catch (Exception e) {
            return false;
        }
    }
}
