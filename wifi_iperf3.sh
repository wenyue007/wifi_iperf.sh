#!/bin/bash -
#Author: Jianwei.Hu@windriver.com
#Date: 2015/12/5
#Version: v1.0

expect_re=`expect -h &> /dev/null;echo $?`
BASH="bash"

#This is an useful conf template
gen_conf()
{
    ans=n
    read -p "Do you want to generate/rewrite the conf?[y/N]" ans
    [ x"$ans" == x"n" -o -z "$ans" ] && exit 1 
cat <<EOF > ./conf
#172.168.1.1 5001 - root
#172.168.1.1 5002 R root
#172.168.1.1 5003 - root
#172.168.1.1 5004 R root
#172.168.1.1 5005 - root
#172.168.1.1 5006 R root
#172.168.1.1 5007 - root
#172.168.1.1 5008 R root 
#128.224.158.179 8888 - root
#128.224.158.179 9999 R root
EOF
}

parse_conf()
{
    available_line=0
    real_line=0
    [ -f ./conf ] || { echo -e "\033[31mThe config file is not existing\033[0m";gen_conf; exit 1;}
    while read line
    do
        available_line=$((available_line + 1 ))
        have_line=`echo $line |grep "^#" > /dev/null 2>&1;echo $?`
        [ $have_line -eq 0 ] && continue || real_line=$((real_line + 1 ))
        t=`echo $line | awk -F" " '{print NF}'`
        [ $t -eq 5 ] && t=$(($t - 1))
        [ $t -ne 4 ] && { echo -e "\033[31mLine $available_line: Need 4 items in conf.\033[0m"; exit 1; }
        i=`echo $line | awk -F" " '{print $1}'`
        p=`echo $line | awk -F" " '{print $2}'`
        m=`echo $line | awk -F" " '{print $3}'`
        a=`echo $line | awk -F" " '{print $4}'`
        have_i=`echo $i |grep "^[0-9]\{1,3\}\.\([0-9]\{1,3\}\.\)\{2\}[0-9]\{1,3\}$" >/dev/null 2>&1; echo $?`
        [ $have_i -ne 0 ] && { echo -e "\033[31mLine $available_line: Bad IP address in conf.\033[0m";exit 1; }
        have_p=`echo $p |grep "[0-9]" >/dev/null 2>&1; echo $?`
        [ $have_p -ne 0 ] && { echo -e "\033[31mLine $available_line: Bad port in conf.\033[0m";exit 1; }
        have_m=`echo $m |grep -E "\-|R" >/dev/null 2>&1; echo $?`
        [ $have_m -ne 0 ] && { echo -e "\033[31mLine $available_line: Bad iperf3 mode in conf.\033[0m";exit 1; }
        [ -z "$a" ] && { echo -e "\033[31mLine $available_line: Null target default account in conf.\033[0m";exit 1; }
    done < ./conf
    if [ $real_line -lt 1 ]; then
        echo -e "\033[31mThis is empty conf.\033[0m"
        exit 1
    fi
}

#Auto-ssh to peer OS using this function, two ways, one is ssh-copy-id, another is scp
#In this function, we need input the peer password at least one time.

