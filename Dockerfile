FROM 10.6.13.254:5000/centos:java
MAINTAINER wangxiyang@ofo.com

RUN yum install -y wget lsof zip unzip netstat

ADD target /export/servers
WORKDIR /export/servers

ENV JAVA_HOME=/export/servers/jdk1.8.0_71
ENV CLASSPATH=$JAVA_HOME/lib
ENV MAVEN_HOME=/export/servers/maven-3.5.3
ENV PATH=$PATH:$JAVA_HOME/bin:$MAVEN_HOME/bin

EXPOSE 2203
CMD ["java","-jar","ofo-mj.jar"]
