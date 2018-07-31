#!/bin/bash
CUR_PATH=`pwd`
SSHPASS="$CUR_PATH/tools/sshpass"
ERROR_INFO="$CUR_PATH/.ERROR_INFO"
rm -f $ERROR_INFO
regitstry_address="10.6.13.254:5000"
IPLIST=$1
PASSWORD=$2
JOB_NAME=$3
BUILD_NUMBER=$4

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

function record_error_info()
{
    echo "[FATAL]$@" >> $ERROR_INFO
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


function pssh()
{
	local ip=$1
	local cmd=$2
	local ssh="$SSHPASS -p $PASSWORD ssh -o StrictHostKeyChecking=no"
	$ssh root@$ip "$cmd"
	local ret=$?
	[[ $ret -ne 0 ]] && record_error_info "[$ip]:$cmd"
	return $ret
}

function connect_machine()
{
	[[ ! -f $IPLIST ]] && return 1
	local sshpass="$SSHPASS -p $PASSWORD"
	local total=`cat $IPLIST | wc -l`
	local num=0
	while [[ 1 ]]
	do
		[[ $num -ge $total ]] && break
		((num++))
		local oneip=`sed -n "$num"p $IPLIST`
		[[ -z $oneip || $oneip = "#"* ]] && continue
		pssh $oneip "echo $oneip"
		[[ $? -ne 0 ]] && continue
		pssh $oneip "mkdir -p /export/servers/$JOB_NAME"
		[[ $? -ne 0 ]] && continue
		$sshpass scp $JOB_NAME.tar.gz root@$oneip:/export/servers/$JOB_NAME
		[[ $? -ne 0 ]] && record_error_info "[$oneip]:scp $JOB_NAME.tar.gz failed!" && continue
		pssh $oneip "cd /export/servers/$JOB_NAME; tar zxf $JOB_NAME.tar.gz"
		pssh $oneip "echo ---->$oneip 发送软件包成功。"
	done
	return 0
}

function docker_image_build()
{
	docker build -t $JOB_NAME:$BUILD_NUMBER . > /dev/null 2>&1
	[[ $? != 0 ]] && abnormal_exit "---->制作镜像失败。" || echo "---->制作镜像成功。"
	sleep 2
	docker tag $JOB_NAME:$BUILD_NUMBER $regitstry_address/$JOB_NAME:$BUILD_NUMBER > /dev/null 2>&1
	[[ $? != 0 ]] && abnormal_exit "---->标记镜像失败。" || echo "---->标记镜像成功。"
	sleep 2
	docker push $regitstry_address/$JOB_NAME:$BUILD_NUMBER > /dev/null 2>&1
	[[ $? != 0 ]] && abnormal_exit "---->上传镜像失败。" || echo "---->上传镜像成功。"
	sleep 2
	docker rmi $JOB_NAME:$BUILD_NUMBER && docker rmi $regitstry_address/$JOB_NAME:$BUILD_NUMBER > /dev/null 2>&1
	[[ $? != 0 ]] && abnormal_exit "---->删除镜像失败。" || echo "---->删除镜像成功。"
	return 0
}

execshell "connect_machine"
execshell "docker_image_build"