keys1()
{

    [ -f ./conf ] || { echo -e "\033[31mThe config file is not existing\033[0m";gen_conf; exit 1;}
    cat ./conf | grep -v "^#"| uniq -w 15 > ./conf.tmp   
    echo -e "\033[34mRunning ssh-keygen/ssh-add ...[y]\033[0m"
    [ -f ~/.ssh/id_rsa.pub ] || 
        if [ "$expect_re" -eq 1 ]; then
        {
            expect <<- END
            spawn ssh-keygen -t rsa
            expect "Enter file in which to save the key" 
            send "\r"
           
            expect "Enter passphrase (empty for no passphrase):"
            send "\r"
           
            expect  "Enter same passphrase again:"       
            send "\r"
            	
            expect eof
            exit
END
        }
     else
        ssh-keygen -q
    fi
    ssh-add ~/.ssh/id_rsa > /dev/null 2>&1
    while read line
    do
        com_f=`echo $line |grep "^#" > /dev/null 2>&1;echo $?`
        server_ip=`echo $line |grep -v "^#" | awk -F" " '{print $1}'`
        account=`echo $line |grep -v "^#" | awk -F" " '{print $4}'` 
        t=`echo $line | awk -F" " '{print NF}'`
        [ $t -eq 5 ]&& passwdd=`echo $line |grep -v "^#" | awk -F" " '{print $5}'` 
        ssh-keygen -R $server_ip &> /dev/null
        [ $com_f -eq 0 ] && continue
        [ -z "$account" -o -z "$server_ip" ] && { echo "Null for ip or account"; continue;}
        echo -e "\033[34m>>>>On $account at $server_ip :\033[0m"
        echo "Try to connect it..."
        ping $server_ip -c 3  > /dev/null 2>&1 && echo -e "\033[32mSuccess to connect it\033[0m "|| { echo -e "\033[31mFailed to connect it\033[0m"; continue;}

        ssh -n -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=0 ${account}@$server_ip "ls -l" > tmp.log 2>&1
        r=`cat tmp.log | grep -E "Permission denied|Connection refused|Too many authentication failures" > /dev/null 2>&1;echo $?`
        [ $r -ne 0 ] && { echo -e "\033[32mAlready pass to login without password!\033[0m"; rm -rf tmp.log; continue;}
        rm -rf tmp.log

        type ssh-copy-id >/dev/null 2>&1
        re_id=`echo $?`
        if [ "$re_id" -eq 0 ]; then
            if [ "$expect_re" -eq 1 ]; then
                expect <<- END
                spawn  ssh-copy-id -o StrictHostKeyChecking=no ${account}@$server_ip
                expect "Password"
                send "${passwdd:-root}\r"
                expect eof
                exit
END
            else
                ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub ${account}@$server_ip >/dev/null 2>&1
            fi
        else
            echo -e "\033[34m[Please input password] Using tradition scp type...\033[0m"
            echo -e "\033[34mscp ~/.ssh/id_rsa.pub to peer server\033[0m"
            scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa.pub ${account}@${server_ip}:~
            echo -e "\033[34mcat id_rsa.pub into authorized_keys in peer server\033[0m"
            ssh -n -o StrictHostKeyChecking=no -n ${account}@$server_ip "cat ~/id_rsa.pub  >> ~/.ssh/authorized_keys"
            echo -e "\033[34mchange authorized_keys mode to 600 in peer server\033[0m"
            ssh -n ${account}@$server_ip "chmod 600 ~/.ssh/authorized_keys"
        fi
        echo -e "\033[34mDone for '$account' on '$server_ip' autossh login\033[0m"
    done < ./conf.tmp
    rm -rf ./conf.tmp
}

keys()
{
    [ -f ./conf ] || { echo -e "\033[31mThe config file is not existing\033[0m";gen_conf; exit 1;}
    cat ./conf | grep -v "^#"| uniq -w 15 > ./conf.tmp   
    echo -e "\033[34mRunning ssh-keygen/ssh-add ...[y]\033[0m"
    [ -f ~/.ssh/id_rsa.pub ] || ssh-keygen -q
    ssh-add ~/.ssh/id_rsa > /dev/null 2>&1
    while read line
    do
        com_f=`echo $line |grep "^#" > /dev/null 2>&1;echo $?`
        server_ip=`echo $line |grep -v "^#" | awk -F" " '{print $1}'`
        account=`echo $line |grep -v "^#" | awk -F" " '{print $4}'` 
        ssh-keygen -R $server_ip &> /dev/null
        [ $com_f -eq 0 ] && continue
        [ -z "$account" -o -z "$server_ip" ] && { echo "Null for ip or account"; continue;}
        echo -e "\033[34m>>>>On $account at $server_ip :\033[0m"
        echo "Try to connect it..."
        ping $server_ip -c 3  > /dev/null 2>&1 && echo -e "\033[32mSuccess to connect it\033[0m "|| { echo -e "\033[31mFailed to connect it\033[0m"; continue;}

        ssh -n -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=0 ${account}@$server_ip "ls -l" > tmp.log 2>&1
        r=`cat tmp.log | grep -E "Permission denied|Connection refused" > /dev/null 2>&1;echo $?`
        [ $r -ne 0 ] && { echo -e "\033[32mAlready pass to login without password!\033[0m"; rm -rf tmp.log; continue;}
        rm -rf tmp.log

        type ssh-copy-id >/dev/null 2>&1
        re_id=`echo $?`
        if [ "$re_id" -eq 0 ]; then
            echo -e "\033[34m[Please input password] Using ssh-copy-id...\033[0m"
            ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub ${account}@$server_ip >/dev/null 2>&1
            [ $? -ne 0 ] && ssh-copy-id -i ~/.ssh/id_rsa.pub ${account}@$server_ip >/dev/null  2>&1
        else
            echo -e "\033[34m[Please input password] Using tradition scp type...\033[0m"
            echo -e "\033[34mscp ~/.ssh/id_rsa.pub to peer server\033[0m"
            scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa.pub ${account}@${server_ip}:~
            echo -e "\033[34mcat id_rsa.pub into authorized_keys in peer server\033[0m"
            ssh -n -o StrictHostKeyChecking=no -n ${account}@$server_ip "cat ~/id_rsa.pub  >> ~/.ssh/authorized_keys"
            echo -e "\033[34mchange authorized_keys mode to 600 in peer server\033[0m"
            ssh -n ${account}@$server_ip "chmod 600 ~/.ssh/authorized_keys"
        fi
        echo -e "\033[34mDone for '$account' on '$server_ip' autossh login\033[0m"
    done < ./conf.tmp
    rm -rf ./conf.tmp
}

