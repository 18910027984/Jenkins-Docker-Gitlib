#!/bin/bash
regitstry_address="10.6.13.254:5000"
ERROR_INFO="$CUR_PATH/.ERROR_INFO"
rm -f $ERROR_INFO
JOB_NAME=$1
BUILD_NUMBER=$2
LISTEN_PORT_HOST=$3
LISTEN_PORT_CONTAINER=$4

function execshell()
{
	echo "[execshell]$@ begin."
	eval $@
	[[ $? != 0 ]] && {
		echo "[execshell]$@ failed."
		exit 1
	}
	echo "[execshell]$@ success"
	return 0
}

function abnormal_exit()
{
	echo "[FATAL]$@"
	exit 1
}

function exit_procprocess()
{
    local ret=$?
    kill -9 `pstree $$ -p|awk -F"[()]" '{for(i=1;i<=NF;i++)if($i~/[0-9]+/)print $i}'|grep -v $$` 2>/dev/null
    [[ -f $ERROR_INFO ]] && ret=1
    cat $ERROR_INFO 2>/dev/null
    exit $ret
}

function trap_exit()
{
	trap "exit_procprocess $@" 0
}
trap_exit

function install_docker()
{
		os_core=`uname -r | cut -d "." -f '1,2'`
		[[ $os_core != 3.10 ]] && abnormal_exit "---->内核版本小于3.1，无法使用docker服务。"
		os_bits=`uname -r | cut -d "_" -f '2'`
		[[ $os_bits != 64 ]] && abnormal_exit "---->非64位系统，无法使用docker服务。"
		
		yum -y remove docker-engine > /dev/null 2>&1
		yum -y update > /dev/null 2>&1

cat << EOF > /etc/yum.repos.d/docker.repo
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/\$releasever/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF

		yum -y install docker-engine > /dev/null 2>&1 
		[[ $? != 0 ]] && abnormal_exit "---->Docker安装失败。" || echo "---->Docker服务安装成功。"
		sed -i "/ExecStart.*/ s/$/ --insecure-registry $regitstry_address/" /usr/lib/systemd/system/docker.service > /dev/null 2>&1
		[[ $? != 0 ]] && abnormal_exit "---->添加私仓地址失败。" || echo "---->添加私仓地址成功。"
		systemctl enable docker > /dev/null 2>&1 
		systemctl start docker.service > /dev/null 2>&1
		[[ $? != 0 ]] && abnormal_exit "---->Docker服务启动失败。" || echo "---->Docker服务启动成功。"
		chmod 777 /var/run/docker.sock
	return 0
}

function docker_remote_run()
{
	local image_name=$regitstry_address/$JOB_NAME:$BUILD_NUMBER
	docker ps -a | awk '$NF=="'"$JOB_NAME"'" {print $1}' | xargs docker kill > /dev/null 2>&1 #杀掉老的容器，精确匹配JOB_NAME名称，Jenkins的JOB_NAME需唯一
	echo "---->已关闭旧容器。" && sleep 2

	docker ps -a | awk '$NF=="'"$JOB_NAME"'" {print $1}' | xargs docker rm > /dev/null 2>&1
	echo "---->已删除旧容器。" && sleep 2
	
	docker images | awk '$1=="'"$regitstry_address/$JOB_NAME"'" {print $3}' | xargs docker rmi > /dev/null 2>&1
	echo "---->已删除旧镜像。" && sleep 2

	docker pull $image_name > /dev/null 2>&1
	[[ $? != 0 ]] && abnormal_exit "---->拉取新镜像失败。" || echo "---->拉取新镜像成功。"
	sleep 2
    
	docker run -it -d -p $LISTEN_PORT_HOST:$LISTEN_PORT_CONTAINER --name $JOB_NAME $image_name > /dev/null 2>&1
	[[ $? != 0 ]] && abnormal_exit "---->新容器部署失败。" || echo "---->新容器部署成功。"
    return 0
}

execshell "install_docker"
execshell "docker_remote_run"
