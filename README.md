# 手工打造hadoop-spark镜像

网上有现成的docker镜像可用，肯定比我的这个好用，如果有需要其实可以用[这个](https://clubhouse.io/developer-how-to/how-to-set-up-a-hadoop-cluster-in-docker)。不好的是，别人的镜像各种应用的版本不受控制，不太爽，而且每折腾一次也是多学习一点知识，因此我手动建立了一个docker镜像。

最终的版本结合是：`oracle-jdk_8u231 ` + `scala_2.11.12` + `hadoop_2.6.5` + `spark_2.3.0`

## 先部署Hadoop

1. 下载相关软件包并解压，放在一个文件夹里，形成这样的文件树，我这里的母文件夹是`hadoop-docker`

   ```
   |- hadoop-docker
       |- hadoop-2.6.5
       |- jdk-1.8.0_231
       |- scala-2.11.12
       |- spark-2.3.0-bin-without-hadoop
   ```

2. 搞个基础镜像，我用的是`ubuntu:18.04`

   ```shell
   docker pull ubuntu:18.04
   ```

3. 因为最后要在master和slave上做到ssh通信，要准备密钥对，我这里直接生成好。

   ```shell
   # 使用刚才的docker镜像生成两种key
   # -v 挂载的
   docker run -it --rm -v /path/to/hadoop-docker:/root/outer ubuntu:18.04
   # 在docker的终端下
   apt update
   apt-get install openssh-server openssh-client -y
   ssh-keygen -t rsa -P ""
   cp ~/.ssh/id_rsa /root/outer/id_rsa
   cp ~/.ssh/id_rsa.pub /root/outer/authorized_keys
   ```

   操作完成后，`hadoop-docker`形成下面的目录树

   ```
   |- hadoop-docker
       |- hadoop-2.6.5
       |- jdk-1.8.0_231
       |- scala-2.11.12
       |- spark-2.3.0-bin-without-hadoop
       |- id_rsa
       |- authorized_keys
   ```

4. 各种修改配置文件

   + hadoop-2.6.5/etc/hadoop/core-site.xml   添加下列内容

     ```xml
     <configuration>
     	<property>
     		<name>fs.defaultFS</name>
     		<value>hdfs://master:9000</value>
     	</property>
     	<property>
     		<name>hadoop.tmp.dir</name>
     		<value>/root/hdata</value>
     	</property>
     </configuration>
     ```

   + hadoop-2.6.5/etc/hadoop/hdfs-site.xml   添加下列内容

     ```xml
     <configuration>
     	<property>
     		<name>dfs.replication</name>
     		<value>2</value>
         </property>
         <property>
             <name>dfs.namenode.name.dir</name>
             <value>file:/hdfs/name</value>
         </property>
         <property>
             <name>dfs.datanode.data.dir</name>
             <value>file:/hdfs/data</value>
         </property>
     </configuration>
     ```

   + hadoop-2.6.5/etc/hadoop/mapred-site.xml

     ```xml
     <configuration>
     	<property>
     		<name>mapreduce.framework.name</name>
     		<value>yarn</value>
     	</property>
     </configuration>
     ```

   + hadoop-2.6.5/etc/hadoop/yarn-site.xml

     ```xml
     <configuration>
         <property>
             <name>yarn.nodemanager.aux-services</name>
             <value>mapreduce_shuffle</value>
         </property>
         <property>
             <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>
             <value>org.apache.hadoop.mapred.ShuffleHandler</value>
         </property>
         <property>
             <name>yarn.resourcemanager.resource-tracker.address</name>
             <value>master:8025</value>
         </property>
         <property>
             <name>yarn.resourcemanager.scheduler.address</name>
             <value>master:8030</value>
         </property>
         <property>
             <name>yarn.resourcemanager.address</name>
             <value>master:8040</value>
         </property>
         <property>
             <name>yarn.nodemanager.resource.memory-mb</name>
             <value>2048</value>
         </property>
         <property>
             <name>yarn.nodemanager.vmem-pmem-ratio</name>
             <value>4</value>
             <description>Ratio between virtual memory to physical memory when setting memory limits for containers</description>
         </property>
     </configuration>
     ```

   + hadoop-2.6.5/etc/hadoop/slaves

     ```xml
     slave01
     slave02
     ```

   + spark-2.3.0-bin-without-hadoop/conf/slaves（复制template重命名）

     ```
     slave01
     slave02
     ```

   + spark-2.3.0-bin-without-hadoop/conf/spark-defaults.conf

     ```properties
     spark.yarn.jars=/usr/local/spark-2.3.0/jars/*
     spark.history.fs.logDirectory=hdfs://master:9000/spark-historys
     spark.history.retainedApplications=20
     ```

   + spark-2.3.0-bin-without-hadoop/conf/spark-env.sh

     ```properties
     JAVA_HOME=/usr/local/jdk-1.8.0
     SCALA_HOME=/usr/local/scala-2.11.12
     HADOOP_HOME=/usr/local/hadoop-2.6.5
     HADOOP_CONF_DIR=/usr/local/hadoop-2.6.5/etc/hadoop
     SPARK_DIST_CLASSPATH=$(/usr/local/hadoop-2.6.5/bin/hadoop classpath) 
     SPARK_HOME=/usr/local/spark-2.3.0
     ```

5. 建立四个文件

   Dockerfile-nameNode

   ```dockerfile
   # for namenode/master
   FROM ubuntu:18.04
   # DEBIAN_FRONTEND=noninteractive 使得整个安装没有任何交互，适用于dockerfile
   RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install tzdata language-pack-zh-hans software-properties-common openssh-server openssh-client rsync -y && locale-gen zh_CN.UTF-8 && apt-get clean && apt-get autoclean
   COPY hadoop-2.6.5 /usr/local/hadoop-2.6.5
   COPY jdk-1.8.0_231 /usr/local/jdk-1.8.0
   COPY scala-2.11.12 /usr/local/scala-2.11.12
   COPY spark-2.3.0-bin-without-hadoop /usr/local/spark-2.3.0
   COPY id_rsa /root/.ssh/id_rsa
   # ssh首次登陆时不会有废话询问
   RUN chmod 0600 /root/.ssh/id_rsa && mkdir /run/sshd && echo 'StrictHostKeyChecking no' >> /etc/ssh/ssh_config
   COPY authorized_keys /root/.ssh/authorized_keys
   
   # 开启中文支持
   ENV LANG="zh_CN.UTF-8"
   
   ENV JAVA_HOME="/usr/local/jdk-1.8.0"
   ENV JRE_HOME=${JAVA_HOME}/jre
   ENV CLASSPATH=.:${JAVA_HOME}/lib:${JRE_HOME}/lib
   ENV PATH=${JAVA_HOME}/bin:$PATH
   
   ENV SCALA_HOME="/usr/local/scala-2.11.12"
   ENV PATH=${SCALA_HOME}/bin:$PATH
   
   ENV HADOOP_PREFIX="/usr/local/hadoop-2.6.5"
   ENV HADOOP_HOME=${HADOOP_PREFIX}
   ENV PATH=$PATH:$HADOOP_PREFIX/bin
   ENV PATH=$PATH:$HADOOP_PREFIX/sbin
   ENV HADOOP_MAPRED_HOME=${HADOOP_PREFIX}
   ENV HADOOP_COMMON_HOME=${HADOOP_PREFIX}
   ENV HADOOP_HDFS_HOME=${HADOOP_PREFIX}
   ENV YARN_HOME=${HADOOP_PREFIX}
   
   # 确保spark能找到hadoop的本地库
   ENV LD_LIBRARY_PATH=$HADOOP_HOME/lib/native:$LD_LIBRARY_PATH
   
   COPY entry-point-name.sh /root/entry-point.sh
   RUN chmod +x /root/entry-point.sh && ln -s /usr/bin/python3 /usr/bin/python && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
   ENTRYPOINT [ "/root/entry-point.sh" ]
   ```

   Dockerfile-dataNode

   ```dockerfile
   # for datanode/slave
   FROM ubuntu:18.04
   # DEBIAN_FRONTEND=noninteractive 使得整个安装没有任何交互，适用于dockerfile
   RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install tzdata language-pack-zh-hans software-properties-common openssh-server openssh-client rsync -y && locale-gen zh_CN.UTF-8 && apt-get clean && apt-get autoclean
   COPY hadoop-2.6.5 /usr/local/hadoop-2.6.5
   COPY jdk-1.8.0_231 /usr/local/jdk-1.8.0
   COPY scala-2.11.12 /usr/local/scala-2.11.12
   COPY spark-2.3.0-bin-without-hadoop /usr/local/spark-2.3.0
   # ssh首次登陆时不会有废话询问
   RUN mkdir /run/sshd && echo 'StrictHostKeyChecking no' >> /etc/ssh/ssh_config
   COPY authorized_keys /root/.ssh/authorized_keys
   
   # 中文支持
   ENV LANG="zh_CN.UTF-8"
   
   ENV JAVA_HOME="/usr/local/jdk-1.8.0"
   ENV JRE_HOME=${JAVA_HOME}/jre
   ENV CLASSPATH=.:${JAVA_HOME}/lib:${JRE_HOME}/lib
   ENV PATH=${JAVA_HOME}/bin:$PATH
   
   ENV SCALA_HOME="/usr/local/scala-2.11.12"
   ENV PATH=${SCALA_HOME}/bin:$PATH
   
   ENV HADOOP_PREFIX="/usr/local/hadoop-2.6.5"
   ENV HADOOP_HOME=${HADOOP_PREFIX}
   ENV PATH=$PATH:$HADOOP_PREFIX/bin
   ENV PATH=$PATH:$HADOOP_PREFIX/sbin
   ENV HADOOP_MAPRED_HOME=${HADOOP_PREFIX}
   ENV HADOOP_COMMON_HOME=${HADOOP_PREFIX}
   ENV HADOOP_HDFS_HOME=${HADOOP_PREFIX}
   ENV YARN_HOME=${HADOOP_PREFIX}
   
   # 确保spark能找到hadoop的本地库
   ENV LD_LIBRARY_PATH=$HADOOP_HOME/lib/native:$LD_LIBRARY_PATH
   
   COPY entry-point-data.sh /root/entry-point.sh
   RUN chmod +x /root/entry-point.sh && ln -s /usr/bin/python3 /usr/bin/python && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
   ENTRYPOINT [ "/root/entry-point.sh" ]
   ```

   entry-point-data.sh

   ```shell
   #!/bin/bash
   /usr/sbin/sshd
   tail -f /root/entry-point.sh
   ```

   Entry-point-name.sh

   ```shell
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
   ```

6. 创建docker-compose.yml文件

   ```yml
   version: '3'
   
   services:
     master:
       image: ubuntu-hadoop:namenode
       hostname: master
       networks:
         - hadoop-test
       volumes:
       # 我把volumes挂载出去了，以便重复使用
         - /Users/test/dockerVolume/hadoop/namenode:/hdfs/name
       ports:
         - "50070:50070"
         - "8020:8020"
         # for hadoop web ui
         - "8088:8088"
         # for spark web ui
         - "8089:8080"
         # for spark cluster master
         - "7077:7077"
         # for spark history server
         - "18080:18080"
         # for hadoop
         - "9000:9000"
   
     slave01:
       image: ubuntu-hadoop:datanode
       hostname: slave01
       networks:
         - hadoop-test
       volumes:
       # 我把volumes挂载出去了，以便重复使用
         - /Users/test/dockerVolume/hadoop/slave01:/hdfs/data
       environment:
         SERVICE_PRECONDITION: "master:50070"
       ports:
         - "50075:50075"
         - "50010:50010"
   
     slave02:
       image: ubuntu-hadoop:datanode
       hostname: slave02
       networks:
         - hadoop-test
       volumes:
       # 我把volumes挂载出去了，以便重复使用
         - /Users/test/dockerVolume/hadoop/slave02:/hdfs/data
       environment:
         SERVICE_PRECONDITION: "master:50070"
       ports:
         - "50076:50076"
         - "50011:50011"
   
   networks:
     hadoop-test:
       external:
         name: hadoop-test
   ```

7. 最后看一眼目录树，是这样的

   ```
   |- hadoop-docker
       |- hadoop-2.6.5
       |- jdk-1.8.0_231
       |- scala-2.11.12
       |- spark-2.3.0-bin-without-hadoop
       |- id_rsa
       |- authorized_keys
       |- Dockerfile-dataNode
       |- Dockerfile-nameNode
       |- entry-point-data.sh
       |- entry-point-name.sh
       |- docker-compose.yml
   ```

8. 构建镜像并运行

   ```shell
   cd /path/to/hadoop-docker
   docker build -t ubuntu-hadoop:datanode -f Dockerfile-dataNode .
   docker build -t ubuntu-hadoop:namenode -f Dockerfile-nameNode .
   # 为这玩意创建个network
   docker network create hadoop-test
   # 运行起来
   docker-compose up -d
   docker-compose log -f
   ```

9. 最后我把这些东西都放到github上去了

   [github: hadoop-docker](https://github.com/godisboy0/hadoop-spark-docker)