#kill local machine's processes according to port/iperf3
killer()
{
     kill -9 `ps aux| grep runner |grep $port | awk -F" " '{print $2}'` > /dev/null 2>&1
     kill -9 `ps aux | grep iperf3 | grep $port | awk -F" " '{print $2}' ` > /dev/null 2>&1
}

#kill peer OS processes according to port/iperf3
rkiller()
{
     pid=`eval ssh -n ${account}@$server_ip ps aux | grep iperf3|grep $port| cut -d ' ' -f 2-7`
     ssh -n ${account}@$server_ip "kill -9 $pid >/dev/null 2>&1"

}

#Remove the shell script in runner_client function
clean_up()
{
    rm -rf runner_* 2>/dev/null
}

#Generate the new shell script for each port in conf on local machine
runner_client()
{
cat <<"EOF" > runner_${port}.sh
#!/bin/bash -

ip_addr=$1
port=$2
[ $3 == "R" ] && mode=-$3 || mode=""
iperf_time=$4
adjust_time=$iperf_time
loop_time=$5
logfile=$6
account=$7
[ $iperf_time -gt 86400 ] && iperf_time=0
for ((i=1; i<=$loop_time; i++))
do
        echo "+++++++++++++++++++++++Running $i mins on $port++++++++++++++++++++++++++++"
        date
        iperf3 -c $ip_addr -p $port -t $iperf_time $mode 
        re=`echo $?`
        [ $re -ne 0 -a $adjust_time -gt 86400 ] && { echo 'Maybe: Time is running out!!!'; continue; } 
        if [ $re != 0 ]; then 
            echo "iperf3 failed, skipped this time!!!"
            sleep 60
            total_error=`cat $logfile | grep "iperf3 failed"|wc -l`
            last_error=`cat $logfile | grep "iperf3 failed" -A5 |tail -5|grep "busy" > /dev/null 2>&1; echo $?`
            if [ "$total_error" -gt 30 -a "$last_error" -eq 0 ]; then
                pid=`eval ssh -n ${account}@$ip_addr ps aux | grep iperf3|grep $port| cut -d ' ' -f 2-7`
                ssh -n ${account}@$ip_addr "kill -9 $pid >/dev/null 2>&1"
                ssh -n ${account}@$ip_addr "iperf3 -s -p $port > $logfile 2>&1 &"
            fi
        fi
        date
        sleep 5

done

check=$(($loop_time + 1 ))
if [ $i == $check ]; then
        echo "Done!!!"
else
        echo "Failed!!!"
fi
pid=`eval ssh -n ${account}@$ip_addr ps aux | grep iperf3|grep $port| cut -d ' ' -f 2-7`
ssh -n ${account}@$ip_addr "sleep 15;kill -9 $pid >/dev/null 2>&1"
rm -rf runner_${port}.sh 2>/dev/null
EOF

}

