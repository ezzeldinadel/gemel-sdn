
apt-get update

apt-get install -y git automake autoconf gcc uml-utilities libtool build-essential git pkg-config linux-headers-`uname -r`


apt-get install -y python-simplejson python-qt4 python-twisted-conch automake autoconf gcc uml-utilities libtool build-essential git pkg-config

apt install -y iperf

wget https://www.openvswitch.org/releases/openvswitch-2.11.0.tar.gz
tar xvf openvswitch-2.11.0.tar.gz

cd openvswitch-2.11.0

./boot.sh
./configure --with-linux=/lib/modules/`uname -r`/build

make
make install
make modules_install


modprobe openvswitch

mkdir -p /usr/local/etc/openvswitch

ovsdb-tool create /usr/local/etc/openvswitch/conf.db vswitchd/vswitch.ovsschema

mkdir -p $(dirname /usr/local/var/run/openvswitch/ovsdb-server.pid.tmp)
mkdir -p $(dirname /usr/local/var/run/openvswitch/ovsdb-server.pid.tmp)

ovsdb-server -v --log-file --pidfile --remote=punix:/usr/local/var/run/openvswitch/db.sock # --detach


ovs-vswitchd --pidfile # --detach

ovs-vsctl --no-wait init

ovs-vsctl show

# ============================================================================ #

ovs-vsctl add-br br0
ovs-vsctl add-port br0 br0-int -- set interface br0-int type=internal
ovs-vsctl add-port br0 vx1 -- set interface vx1 type=vxlan options:remote_ip=$peer_ip options:key=2001
ifconfig br0-int 210.0.0.101 mtu 1450 up

 












