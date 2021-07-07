#!/bin/bash
#路由器上扫CF的脚本
#运行目录下创建一个cfip.txt定义扫描范围
#每行定义一个网段，例如1.0.0.0/24
#0.0.0.0/0则全网扫描
#扫描结果：查看log.txt
#测速结果：查看speedlog.txt

#支持输入参数:
#-n <num>表示并发任务数量，默认100。路由运行如果内存不足挂死，可适当调小。手机termux下建议400。
#-k 表示跳过扫描，仅测速。
#-m <mode>表示扫描模式，0表示https，1表示http
#-c 表示清除断点文件和扫描结果文件，从头扫描，不清除测速结果文件

function scan_single_ip(){
local ip;
ip=$1;
if [ $p_mode -eq 0 ];then
    curl -k --resolve valid.scan.cf:443:$ip https://valid.scan.cf/cdn-cgi/trace --connect-timeout 5 -m 5 --max-filesize 1 2>&1 | grep 'h=\|colo=' | tr '\n' ' ' | sed "s/^/ip=$ip &/g" | grep 'colo='  >> log.txt
else
    curl http://$ip/cdn-cgi/trace --connect-timeout 5 -m 5 2>&1 | grep 'h=\|colo=' | tr '\n' ' ' | sed "s/^/ip=$ip &/g" | grep 'colo='  >> log.txt
fi
}

function scan_subnet(){
raw=`echo $1.32 | tr '/' '.' | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,2}"`;
 
if [ "$raw"x = x ];then
    return;
fi

mask=`echo $raw | awk -F. '{print $5}'`;

if [ "$mask"x = x ];then
    return;
fi
    
i=`echo $raw | awk -F. '{print $1}'`;
j=`echo $raw | awk -F. '{print $2}'`;
k=`echo $raw | awk -F. '{print $3}'`;
l=`echo $raw | awk -F. '{print $4}'`;

if [ $i -le 0 ];then
    i=1;
fi

echo scanning:$i.$j.$k.$l/$mask
     
ipstart=$(((i<<24)|(j<<16)|(k<<8)|l));
hostend=$((2**(32-mask)-1));
loop=0;
while [ $loop -le $hostend ]
do
    read -u6;
    ip=$((ipstart|loop));
    i=$(((ip>>24)&255));
    j=$(((ip>>16)&255));
    k=$(((ip>>8)&255));
    l=$(((ip>>0)&255));
    loop=$((loop+1));
    {
    scan_single_ip $i.$j.$k.$l;
    echo >&6 ;
    } &
done
}

#测速
function speedtest(){
ip=$1;
if [ $p_mode -eq 0 ];then
    curl -k --resolve speedtest.udpfile.com:443:$ip https://speedtest.udpfile.com/cache.png -o /dev/null --connect-timeout 5 --max-time 10 > slog.txt 2>&1
else
    curl --resolve gh.msx.workers.dev:80:$ip http://gh.msx.workers.dev/https://github.com/AaronFeng753/Waifu2x-Extension-GUI/releases/download/v2.21.12/Waifu2x-Extension-GUI-v2.21.12-Portable.7z -o /dev/null --connect-timeout 5 --max-time 10 > slog.txt 2>&1
fi

cat slog.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep -v 'k\|M' >> speed.txt
for i in `cat slog.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep k | sed 's/k//g'`
do
	k=$i
	k=$((k*1024))
	echo $k >> speed.txt
done
for i in `cat slog.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep M | sed 's/M//g'`
do
	i=$(echo | awk '{print '$i'*10 }')
	M=$i
	M=$((M*1024*1024/10))
	echo $M >> speed.txt
done
max=0
for i in `cat speed.txt`
do
	max=$i
	if [ $i -ge $max ]; then
		max=$i
	fi
done
rm -rf slog.txt speed.txt
pi=`ping -c 3 -W 1 $ip`;
delay=`echo $pi | grep -oE "([0-9]{1,10}\.[0-9]{1,10}\/){2}[0-9]{1,10}.[0-9]{1,10}" | awk -F'/' '{print $2}' | awk -F'.' '{print $1}'`;
max=$((max/1024));
echo $ip $max kB/s $delay ms;
echo $ip $max kB/s $delay ms >> speedlog.txt
}