#Execute iperf3 command on peer OS
runner_server()
{
    rkiller
    logfile="${port}_`date +%y_%m_%d_%H_%M`.log"
    ssh -n ${account}@$server_ip "touch $logfile" 
    ssh -n ${account}@$server_ip "iperf3 -s -p $port > $logfile 2>&1 &"
}

#Parse conf and run iperf3 server on peer OS
sponser_server()
{
    [ -f ./conf ] || { echo "The config file is not existing";gen_conf;exit 1;}
    while read items
    do
        server_ip=`echo $items | awk -F" " '{print $1}'`
        account_tmp=`echo $items | awk -F" " '{print $4}'`
        `echo "$server_ip" | grep "#" > /dev/null 2>&1`
         [ $? -eq 0 ] && continue
        port=`echo $items | awk -F" " '{print $2}'`
        [ "$account" != "$account_tmp" ] && account=$account_tmp
        echo "On $account at $server_ip, starting $port"

        runner_server
    done < ./conf
    sleep 5
}

#Parse conf and run iperf3 client on current OS
sponser_client()
{
    clean_up
    local_killer
    i=1
    [ -f ./conf ] || { echo "The config file is not existing";gen_conf;exit 1;}
    while read items
    do
        ip_addr=`echo $items | awk -F" " '{print $1}'`
        `echo "$ip_addr" | grep "#" > /dev/null 2>&1`
         [ $? -eq 0 ] && continue
        port=`echo $items | awk -F" " '{print $2}'`
        mode=`echo $items | awk -F" " '{print $3}'`
        account_tmp=`echo $items | awk -F" " '{print $4}'`
        [ "$account" != "$account_tmp" ] && account=$account_tmp
        echo "On current target, running iperf3 client: $ip_addr $port $mode $iperf_time $loop_time"
        touch ${port}_`date +%y_%m_%d_%H_%M`.log && logfile="${port}_`date +%y_%m_%d_%H_%M`.log"
        killer
        runner_client
        echo "`date +%s%N` $iperf_time $loop_time" > $logfile
        $BASH ./runner_${port}.sh $ip_addr $port $mode $iperf_time $loop_time $logfile $account 2>&1 >> $logfile &
    done < ./conf
    monitor
    $BASH ./monitor.sh $logfile $iperf_time $loop_time &
}

usage()
{
cat << EOF
Usage:
$0 [-d XX |-l XX |-f local_file |--status/--loop |--key |--conf |--kill |--check |-h/--help ]
    -d X       duration hours, when level is 4, duration is mintue
    -l X       running level for iperf3, pass time for each running iperf3
    -f X       show report from specified local files
    --key      send ssh key to target, for the first time connection
    --conf     generate a template of conf
    --kill     kill all running $0 process/child on current OS
    --status   show all running $0 processes on current OS
    --loop     show all related $0 processes/info per 5 seconds
    --check    check the connectivity of target in conf
    -h/--help  show this help
EOF
}

#When meeting error, this function will kill all running processes for the last time
local_killer()
{
    echo "kill all related running process"
    kill -9 `ps aux| grep bash |grep runner | awk -F" " '{print $2}'` > /dev/null 2>&1
    kill -9 `ps aux| grep bash |grep monitor | awk -F" " '{print $2}'` > /dev/null 2>&1
    killall iperf3 > /dev/null 2>&1
}

