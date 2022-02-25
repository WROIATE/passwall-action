#!/bin/bash

export PKG_SOURCE_DATE_EPOCH="$(date "+%s")"

BASE_DIR=$(
    cd $(dirname $0)
    pwd
)
PKG_NAME="$1"
PKG_DIR="$BASE_DIR/$1"
TEMP_DIR="$(mktemp -d -p $PKG_DIR)"
TEMP_PKG_DIR="$TEMP_DIR/$PKG_NAME"
mkdir -p "$TEMP_PKG_DIR/CONTROL/"
mkdir -p "$TEMP_PKG_DIR/usr/lib/lua/luci/"
CONFFILES="/etc/config/passwall_server
/usr/share/passwall/rules/direct_host
/usr/share/passwall/rules/direct_ip
/usr/share/passwall/rules/proxy_host
/usr/share/passwall/rules/proxy_ip
/usr/share/passwall/rules/block_host
/usr/share/passwall/rules/block_ip
/usr/share/passwall/rules/lanlist_ipv4
/usr/share/passwall/rules/lanlist_ipv6"

function get_mk_value() {
    awk -F "$1:=" '{print $2}' "$PKG_DIR/Makefile" | xargs
}

function get_mk_depends() {
    echo $(cat $PKG_DIR/Makefile | grep -o '\+.*' | sed 's/\\//g' | sed ':a;N;s/\n//g;ta' | sed 's/[[:space:]]+/,/g' | sed 's\+\\g' | sed 's/PACKAGE_$(PKG_NAME)\w*://g')
}

PKG_VERSION="$(get_mk_value "PKG_VERSION")-$(get_mk_value "PKG_RELEASE")"
cp -fpR "$PKG_DIR/luasrc"/* "$TEMP_PKG_DIR/usr/lib/lua/luci/"
cp -fpR "$PKG_DIR/root"/* "$TEMP_PKG_DIR/"

echo -e "$CONFFILES" >"$TEMP_PKG_DIR/CONTROL/conffiles"

cat >"$TEMP_PKG_DIR/CONTROL/control" <<-EOF
	Package: $PKG_NAME
	Version: $PKG_VERSION
	Depends: libc,$(get_mk_depends | xargs | tr " +" ", ")
	Source: https://github.com/xiaorouji/openwrt-passwall
	SourceName: $PKG_NAME
	Section: luci
	SourceDateEpoch: $PKG_SOURCE_DATE_EPOCH
	Architecture: all
	Installed-Size: TO-BE-FILLED-BY-IPKG-BUILD
	Description:  LuCI support for PassWall
EOF

echo -e '#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@' >"$TEMP_PKG_DIR/CONTROL/postinst"
chmod 0755 "$TEMP_PKG_DIR/CONTROL/postinst"

echo -e "[ -n "\${IPKG_INSTROOT}" ] || {
	(. /etc/uci-defaults/$PKG_NAME) && rm -f /etc/uci-defaults/$PKG_NAME
	rm -f /tmp/luci-indexcache
	rm -rf /tmp/luci-modulecache/
	exit 0
}" >"$TEMP_PKG_DIR/CONTROL/postinst-pkg"
chmod 0755 "$TEMP_PKG_DIR/CONTROL/postinst-pkg"

echo -e '#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@' >"$TEMP_PKG_DIR/CONTROL/prerm"
chmod 0755 "$TEMP_PKG_DIR/CONTROL/prerm"

curl -fsSL "https://raw.githubusercontent.com/openwrt/openwrt/master/scripts/ipkg-build" -o "$TEMP_DIR/ipkg-build"
chmod 0755 "$TEMP_DIR/ipkg-build"
"$TEMP_DIR/ipkg-build" -m "" "$TEMP_PKG_DIR" "$TEMP_DIR"

mv "$TEMP_DIR/${PKG_NAME}_${PKG_VERSION}_all.ipk" "$BASE_DIR"
rm -rf "$TEMP_DIR"
