#!/bin/bash
# Script performs non-interactive installation of Oracle XE 10g on Debian
#
# Based on oracle10g-update.sh from HTSQL project:
# https://bitbucket.org/prometheus/htsql
#
# Modified by Mateusz Loskot <mateusz@loskot.net>
# Changes:
# - Add fake swap support (backup /usr/bin/free manually anyway!)
#
# Modified by Peter Butkovic <butkovic@gmail.com> to enable i386 install on amd64 architecture (precise 64)
# based on: http://www.ubuntugeek.com/how-to-install-oracle-10g-xe-in-64-bit-ubuntu.html
#
# set -ex

#
# Utilities
#
function free_backup()
{
    # Multiple copies to be on safe side
    sudo cp /usr/bin/free /root
    sudo mv /usr/bin/free /usr/bin/free.original
}

function free_restore()
{
    sudo cp /usr/bin/free.original /usr/bin/free
}

# Install fake free
# http://www.axelog.de/2010/02/7-oracle-ee-refused-to-install-into-openvz/
free_backup

sudo tee /usr/bin/free <<EOF > /dev/null
#!/bin/sh
cat <<__eof
             total       used       free     shared    buffers     cached
Mem:       1048576     327264     721312          0          0          0
-/+ buffers/cache:     327264     721312
Swap:      2000000          0    2000000
__eof
exit
EOF

sudo chmod 755 /usr/bin/free

#
# ok, bc, is the dependency that is required by DB2 as well => let's remove it from oracle xe dependencies and provide 64bit one only
#
sudo apt-get update

# Install the Oracle 10g dependant packages
sudo apt-get install -qq --allow-unauthenticated libc6:i386
# travis needs the "apt-transport-https" to enable https transport
sudo apt-get install -qq bc apt-transport-https

wget https://oss.oracle.com/debian/dists/unstable/main/binary-i386/libaio_0.3.104-1_i386.deb
sudo dpkg -i --force-architecture libaio_0.3.104-1_i386.deb

wget  -q https://oss.oracle.com/debian/dists/unstable/non-free/binary-i386/oracle-xe-universal_10.2.0.1-1.1_i386.deb
mv oracle-xe-universal_10.2.0.1-1.1_i386.deb /tmp/

# remove bc from the dependencies of the oracle-xe-universal package (to keep 64bit one installed)
mkdir /tmp/oracle_unpack
dpkg-deb -x /tmp/oracle-xe-universal_10.2.0.1-1.1_i386.deb /tmp/oracle_unpack
cd /tmp/oracle_unpack
dpkg-deb --control /tmp/oracle-xe-universal_10.2.0.1-1.1_i386.deb
sed -i "s/,\ bc//g" /tmp/oracle_unpack/DEBIAN/control
mkdir /tmp/oracle_repack
dpkg -b /tmp/oracle_unpack /tmp/oracle_repack/oracle-xe-universal_fixed_10.2.0.1-1.1_i386.deb

# install Oracle 10g with the fixed dependencies, to prevent i386/amd64 conflicts on bc package
sudo dpkg -i --force-architecture /tmp/oracle_repack/oracle-xe-universal_fixed_10.2.0.1-1.1_i386.deb

# Fix the problem when the configuration script eats the last
# character of the password if it is 'n': replace IFS="\n" with IFS=$'\n'.
sudo sed -i -e s/IFS=\"\\\\n\"/IFS=\$\'\\\\n\'/ /etc/init.d/oracle-xe

# change shebang of nls_lang.sh
sudo sed -i 's/#!\/bin\/sh/#!\/bin\/bash/' /usr/lib/oracle/xe/app/oracle/product/10.2.0/server/bin/nls_lang.sh

# Configure the server; provide the answers for the following questions:
# The HTTP port for Oracle Application Express: 8080
# A port for the database listener: 1521
# The password for the SYS and SYSTEM database accounts: admin
# Start the server on boot: yes
sudo /etc/init.d/oracle-xe configure <<END
8080
1521
admin
admin
y
END

# Load Oracle environment variables so that we could run `sqlplus`.
. /usr/lib/oracle/xe/app/oracle/product/10.2.0/server/bin/oracle_env.sh

# Increase the number of connections.
echo "ALTER SYSTEM SET PROCESSES=40 SCOPE=SPFILE;" | \
sqlplus -S -L sys/admin AS SYSDBA

# Set Oracle environment variables on login.
cat <<END >>~/.bashrc

. /usr/lib/oracle/xe/app/oracle/product/10.2.0/server/bin/oracle_env.sh
END

free_restore

# build php module
git clone https://github.com/DeepDiver1975/oracle_instant_client_for_ubuntu_64bit.git instantclient
cd instantclient
sudo bash -c 'printf "\n" | python system_setup.py'

sudo mkdir -p /usr/lib/oracle/11.2/client64/rdbms/
sudo ln -s /usr/include/oracle/11.2/client64/ /usr/lib/oracle/11.2/client64/rdbms/public

sudo apt-get install -qq --allow-unauthenticated libaio1
if [[ " 7 7.1 7.2 7.3 7.4 " =~ .*\ $TRAVIS_PHP_VERSION\ .* ]] ; then
  printf "/usr/lib/oracle/11.2/client64\n" | pecl install oci8
else
  printf "/usr/lib/oracle/11.2/client64\n" | pecl install oci8-2.0.10
fi

cat ~/.phpenv/versions/$(phpenv version-name)/etc/php.ini

# add travis user to oracle user group - necessary for execution of sqlplus
sudo adduser travis dba