#Return the status of current running processes, when $s_flag=y, loop show status.
local_status()
{
    l_flag="y"
    local_file="$@"
    while [ x"$l_flag" == x"y" ]
    do
        ps aux | grep bash | grep runner >/dev/null 2>&1
        [ $? -ne 0 ] && { [ -z "$local_file" ] && exit 1; }
        log_file=`ps aux | grep bash | grep runner| head -1 |awk -F" " '{print $(NF-1)}'`
        [ -n "$local_file" ] && log_file=$local_file
        total_time=`ps aux | grep bash | grep runner| head -1 |awk -F" " '{print $(NF-2)}'`
        elapsing_time=`cat $log_file | grep "++++++Running"|tail -1| awk -F" " '{print $2}'`
        tttt1=`cat $log_file |head -1| awk -F" " '{print $2}'`
        tttt2=`cat $log_file |head -1| awk -F" " '{print $3}'`
        tttt=$(($(($tttt1 * $tttt2))/60))
        start_time=`cat $log_file |head -1| awk -F" " '{print $1}'`
        current_time=`date +%s%N`
        total_time=$tttt
        elapsing_time=$(($(($current_time - $start_time ))/60000000000))
        echo "======================================================================================"
        [ -z "$local_file" ] &&  echo "Show all related running process, elapsing time: $elapsing_time/$total_time mintues, remaining time: $(($total_time - $elapsing_time))"
        log_files=`ps aux | grep bash | grep runner|awk -F" " '{print $(NF-1)}'`
        [ -n "$local_file" ] && log_files=$local_file
        num=0
        for f in $log_files
        do
            total_times=`cat $f | grep "++++++Running"|wc -l`
            total_error=`cat $f | grep "iperf3 failed"|wc -l`
            first_error=`cat $f | grep "iperf3 failed" -A3 |head -3| grep "++++++Running"|tail -1| awk -F" " '{print $2}'`
	    [ -n "$first_error" ] && first_error=$((first_error - 1))
            last_error=`cat $f | grep "iperf3 failed" -A3 |tail -3| grep "++++++Running"|tail -1| awk -F" " '{print $2}'`
            [ -n "$last_error" ] && last_error=$((last_error - 1))
            [ -z "$last_error" ] && last_error=`cat $f | grep "iperf3 failed" -B5 |tail -5| grep "++++++Running"|tail -1| awk -F" " '{print $2}'`
            echo -e "\033[31mShow $total_error errors in $f:\033[0m" 
            echo -e "\033[31m                               total times: $total_times\033[0m" 
            echo -e "\033[31m                               first time at: ${first_error:-0} mintue\033[0m" 
            echo -e "\033[31m                               last time at : ${last_error:-0} mintue\033[0m"
            num=$((num + 1))
        done
        echo "======================================================================================"
        [ -z "$local_file" ] && {
        ps aux | grep bash | grep runner| grep -v grep
        ps aux | grep iperf3| grep -v grep| grep -v "S+"
        ps aux | grep bash |grep monitor |grep -v grep
        }

        [ $num -le 2 ] && nn=10 || nn=3
        [ $num -gt 4 ] && log_files=
        for f in $log_files
        do
           echo
           echo -e "\033[34mIn $f >>>>>>>>>>>>>>>>>>>>\033[0m"
           tail -${nn} $f
        done
        [ x"$s_flag" != x"y" ] && l_flag="n" || ( sleep 5;
	                                          echo -e "\033[2J\033[0m" ;
	                                          echo -e "\033[200A\033[0m";) 
    done 
}

#Check the connectivity of the server in conf
checker()
{
    echo -e "\033[34mCheck the connectivity...\033[0m"
    [ -f ./conf ] || { echo -e "\033[31mThe config file is not existing\033[0m";gen_conf; exit 1;}
    cat ./conf | grep -v "^#" | uniq -w 15 > ./conf.tmp
    while read line
    do
        com_f=`echo $line |grep "^#" > /dev/null 2>&1;echo $?`
        server_ip=`echo $line |grep -v "^#" | awk -F" " '{print $1}'`
        account=`echo $line |grep -v "^#" | awk -F" " '{print $4}'` 
        [ $com_f -eq 0 ] && continue
        [ -z "$account" -o -z "$server_ip" ] && { echo "Null for ip or account"; continue;}
        echo -e "\033[34m>>>>On $account at $server_ip:\033[0m"
        echo "Try to ping $server_ip ..."
        ping $server_ip -c 5 && echo -e "\033[32mSuccess to ping $server_ip\033[0m"|| { echo -e "\033[31mFailed to ping $server_ip\033[0m"; exit 1;}
        ssh-keygen -R $server_ip &> /dev/null
        ssh -n -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=0 ${account}@$server_ip "ls -l" > tmp.log 2>&1
        r=`cat tmp.log | grep -E "Permission denied|Connection refused|Too many authentication failures" > /dev/null 2>&1;echo $?`
        [ $r -ne 0 ] && echo -e "\033[32mSuccess to login without password!!!\033[0m" || { rm -rf tmp.log; echo -e "\033[31mNo-password login failed, please use --key to autossh\033[0m";continue;}
        rm -rf tmp.log
    done < ./conf.tmp
    rm -rf ./conf.tmp
}

