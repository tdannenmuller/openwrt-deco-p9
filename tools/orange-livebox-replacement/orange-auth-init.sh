#!/bin/sh /etc/rc.common
# Installation on the Deco:
#   ln -s /etc/config/orange-auth-init.sh /etc/init.d/orange-auth
#   /etc/init.d/orange-auth enable
START=09
start() {
    /etc/config/orange-gen-auth.sh
}
