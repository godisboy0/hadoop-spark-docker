#!/bin/bash
# 启动hadoop
/usr/sbin/sshd
# 如果文件 namenode已经初始化过了，就不初始化了
if [ ! -d "/hdfs/name/current" ]; then
    hdfs namenode -format
fi
start-dfs.sh
start-yarn.sh

# 打开spark集群
/usr/local/spark-2.3.0/sbin/start-all.sh

# 测试 history-log 文件在不在
hadoop fs -test -e /spark-historys
if [ $? -eq 0 ] ;then 
    echo 'history log file exist' 
else 
    hdfs dfs -mkdir /spark-historys
fi 
# 打开 spark 历史服务器
/usr/local/spark-2.3.0/sbin/start-history-server.sh

# 把docker卡住不让结束
tail -f /root/entry-point.sh