#By now, only support 4 level for running iperf3, for level 1/2/3,the duration is hour.
#level 1, just run iperf3 with total time once; 
#level 2, 3600 seconds to for each time;
#level 3, 60 seconds to for each time, 
#level 4, 60 seconds to for each time, the duration is mintue
check_level()
{
    [ -z "$level" ] && { echo -e "\033[31mPlease set value for level\033[0m"; exit 1;}
    if [ $level -eq 1 ]; then
        iperf_time=$(($duration * 3600 ))
        loop_time=1
    elif [ $level -eq 2 ];then
        iperf_time=3600
        loop_time=$duration
    elif [ $level -eq 3 ];then
        iperf_time=60
        loop_time=$(($duration * 60))
        t_time=
    elif [ $level -eq 4 ];then
        iperf_time=60
        loop_time=$duration
    else
        echo -e "\033[31mWrong level value!!!\033[0m"
        exit 1
    fi
}

#Get the default account from conf file
default_acc()
{
    #get the default account
    [ -f ./conf ] || { echo -e "\033[31mThe config file is not existing\033[0m";gen_conf; exit 1;}
    account=`cat ./conf |grep -v "^#" | awk -F" " '{print $4}'|head -1`
    [ -z "$account" ] && { echo -e "\033[31mNo default account for remote server\033[0m"; exit 1;}
}
 
monitor()
{
cat <<"EOF" > monitor.sh
#!/bin/bash -

log_file=$1
iperf_time=$2
loop_time=$3
[ $loop_time -gt 1 ] && { rm -rf monitor.sh 2>/dev/null; exit 0; }
[ $iperf_time -le 86400 ] && { rm -rf monitor.sh 2>/dev/null; exit 0; }
m_start_time=`head $log_file |head -1| awk -F" " '{print $1}'`
while true
do
    sleep $iperf_time
    m_start_time=`head $log_file |head -1| awk -F" " '{print $1}'`
    m_current_time=`date +%s%N`
    m_elapsing_time=$(($(($m_current_time - $m_start_time ))/1000000000))
    #[ $iperf_time -lt $m_elapsing_time ] && { kill -15 `ps aux | grep " iperf3 " | awk -F" " '{print $2}' ` > /dev/null 2>&1 ; break; }
    { kill -15 `ps aux | grep " iperf3 " | awk -F" " '{print $2}' ` > /dev/null 2>&1 ; break; }
done 
rm -rf monitor.sh 2>/dev/null
EOF
}

#main
[ -z $1 ] && { usage; exit 1;} 


temp=`echo $1 |sed 's/[0-9]//g'`
if [ -z $temp ];then
    duration=$1
    level=$2
    shift
    shift
    eval set -- "`getopt -o d:t:hf: -al conf,key,check,kill,help,status,loop -- "$@"`"
else
    eval set -- "`getopt -o d:t:hf: -al conf,key,check,kill,help,status,loop -- "$@"`"
fi

while true ; do
    case "$1" in
         -d)
              duration=$2
              shift 2;;
        -t)
              level=$2
              shift 2;;
        --key) 
              parse_conf
              default_acc
              keys1
              [ -z "$duration" -o -z "$level" ] && exit 0
              break;;
        --conf) 
              gen_conf
              exit 0;;
        --status)
              s_flag="n"
	      shift 1
	      [ -n "$2" ] && opts=`ls -lrt| grep ".._.._...log"|tail -2|awk -F" " '{print $9}'`
              local_status "$opts"
              exit 0;;
        -f)
              s_flag="n"
	      shift 1
	      opts=`echo $@| sed "s/\-\-//g"`
              local_status "$opts"
              exit 0;;
        --loop)
              s_flag="y"
	      echo -e "\033[2J\033[0m" 
	      echo -e "\033[200A\033[0m" 
              local_status
              exit 0;;
        --check) 
              parse_conf
              default_acc
              checker
              exit 0;;
        --kill)
              local_killer
              exit 0;;
         -h|--help)
              usage
              exit 0 ;;
        --) shift ; break ;;

        *) echo -e "\033[31mError! Invalid option \"$1\"\033[0m" ; exit 1 ;;
    esac

done

parse_conf
default_acc
check_level
checker
sponser_server
sponser_client

echo -e "\033[34mThe processes are running in background, please use bash $0 --status/--loop to track them.\033[0m"
echo "Done"
