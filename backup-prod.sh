#!/bin/bash

LANG=en_US.utf8

if [ $# != 3 ];then
   echo "Usage: "$0" count freq backup_type"
   exit 1
fi

# input variables:

count=$1
freq=$2
backup_type=$3

if [[ "$backup_type" = "daily" ]]
then
    days=$(($count*$freq))
elif [[ "$backup_type" = "weekly" ]]
then
    days=$((7*$count*$freq))
elif [[ "$backup_type" = "monthly" ]]
then
    days=$((30*$count*$freq))
else
    echo "Wrong backup type. Possible values: daily,weekly,monthly"
    exit 1
fi

# global variables

prkey='/root/.ssh/backup'
bkuserid='root'
bkhost='51.254.188.13'
timemark=`date +%d%m%Y.%H%M`
host=`hostname`
pathbkfiles='/backup/'$backup_type'/'$host'/f'
pathdbfiles='/backup/'$backup_type'/'$host'/d'
slack_token=""

# list of directories and files for backup separated by space (dirs='/dir1 /dir2 /dir3')
dirs=''
# list of pg databases and files for backup separated by space (pgdbs='db1 db2 db3')
pgdbs=''
# list of mysql databases and files for backup separated by space (mysqldbs='db1 db2 db3')
mysqldbs=''

# functions

cleanup () {

    for i in `ssh -i $prkey $bkuserid@$bkhost "find $pathbkfiles -type f -mtime +$days"`; do
        ssh -i $prkey $bkuserid@$bkhost "rm -f $i"
    done
    for i in `ssh -i $prkey $bkuserid@$bkhost "find $pathdbfiles -type f -mtime +$days"`; do
        ssh -i $prkey $bkuserid@$bkhost "rm -f $i"
    done

}

backup_files () {

    ssh -i $prkey $bkuserid@$bkhost "mkdir -p $pathbkfiles" > /dev/null 2>&1
    tar zcf - $dirs | ssh -i $prkey $bkuserid@$bkhost "cat > $pathbkfiles/$host.$timemark.tar.gz"

}

backup_databases_pg () {

    ssh -i $prkey $bkuserid@$bkhost "mkdir -p $pathdbfiles" > /dev/null 2>&1
    for i in $pgdbs; do
        pg_dump --host=$PGHOST --username=$PGUSER $i | gzip -c | ssh -i $prkey $bkuserid@$bkhost "cat > $pathdbfiles/theme.$host.$timemark.pgsql.gz"
    done
}

backup_databases_mysql () {

    ssh -i $prkey $bkuserid@$bkhost "mkdir -p $pathdbfiles" > /dev/null 2>&1
    for i in $mysqldbs; do
        mysqldump $i | gzip -c | ssh -i $prkey $bkuserid@$bkhost "cat > $pathdbfiles/$i.$host.$timemark.mysql.gz"
    done

}

backup_databases_mongo () {

    if [ -d /tmp/mongo ]
    then
        echo "Cleaning tmp directory"
        rm -rf /tmp/mongo
    fi
    ssh -i $prkey $bkuserid@$bkhost "mkdir -p $pathdbfiles" > /dev/null 2>&1
    mkdir /tmp/mongo > /dev/null 2>&1
    mongodump --out /tmp/mongo
    tar zcf - /tmp/mongo | ssh -i $prkey $bkuserid@$bkhost "cat > $pathdbfiles/mongo.$host.$timemark.tar.gz"
    rm -rf /tmp/mongo

}

# logic:

#cleanup
#backup_files
#backup_databases_mysql
#PGHOST=
#PGUSER=
#export PGPASSWORD=
#backup_databases_pg
#backup_databases_mongo
ssh -i $prkey $bkuserid@$bkhost "rsync -av --delete /backup/ /mnt/s3/ > /dev/null 2>&1"
post_to_slack "Backup process has been finished on $host" "INFO"
curl -X POST --data 'payload={"channel": "#script-channel", "username": "Backup", "text": "'"$backup_type backup process has been finished on $host"'"}' https://hooks.slack.com/services/$slack_token
exit 0
