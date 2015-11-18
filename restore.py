#!/usr/bin/python
import os
import re
import json
import time
from datetime import datetime

time.sleep(10)
# Comment the autostart this script
os.system("sudo sed -ri 's/sudo\s+-u\s+ubuntu\s+\/home\/ubuntu\/restore\.py/#sudo -u ubuntu \/home\/ubuntu\/restore\.py/g' /etc/rc.local")

# Get this instance id
r = re.compile('(availability-zone:\s*(?P<availability_zone>.+)|instance-id:\s*(?P<instance_id>.+))')
metadata = os.popen('ec2metadata').read()
res = r.finditer(metadata)

INSTANCE_ID = None
AVAILABILITY_ZONE = None
for i in res:
    d = i.groupdict()
    INSTANCE_ID = d['instance_id'] or INSTANCE_ID
    AVAILABILITY_ZONE = d['availability_zone'] or AVAILABILITY_ZONE

if not INSTANCE_ID:
    print 'Error get instance id'
    exit(1)

# Get last snapshot
command = 'aws ec2 describe-snapshots --filters Name=description,Values=EDX*backup Name=status,Values=completed'
result = os.popen(command)
snapshots = json.loads(result.read())['Snapshots']

snapshots.sort(key=lambda s: datetime.strptime(s['StartTime'], '%Y-%m-%dT%H:%M:%S.000Z'))

last_snapshot = snapshots[-1]

# Create volume from last snapshot
res = os.popen(('aws ec2 create-volume --snapshot-id {} --availability-zone {} '
          '--volume-type "standard"').format(last_snapshot['SnapshotId'], AVAILABILITY_ZONE))

vol_id = json.loads(res.read())['VolumeId']

# Get now attached volume id
res = os.popen('aws ec2 describe-instances --instance-ids {}'.format(INSTANCE_ID))

discs = json.loads(res.read())['Reservations'][0]['Instances'][0]['BlockDeviceMappings']
old_vol = filter(lambda d: d['DeviceName'] == '/dev/sdc', discs)[0]

print 'OLD VOLUME ID: ', old_vol['Ebs']['VolumeId']
print 'NEW VOLUME ID: ', vol_id

# Whait until volume is created
attempt = 0
while True:
    res = os.popen('aws ec2 describe-volumes --volume-ids {}'.format(vol_id))
    vol_status = json.loads(res.read())['Volumes'][0]['State']
    print 'VLO: ', vol_id, vol_status
    if vol_status == 'available' or attempt > 90:
        break
    attempt += 1
    time.sleep(10)

# Kill all process that used /edx
os.system('sudo fuser -km /edx')
# Umount /edx
os.system('sudo umount -l /edx')
os.system('mount')
time.sleep(5)

# Detach old volume
os.system('aws ec2 detach-volume --volume-id {} --force'.format(old_vol['Ebs']['VolumeId']))

# whait until old volume is deattached
attempt = 0
while True:
    res = os.popen('aws ec2 describe-volumes --volume-ids {}'.format(old_vol['Ebs']['VolumeId']))
    vol_status = json.loads(res.read())['Volumes'][0]['State']
    print 'VOL: ', old_vol['Ebs']['VolumeId'], vol_status
    if vol_status == 'available' or attempt > 90:
        break
    attempt += 1
    time.sleep(10)

time.sleep(5)

# Attach new volume
os.system(('aws ec2 attach-volume --volume-id {} --device /dev/sdc '
          '--instance-id {}').format(vol_id, INSTANCE_ID))

# Stop server
os.system('aws ec2 stop-instances --instance-ids {}'.format(INSTANCE_ID))