#1、把比较大的网段拆小，提升断点执行效率
#2、把cfip.txt里面不符合预期格式的内容跳过，避免报错
function divsubnet(){
raw=`echo $1.32 | tr '/' '.' | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,2}"`;
 
if [ "$raw"x = x ];then
    return;
fi

mask=`echo $raw | awk -F. '{print $5}'`;

if [ "$mask"x = x ];then
    return;
fi

mask=`echo $raw | awk -F. '{print $5}'`;
if [ "$mask"x = x ];then
    return;
fi


if [ $mask -ge 8 ] && [ $mask -le 23 ];then
    i=`echo $raw | awk -F. '{print $1}'`
    j=`echo $raw | awk -F. '{print $2}'`
    k=`echo $raw | awk -F. '{print $3}'`
    l=`echo $raw | awk -F. '{print $4}'`
        
    ipstart=$(((i<<24)|(j<<16)|(k<<8)|l));
    hostend=$((2**(32-mask)-1));
    loop=0;
    while [ $loop -le $hostend ]
    do
        subnet=$((ipstart|loop));
        i=$(((subnet>>24)&255));
        j=$(((subnet>>16)&255));
        k=$(((subnet>>8)&255));
        l=$(((subnet>>0)&255));
        loop=$((loop+256));
        echo $i.$j.$k.$l.24 >> tmpip.txt;
    done
else
    echo $raw | tr '/' '.' >> tmpip.txt;
fi
}

#解析脚本输入参数
input=`echo "$*" | sed "s/\-/\~/g"`;

p_mode=0;
max_task_num=100;

para=`echo $input | grep -Eo "~k"`;
p_k=0;
if [ ! "$para"x = x ];then
  p_k=1;
  input=`echo $input | sed "s/$para/\^A/g"`;
fi

para=`echo $input | grep -Eo "~n [0-9]{1,10}"`;
p_n=$max_task_num;
if [ ! "$para"x = x ];then
  p_n=`echo $para | awk '{print $2}'`;
  input=`echo $input | sed "s/$para/\^A/g"`;
fi
max_task_num=$p_n;

para=`echo $input | grep -Eo "~m [0-9]{1,10}"`;
if [ ! "$para"x = x ];then
  p_mode=`echo $para | awk '{print $2}'`;
  input=`echo $input | sed "s/$para/\^A/g"`;
fi

para=`echo $input | grep -Eo "~c"`;
p_c=0;
if [ ! "$para"x = x ];then
  p_c=1;
  input=`echo $input | sed "s/$para/\^A/g"`;
fi

#特殊处理，兼容老脚本任意参数跳过扫描流程
input=`echo $input | sed "s/\^A//g"`;
para=`echo $input | tr -d ' '`;
if [ ! "$para"x = x ];then
  p_k=1;
fi

##创建FIFO控制并发进程数
tmp_fifofile="./$$.fifo"
mknod $tmp_fifofile p
exec 6<>$tmp_fifofile
rm -f $tmp_fifofile
for i in `seq $max_task_num`;
do
    echo >&6
done


if [ $p_c -eq 1 ];then
    echo " " > log.txt;
    echo " " > tmpip.txt;
    rm log.txt tmpip.txt;
fi

if [ ! -f cfip.txt ];then
  echo "1.0.0.0/24,1.1.1.0/24" >> cfip.txt
fi

#扫描流程
if [ $p_k -eq 0 ];then
    if [ ! -f tmpip.txt ];then
        cat cfip.txt | tr ',' '\n' | tr '/' '.' | tr ' ' '\n' | while read line
        do
            divsubnet $line;
        done
    fi
  cat tmpip.txt | while read line
    do
        if [ ! "$line"x = x ];then
            scan_subnet $line;
            sed -i "s/$line//g" tmpip.txt;
        fi
    done
    rm tmpip.txt;
fi

wait;
exec 6>&-

#测速流程
cat log.txt | tr 'ip=' ' ' | awk '{print $1}' | while read line
do
    speedtest $line;
    cat speedlog.txt | awk '{print $2,$1,$3,$4,$5}' | sort -nr | awk '{print $2,$1,$3,$4,$5}' > tmp.txt;cat tmp.txt > speedlog.txt;rm tmp.txt;
done

