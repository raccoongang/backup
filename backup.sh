#!/bin/bash

BACKUP_PATH='/edx/var/backup/'

DATABASES=( 'edxapp' 'xqueue' 'reports' 'ora' 'edx_notes_api' 'analytics-api' )

INSTANCE_ID=$(ec2metadata | grep -Po 'instance-id:\s*\K.+')

VOLUME_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | grep -Pzo 'DeviceName": "/dev/sdc",[^"]+"Ebs": {[^}]+"VolumeId": "\K.+(?="[^}]+})')

sudo /etc/init.d/nginx stop
cd /var/www
sudo ./webserver.py &
PID=$!
cd -

sudo /edx/bin/supervisorctl stop all
sudo service mongod stop

for database in $DATABASES
do
    sudo mysqldump $database > "$BACKUP_PATH$database.sql"
done

sudo service mysql stop

snapshot_id=$(aws ec2 create-snapshot --volume-id $VOLUME_ID --description "EDX `date +%Y-%m-%d` backup" | grep -Po '"SnapshotId": "\K.+(?=")')
echo "SNAPSHOT ID: $snapshot_id"

start_time=$(date +%s)

while :
do
    status=$(aws ec2 describe-snapshots --snapshot-ids "$snapshot_id" | grep -Po '"State": "\K.+(?=")')
    work_time=$((`date +%s`-$start_time))

    echo "STATUS: $status"
    if [[ "$status" = 'completed' ]]
    then
        break
    elif (( work_time > 3600 ))
    then
        break
    fi

    sleep 10
done

sudo service mysql start
sudo service mongod start
sudo /edx/bin/supervisorctl start all

sleep 10
cd /var/www
sudo kill $PID
sudo /etc/init.d/nginx start
cd -

delete_snapshots=$(aws ec2 describe-snapshots --filters Name=description,Values=EDX*backup Name=status,Values=completed | python -c "import sys, json; res = json.loads(sys.stdin.read())['Snapshots']; res.sort(key=lambda x: x['StartTime']); print ' '.join([i['SnapshotId'] for i in res[:-5]])")
echo "Deleting: $delete_snapshots"

for snap in $delete_snapshots
do
    aws ec2 delete-snapshot --snapshot-id $snap
done