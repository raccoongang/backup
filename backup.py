#!/usr/bin/python

import os
import sys
import json
import time
from datetime import datetime

AWS = '/usr/local/bin/aws'

INSTANCE_ID = os.popen('ec2metadata | grep -Po "instance-id:\s*\K.+"').read()

res = os.popen('{} ec2 describe-instances --instance-ids {}'.format(AWS, INSTANCE_ID)).read()
instance = json.loads(res)
VOLUME_ID = instance['Reservations'][0]['Instances'][0]['BlockDeviceMappings'][0]['Ebs']['VolumeId']

os.system('sudo /edx/bin/supervisorctl stop all')
os.system('sudo service mongod stop')
os.system('sudo service mysql stop')

res = os.popen('{} ec2 create-snapshot --volume-id {} --description "EDX `date +%Y-%m-%d` backup"'.format(AWS, VOLUME_ID)).read()
snapshot = json.loads(res)
start_time = time.time()
snapshot_id = snapshot['SnapshotId']

while True:
    res = os.popen('{} ec2 describe-snapshots --snapshot-ids "{}"'.format(AWS, snapshot_id)).read()
    snapshot = json.loads(res)

    state = snapshot['Snapshots'][0]['State']
    print 'Snapshot status is "{}"'.format(state)

    if state == 'completed' or (time.time() - start_time) > 3600:
        break

    time.sleep(10)

os.system('sudo service mysql start')
os.system('sudo service mongod start')
os.system('sudo /edx/bin/supervisorctl start all')

res = os.popen('{} ec2 describe-snapshots --filters Name=description,Values=EDX*backup Name=status,Values=completed'.format(AWS)).read()
snapshots = json.loads(res)['Snapshots']
snapshots.sort(key=lambda x: x['StartTime'])

for snap in snapshots[:-7]:
    print 'Delete shapshot "{}" ...'.format(snap['SnapshotId'])
    os.system('{} ec2 delete-snapshot --snapshot-id {}'.format(AWS, snap['SnapshotId']))
