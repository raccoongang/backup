#!/usr/bin/python

import os

os.system("sudo sed -ri 's/sudo\s+-u\s+ubuntu\s+\/home\/ubuntu\/restore_db\.py/#sudo -u ubuntu \/home\/ubuntu\/restore_db\.py/g' /etc/rc.local")

databases = ('edxapp', 'xqueue', 'reports', 'ora', 'edx_notes_api', 'analytics-api')

os.chdir('/edx/var/backup/')

for db in databases:
    os.system('sudo mysql {} < {}.sql'.format(db))

#os.system('sudo reboot')
