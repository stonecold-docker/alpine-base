#!/usr/bin/env bash

if [ "${EUID}" != "0" ]; then
	sudo "${0}" "${@}"
	exit $?
fi

LANG="C"
LC_ALL="C"
IS_DOCKER=N
if [ -e /.dockerenv -o ! -z "${BUILD_TAG}" ]; then
	IS_DOCKER=Y
fi

echo_red() {
	echo -e "\e[0;31m${1}\e[0m"
}

echo_green() {
	echo -e "\e[0;32m${1}\e[0m"
}

echo_blue() {
	echo -e "\e[0;34m${1}\e[0m"
}

fn_run_docker() {
	if ! docker info &> /dev/null ; then
		echo "Cannot execute docker (1)"
		exit 1
	fi

	local dockername=alpine-dev-docker-dist-${RANDOM}
	local dockerdir=/build
	local workdir="$(pwd)"
	local workscript="${workdir}/$(basename "${0}")"
	local user=$(id -n -u)
	local uid=$(id -u)
	local gid=$(id -g)
	local lang=${LANG:-ko_KR.UTF-8}
	local lc_all=${LC_ALL:-ko_KR.UTF-8}

	echo "Execute in docker"
	if [ "${DEBUG}" = "Y" ]; then
		echo "Arguments : $@"
	fi

	[ "${DEBUG}" = "Y" ] && set -x
	docker run  --rm --sig-proxy=false --privileged -e RUN_USER_NAME=${user} -e RUN_USER_UID=${uid} -e RUN_USER_GID=${gid} -e LANG=${lang} -e LC_ALL=${lc_all} -v ${workdir}:${dockerdir} -v ${workscript}:/usr/local/bin/docker-run-alt -v ${workdir}/extras/qemu-aarch64-static:/usr/bin/qemu-aarch64-static  -v ${workdir}/extras/qemu-arm-static:/usr/bin/qemu-arm-static -h ${dockername} --name ${dockername} -e DOCKER_WORKDIR=${dockerdir} forumi0721/alpine-dev:latest - "${@}"
	[ "${DEBUG}" = "Y" ] && set +x
}

fn_usage() {
	echo "Usage : $(basename "${0}") [-d distro] [-a architecture] [-o output] [-l locale] [-z timezone] [--include include packages] [--exclud exclude pacakges] [-m] [-s] [-i] [-p] [-q]"
	echo "          [-d distro] : alpine,debian,ubuntu,entware,busybox,arch"
	echo "          [-a architecture] : x64(x86_64),armv7(armhf),aarch64(arm64) (default : x64)"
	echo "          [-e edition] : debian, ubuntu option"
	echo "          [-o output] : output dir (default : distro_archtecture)"
	echo "          [-l locale] : locale (default : ko_KR.UTF-8)"
	echo "          [-z timezone] : timezone (default : Asia/Seoul)"
	echo "          [--include include pacakges] : include pacakges (default : null)"
	echo "          [--exclude exclude pacakges] : exclude pacakges (default : null)"
	echo "          [-m] : make image"
	echo "          [-u] : update umage"
	echo "          [-i] : import docker"
	echo "          [-p] : push image"
	echo "          [-q] : quiet"
	echo ""
	echo "          docker additional options:"
	echo "                [-n name:tag] : docker image name:tag"
	exit 1
}

fn_target_unmount() {
if [ -e "${TARGET_OUTPUT}" ]; then
	if [ ! -z "$(mount | grep "on ${TARGET_OUTPUT}.* type")" ]; then
		umount -R "${TARGET_OUTPUT}" || true
		for a in $(mount | grep "on ${TARGET_OUTPUT}.* type" | sed 's/^.*on \(.*\) type.*$/\1/g')
		do
			umount ${a} || true
		done
		if [ ! -z "$(mount | grep "on ${TARGET_OUTPUT}.* type")" ]; then
			echo "Cannot remove ${TARGET_OUTPUT}"
			exit 1
		fi
	fi
fi
}

fn_make_busybox() {
	echo "Bootstrap"

	# Need busbox for bootstrapping
	local ALPINE_ARCH=${TARGET_ARCH}
	ALPINE_ARCH=${ALPINE_ARCH/x64/x86_64}
	ALPINE_ARCH=${ALPINE_ARCH/aarch64/aarch64}
	ALPINE_ARCH=${ALPINE_ARCH/armv7/armv7}

	local busybox="https://mirror.xtom.com.hk/alpine/latest-stable/main/${ALPINE_ARCH}/$(wget https://mirror.xtom.com.hk/alpine/latest-stable/main/${ALPINE_ARCH}/ -q -O - | grep busybox-static | sed -e 's/^.*href="\([^"]*\)".*$/\1/g')"
	wget "${busybox}" -q -O - | tar zxf - -C ${TARGET_OUTPUT}/
	rm -rf ${TARGET_OUTPUT}/.PKGINFO ${TARGET_OUTPUT}/.SIGN.RSA*

	for x in bin dev etc home lib opt proc root run sbin sys tmp var usr
	do
		mkdir -p ${TARGET_OUTPUT}/${x}
	done
	chmod 1777 ${TARGET_OUTPUT}/tmp
	for x in bin lib local sbin share
	do
		mkdir -p ${TARGET_OUTPUT}/usr/${x}
	done
	for x in bin lib sbin share
	do
		mkdir -p ${TARGET_OUTPUT}/usr/local/${x}
	done
	for x in log
	do
		mkdir -p ${TARGET_OUTPUT}/var/${x}
	done

	#qemu
	mkdir -p ${TARGET_OUTPUT}/usr/bin
	if [ ! -z "${TARGET_QEMU}" ]; then
		mkdir -p ${TARGET_OUTPUT}/usr/bin
		cp extras/${TARGET_QEMU} ${TARGET_OUTPUT}/usr/bin/

		chroot_cmd() {
			#QEMU_EXECVE=1 chroot "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve "${@}"
			chroot "${TARGET_OUTPUT}" "${@}"
		}
	else
		chroot_cmd() {
			chroot "${TARGET_OUTPUT}" "${@}"
		}
	fi

	#resolve
	cat <<- EOF > ${TARGET_OUTPUT}/etc/resolv.conf
	nameserver 1.1.1.1
	nameserver 1.0.0.1
	EOF

	cat <<- EOF > ${TARGET_OUTPUT}/etc/passwd
	root:x:0:0:Root:/root:/bin/sh
	nobody:x:65534:65534:nobody:/:/sbin/nologin
	EOF
	cat <<- EOF > ${TARGET_OUTPUT}/etc/group
	root:x:0:root
	users:x:100:
	nobody:x:65534:
	EOF
	cat <<- EOF >> ${TARGET_OUTPUT}/etc/os-release
	NAME=busybox
	ID=busybox
	EOF
	cat <<- 'EOF' >> ${TARGET_OUTPUT}/etc/profile
	export CHARSET=UTF-8
	export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	export PAGER=less
	export PS1='\h:\w\$ '
	umask 022

	for script in /etc/profile.d/*.sh ; do
		if [ -r $script ] ; then
			. $script
		fi
	done
	EOF
	chmod 755 ${TARGET_OUTPUT}/etc/profile
	mkdir -p ${TARGET_OUTPUT}/etc/profile.d

	#timezone
	if [ -e ${TARGET_OUTPUT}/usr/share/zoneinfo/${TARGET_TIMEZONE} ]; then
		ln -s /usr/share/zoneinfo/${TARGET_TIMEZONE} ${TARGET_OUTPUT}/etc/localtime
	elif [ -e /usr/share/zoneinfo/${TARGET_TIMEZONE} ]; then
		cat /usr/share/zoneinfo/${TARGET_TIMEZONE} > ${TARGET_OUTPUT}/etc/localtime
	elif [ -e /etc/zoneinfo/${TARGET_TIMEZONE} ]; then
		cat /etc/zoneinfo/${TARGET_TIMEZONE} > ${TARGET_OUTPUT}/etc/localtime
	fi

	chroot_cmd /bin/busybox.static sh -c "/bin/busybox.static --install -s ; /bin/busybox.static add-shell /bin/sh"


	echo "Clearing"

	echo

	fn_make_common
}

fn_make_alpine() {
	echo "Bootstrap"

	#local ALPINE_DIST=edge
	#local ALPINE_DIST=v3.8
	#ALPINE_DIST="$(curl -sSL http://dl-cdn.alpinelinux.org/alpine | grep '<a href="v' | tail -1 | sed -e 's/^<a href="\(.*\)\/">.*$/\1/g')"
	#local ALPINE_DIST="${ALPINE_DIST:-latest-stable}"
	local ALPINE_DIST="${ALPINE_DIST:-edge}"
	echo "Current version : ${ALPINE_DIST}"

	local ALPINE_ARCH=${TARGET_ARCH}
	ALPINE_ARCH=${ALPINE_ARCH/x64/x86_64}
	ALPINE_ARCH=${ALPINE_ARCH/aarch64/aarch64}
	ALPINE_ARCH=${ALPINE_ARCH/armv7/armv7}

	#local ALPINE_MIRROR=http://dl-cdn.alpinelinux.org/alpine
	local ALPINE_MIRROR=http://mirror.xtom.com.hk/alpine
	#local ALPINE_MIRROR=http://dl-2.alpinelinux.org/alpine

	#qemu
	if [ ! -z "${TARGET_QEMU}" ]; then
		mkdir -p ${TARGET_OUTPUT}/usr/bin
		cp extras/${TARGET_QEMU} ${TARGET_OUTPUT}/usr/bin/

		run_cmd() {
			#QEMU_EXECVE=1 /usr/bin/${TARGET_QEMU} -execve "${@}"
			"${@}"
		}
		chroot_cmd() {
			#QEMU_EXECVE=1 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C LC_ALL=C chroot "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve "${@}"
			PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C LC_ALL=C chroot "${TARGET_OUTPUT}" "${@}"
		}
	else
		run_cmd() {
			"${@}"
		}
		chroot_cmd() {
			PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C LC_ALL=C chroot "${TARGET_OUTPUT}" "${@}"
		}
	fi
	local APK_VERSION="$(wget -q -O - ${ALPINE_MIRROR}/latest-stable/main/${ALPINE_ARCH}/APKINDEX.tar.gz | tar -Oxz | grep --text '^P:apk-tools-static$' -A1 | tail -n1 | cut -d: -f2)"
	wget ${ALPINE_MIRROR}/latest-stable/main/${ALPINE_ARCH}/apk-tools-static-${APK_VERSION}.apk -q -O - | tar -xz -C "${TARGET_OUTPUT}" sbin/apk.static  2>/dev/null

	run_cmd ${TARGET_OUTPUT}/sbin/apk.static --repository ${ALPINE_MIRROR}/latest-stable/main --no-cache --no-script --allow-untrusted --root "${TARGET_OUTPUT}" --initdb add busybox alpine-baselayout alpine-keys apk-tools libc-utils
	#for link in $(run_cmd "${TARGET_OUTPUT}"/bin/busybox --list-full); do
	#	[ -e "${TARGET_OUTPUT}"/$link ] || ln -s /bin/busybox "${TARGET_OUTPUT}"/${link}
	#done
	chroot_cmd /bin/busybox --install -s
	if [ "${ALPINE_DIST}" = "edge" ]; then
		run_cmd ${TARGET_OUTPUT}/sbin/apk.static --repository ${ALPINE_MIRROR}/edge/tesing --repository ${ALPINE_MIRROR}/edge/main --repository ${ALPINE_MIRROR}/edge/community --no-cache --allow-untrusted --root "${TARGET_OUTPUT}" --stdout --quiet fetch alpine-base | tar -zx -C "${TARGET_OUTPUT}" etc/
	else
		run_cmd ${TARGET_OUTPUT}/sbin/apk.static --repository ${ALPINE_MIRROR}/${ALPINE_DIST}/main --repository ${ALPINE_MIRROR}/${ALPINE_DIST}/community --no-cache --allow-untrusted --root "${TARGET_OUTPUT}" --stdout --quiet fetch alpine-base | tar -zx -C "${TARGET_OUTPUT}" etc/
	fi

	echo

	#echo "Create chroot envoronment"
	#mount -t proc /proc ${TARGET_OUTPUT}/proc/
	#mount --rbind /sys ${TARGET_OUTPUT}/sys/
	#mount --rbind /dev ${TARGET_OUTPUT}/dev
	#echo

	echo "Configuration"

	#mirror
	if [ "${ALPINE_DIST}" = "edge" ]; then
		#echo "Disable edge"
		echo "${ALPINE_MIRROR}/latest-stable/main" > ${TARGET_OUTPUT}/etc/apk/repositories
		echo "${ALPINE_MIRROR}/latest-stable/community" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "${ALPINE_MIRROR}/edge/main" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "${ALPINE_MIRROR}/edge/community" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "${ALPINE_MIRROR}/edge/testing" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "@stablemain ${ALPINE_MIRROR}/latest-stable/main" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "@stablecommunity  ${ALPINE_MIRROR}/latest-stable/community" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "@edgemain ${ALPINE_MIRROR}/edge/main" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "@edgecommunity ${ALPINE_MIRROR}/edge/community" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "@edgetesting ${ALPINE_MIRROR}/edge/testing" >> ${TARGET_OUTPUT}/etc/apk/repositories
	else
		echo "${ALPINE_MIRROR}/${ALPINE_DIST}/main" > ${TARGET_OUTPUT}/etc/apk/repositories
		echo "${ALPINE_MIRROR}/${ALPINE_DIST}/community" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "@${ALPINE_DIST}main ${ALPINE_MIRROR}/${ALPINE_DIST}/main" >> ${TARGET_OUTPUT}/etc/apk/repositories
		echo "@${ALPINE_DIST}community  ${ALPINE_MIRROR}/${ALPINE_DIST}/community" >> ${TARGET_OUTPUT}/etc/apk/repositories
	fi

	##pin musl
	#musl_ver="$(cat ${TARGET_OUTPUT}/lib/apk/db/installed | grep '^P:musl$' -A 10 | grep '^V:' | head -1 | sed -e 's/^V://g')"
	#if [ ! -z "${musl_ver}" ]; then
	#	sed -e '/^musl$/d' ${TARGET_OUTPUT}/etc/apk/world
	#	sed -e '/^musl-utils$/d' ${TARGET_OUTPUT}/etc/apk/world
	#	echo "musl=${musl_ver}" >> ${TARGET_OUTPUT}/etc/apk/world
	#	echo "musl-utils=${musl_ver}" >> ${TARGET_OUTPUT}/etc/apk/world
	#fi

	#resolve
	cat <<- EOF > ${TARGET_OUTPUT}/etc/resolv.conf
	nameserver 1.1.1.1
	nameserver 1.0.0.1
	EOF

	#timezone
	echo "${TARGET_TIMEZONE}" > ${TARGET_OUTPUT}/etc/TZ
	if [ -e ${TARGET_OUTPUT}/usr/share/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		ln -s /usr/share/zoneinfo/${TARGET_TIMEZONE} ${TARGET_OUTPUT}/etc/localtime
	elif [ -e /usr/share/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		cat /usr/share/zoneinfo/${TARGET_TIMEZONE} > ${TARGET_OUTPUT}/etc/localtime
	elif [ -e /etc/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		cat /etc/zoneinfo/${TARGET_TIMEZONE} > ${TARGET_OUTPUT}/etc/localtime
	else
		local tz1=$(echo "${TARGET_TIMEZONE}" | cut -d '/' -f 1)
		local tz2=$(echo "${TARGET_TIMEZONE}" | cut -d '/' -f 2)
		mkdir -p ${TARGET_OUTPUT}/tmp/tzdata
		run_cmd ${TARGET_OUTPUT}/sbin/apk.static --repository ${ALPINE_MIRROR}/${ALPINE_DIST}/main --no-cache --allow-untrusted --root "${TARGET_OUTPUT}" --stdout --quiet fetch tzdata | tar -zx -C "${TARGET_OUTPUT}/tmp/tzdata" usr/share/zoneinfo
		if [ -e ${TARGET_OUTPUT}/tmp/tzdata/usr/share/zoneinfo/${tz1}/${tz2} ]; then
			mkdir -p ${TARGET_OUTPUT}/etc/zoneinfo/${tz1}
			cp ${TARGET_OUTPUT}/tmp/tzdata/usr/share/zoneinfo/${tz1}/${tz2} ${TARGET_OUTPUT}/etc/zoneinfo/${tz1}/${tz2}
			ln -sf /etc/zoneinfo/${tz1}/${tz2} ${TARGET_OUTPUT}/etc/localtime
		fi
		rm -rf ${TARGET_OUTPUT}/tmp/tzdata
	fi

	echo


	echo "Clearing"

	rm -rf ${TARGET_OUTPUT}/sbin/apk.static

	#umount ${TARGET_OUTPUT}/proc/
	#umount -R ${TARGET_OUTPUT}/sys/
	#umount -R ${TARGET_OUTPUT}/dev

	echo

	fn_make_common
}

fn_make_entware() {
	echo "Bootstrap"
	local USE_LOCALE=Y

	local ENTWARE_VER=
	if [ "${TARGET_ARCH}" = "x64" ]; then
		ENTWARE_VER="$(wget http://bin.entware.net/ -q -O - | grep 'x64-' | tail -1 | sed -e 's/^.*a href="\([^"]*\)\/".*$/\1/g')"
	elif [ "${TARGET_ARCH}" = "aarch64" ]; then
		ENTWARE_VER="$(wget http://bin.entware.net/ -q -O - | grep 'aarch64-' | tail -1 | sed -e 's/^.*a href="\([^"]*\)\/".*$/\1/g')"
	elif [ "${TARGET_ARCH}" = "armv7" ]; then
		ENTWARE_VER="$(wget http://bin.entware.net/ -q -O - | grep 'armv7sf-' | tail -1 | sed -e 's/^.*a href="\([^"]*\)\/".*$/\1/g')"
	fi

	# Need busbox for bootstrapping
	local ALPINE_ARCH=${TARGET_ARCH}
	ALPINE_ARCH=${ALPINE_ARCH/x64/x86_64}
	ALPINE_ARCH=${ALPINE_ARCH/aarch64/aarch64}
	ALPINE_ARCH=${ALPINE_ARCH/armv7/armv7}

	#qemu
	mkdir -p ${TARGET_OUTPUT}/usr/bin
	if [ ! -z "${TARGET_QEMU}" ]; then
		mkdir -p ${TARGET_OUTPUT}/usr/bin
		cp extras/${TARGET_QEMU} ${TARGET_OUTPUT}/usr/bin/

		chroot_cmd() {
			#QEMU_EXECVE=1 PATH="/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/bbin" chroot "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve "${@}"
			PATH="/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/bbin" chroot "${TARGET_OUTPUT}" "${@}"
		}
	else
		chroot_cmd() {
			PATH="/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/bbin" chroot "${TARGET_OUTPUT}" "${@}"
		}
	fi

	#busybox
	local busybox="https://mirror.xtom.com.hk/alpine/latest-stable/main/${ALPINE_ARCH}/$(wget https://mirror.xtom.com.hk/alpine/latest-stable/main/${ALPINE_ARCH}/ -q -O - | grep busybox-static | sed -e 's/^.*href="\([^"]*\)".*$/\1/g')"
	wget "${busybox}" -q -O - | tar zxf - -C ${TARGET_OUTPUT}/
	rm -rf ${TARGET_OUTPUT}/.PKGINFO ${TARGET_OUTPUT}/.SIGN.RSA*
	mv ${TARGET_OUTPUT}/bin ${TARGET_OUTPUT}/bbin
	chroot_cmd /bbin/busybox.static --install -s /bbin
	mkdir -p ${TARGET_OUTPUT}/bin
	ln -s /bbin/busybox.static ${TARGET_OUTPUT}/bin/sh

	#Create basic directory
	for folder in dev etc proc run sys
	do
		mkdir -p ${TARGET_OUTPUT}/${folder}
	done

	#resolve
	cat <<- EOF > ${TARGET_OUTPUT}/etc/resolv.conf
	nameserver 1.1.1.1
	nameserver 1.0.0.1
	EOF

	#Intall entware
	wget http://bin.entware.net/${ENTWARE_VER}/installer/generic.sh -q -O ${TARGET_OUTPUT}/entware_install.sh
	sed -i -e 's|/opt/bin/opkg install entware-opt|#/opt/bin/opkg install entware-opt|g' ${TARGET_OUTPUT}/entware_install.sh
	sed -i -e 's|chmod 777 /opt/tmp|chmod 777 /opt/tmp\nexit 0|g' ${TARGET_OUTPUT}/entware_install.sh
	chroot_cmd /bin/sh -c "/bin/sh /entware_install.sh ; /opt/bin/opkg update ; /opt/bin/opkg install opkg busybox entware-release"
	rm -rf ${TARGET_OUTPUT}/entware_install.sh

	#ln
	for x in bin sbin lib var tmp root home usr
	do
		if [ ! -e ${TARGET_OUTPUT}/opt/${x} ]; then
			mkdir -p ${TARGET_OUTPUT}/opt/${x}
		fi
		rm -rf ${TARGET_OUTPUT}/${x}
		ln -sf opt/${x} ${TARGET_OUTPUT}/${x}
	done
	chmod 1777 ${TARGET_OUTPUT}/opt/tmp
	if [ "${TARGET_ARCH}" = "x64" ]; then
		rm -rf ${TARGET_OUTPUT}/lib64
		ln -sf opt/lib ${TARGET_OUTPUT}/lib64
	fi
	if [ "${TARGET_ARCH}" = "armv7" -a ! -e ${TARGET_OUTPUT}/opt/lib/ld-linux-armhf.so.3 ]; then
		ln -sf $(basename $(ls ${TARGET_OUTPUT}/opt/lib/ld-*.so)) ${TARGET_OUTPUT}/opt/lib/ld-linux-armhf.so.3
	fi

	#qemu
	mkdir -p ${TARGET_OUTPUT}/usr/bin
	if [ ! -z "${TARGET_QEMU}" ]; then
		mkdir -p ${TARGET_OUTPUT}/usr/bin
		cp extras/${TARGET_QEMU} ${TARGET_OUTPUT}/usr/bin/
	fi

	#workaround link
	ln -s /opt/bin/env ${TARGET_OUTPUT}/usr/bin/env

	chroot_cmd /bin/sh -c "/opt/bin/opkg update ; /opt/bin/opkg download entware-opt"
	tar zxf ${TARGET_OUTPUT}/entware-opt* -C ${TARGET_OUTPUT}/
	tar zxf ${TARGET_OUTPUT}/data.tar.gz -C ${TARGET_OUTPUT}/
	rm -rf ${TARGET_OUTPUT}/entware-opt* ${TARGET_OUTPUT}/debian-binary ${TARGET_OUTPUT}/data.* ${TARGET_OUTPUT}/control.*

	#etc
	mkdir -p ${TARGET_OUTPUT}/usr/bin ${TARGET_OUTPUT}/usr/sbin ${TARGET_OUTPUT}/usr/local/bin ${TARGET_OUTPUT}/usr/local/sbin
	mv ${TARGET_OUTPUT}/opt/etc/shells.1 ${TARGET_OUTPUT}/opt/etc/shells
	rm -rf ${TARGET_OUTPUT}/opt/etc/*.1
	cat <<- EOF > ${TARGET_OUTPUT}/opt/etc/passwd
	root:x:0:0:Root:/root:/opt/bin/sh
	nobody:x:65534:65534:nobody:/:/sbin/nologin
	EOF
	cat <<- EOF > ${TARGET_OUTPUT}/opt/etc/group
	root:x:0:root
	users:x:100:
	nobody:x:65534:
	EOF
	sed -i -e 's/^export LANG=/#export LANG=/g' -e 's/^export LC_ALL=/#export LC_ALL=/g' ${TARGET_OUTPUT}/opt/etc/profile
	echo >> ${TARGET_OUTPUT}/opt/etc/profile
	echo "export LD_LIBRARY_PATH=/opt/lib" >> ${TARGET_OUTPUT}/opt/etc/profile
	echo "export PATH=/usr/local/sbin:/usr/local/bin:\${PATH}" >> ${TARGET_OUTPUT}/opt/etc/profile

	#resolve
	cat <<- EOF > ${TARGET_OUTPUT}/etc/resolv.conf
	nameserver 1.1.1.1
	nameserver 1.0.0.1
	EOF

	#skel
	cp -ar ${TARGET_OUTPUT}/opt/etc/skel/. ${TARGET_OUTPUT}/root/

	#timezone
	if [ -e ${TARGET_OUTPUT}/opt/share/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		ln -s /opt/share/zoneinfo/${TARGET_TIMEZONE} ${TARGET_OUTPUT}/opt/etc/localtime
	elif [ -e /usr/share/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		cat /usr/share/zoneinfo/${TARGET_TIMEZONE} > ${TARGET_OUTPUT}/opt/etc/localtime
	elif [ -e /etc/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		cat /etc/zoneinfo/${TARGET_TIMEZONE} > ${TARGET_OUTPUT}/opt/etc/localtime
	fi

	#Locales
	if [ "${USE_LOCALE}" = "Y" ]; then
		#Ignore locales
		mkdir --p ${TARGET_OUTPUT}/opt/usr/lib/locale
		touch ${TARGET_OUTPUT}/opt/usr/lib/locale/locale-archive

		if [ ! -z "${TARGET_QEMU}" ]; then
			#QEMU_EXECVE=1 PATH="/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" chroot "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve /bin/sh -c "/opt/bin/opkg install locales"
			chroot "${TARGET_OUTPUT}" /bin/sh -c "/opt/bin/opkg install locales"
		else
			chroot "${TARGET_OUTPUT}" /bin/sh -c "/opt/bin/opkg install locales"
		fi
		rm -rf ${TARGET_OUTPUT}/opt/usr/lib/locale/locale-archive
		mkdir -p ${TARGET_OUTPUT}/locales
		wget http://pkg.entware.net/sources/i18n_glib227.tar.gz -q -O - | tar zxf - -C ${TARGET_OUTPUT}/locales/
		cp ${TARGET_OUTPUT}/locales/i18n/locales/translit_hangul ${TARGET_OUTPUT}/opt/usr/share/i18n/locales/translit_hangul
		cp ${TARGET_OUTPUT}/locales/i18n/locales/ko_KR ${TARGET_OUTPUT}/opt/usr/share/i18n/locales/ko_KR
		cp ${TARGET_OUTPUT}/locales/i18n/charmaps/EUC-KR.gz ${TARGET_OUTPUT}/opt/usr/share/i18n/charmaps/EUC-KR.gz
		gzip -dc ${TARGET_OUTPUT}/locales/i18n/charmaps/EUC-KR.gz > ${TARGET_OUTPUT}/opt/usr/share/i18n/charmaps/EUC-KR
		cp ${TARGET_OUTPUT}/locales/i18n/charmaps/KSC5636.gz ${TARGET_OUTPUT}/opt/usr/share/i18n/charmaps/KSC5636.gz
		gzip -dc ${TARGET_OUTPUT}/locales/i18n/charmaps/KSC5636.gz > ${TARGET_OUTPUT}/opt/usr/share/i18n/charmaps/KSC5636
		cp ${TARGET_OUTPUT}/locales/i18n/charmaps/CP949.gz ${TARGET_OUTPUT}/opt/usr/share/i18n/charmaps/CP949.gz
		gzip -dc ${TARGET_OUTPUT}/locales/i18n/charmaps/CP949.gz > ${TARGET_OUTPUT}/opt/usr/share/i18n/charmaps/CP949
		rm -rf ${TARGET_OUTPUT}/locales
		local l1="$(echo "${TARGET_LOCALE}" | cut -d '.' -f 1)"
		local l2="$(echo "${TARGET_LOCALE}" | cut -d '.' -f 2)"
		chroot_cmd /opt/bin/localedef.new -c -f ${l2} -i ${l1} ${l1}.${l2}
	else
		#Ignore locales
		mkdir --p ${TARGET_OUTPUT}/opt/usr/lib/locale
		local l1="$(echo "${TARGET_LOCALE}" | cut -d '.' -f 1)"
		local l2="$(echo "${TARGET_LOCALE}" | cut -d '.' -f 2)"
		chroot_cmd /bin/sh -c "touch /opt/usr/lib/locale/locale-archive ; /opt/bin/opkg install locales ; rm -rf /opt/usr/lib/locale/locale-archive ; /opt/bin/localedef.new -c -f ${l2} -i ${l1} ${l1}.${l2} ; /opt/bin/opkg remove locales --autoremove"
	fi

	for x in entware_release passwd group localtime passwd profile shells
	do
		if [ -e ${TARGET_OUTPUT}/opt/etc/${x} ]; then
			ln -sf /opt/etc/${x} /${TARGET_OUTPUT}/etc/
		fi
	done
	ln -sf /etc/resolv.conf ${TARGET_OUTPUT}/opt/etc/resolv.conf

	#qemu
	if [ ! -z "${TARGET_QEMU}" ]; then
		cp -f extras/${TARGET_QEMU} "${TARGET_OUTPUT}/usr/bin/"
		cp -f extras/${TARGET_QEMU} "${TARGET_OUTPUT}/usr/local/bin/"
		chmod 4755 "${TARGET_OUTPUT}/usr/local/bin/${TARGET_QEMU}"
		cat << EOF > ${TARGET_OUTPUT}/usr/local/bin/sudo
#!/bin/sh

qemu=/usr/local/bin/${TARGET_QEMU}
sudo=/bin/sudo

if grep -q -w lm /proc/cpuinfo ; then
		if [ "\$(basename "\${0}")" = "sudoedit" ]; then
				\${qemu} -execve -0 /bin/sh \${sudo} -e "\${@}"
		else
				\${qemu} -execve -0 /bin/sh \${sudo} "\${@}"
		fi
else
		if [ "\$(basename "\${0}")" = "sudoedit" ]; then
				\${sudo} -e "\${@}"
		else
				\${sudo} "\${@}"
		fi
fi

exit \$?
EOF
		chmod 4755 ${TARGET_OUTPUT}/usr/local/bin/sudo
		ln -sf sudo ${TARGET_OUTPUT}/usr/local/bin/sudoedit
	fi


	echo "Clearing"

	rm -rf ${TARGET_OUTPUT}/bbin
	chmod 1777 ${TARGET_OUTPUT}/opt/tmp

	echo

	fn_make_common
}

fn_make_arch() {
	local ARCH_ARCH=${TARGET_ARCH}
	ARCH_ARCH=${ARCH_ARCH/x64/x86_64}
	ARCH_ARCH=${ARCH_ARCH/aarch64/aarch64}
	ARCH_ARCH=${ARCH_ARCH/armv7/armv7h}

	if [ "${ARCH_ARCH}" = "x86_64" ]; then
		#PACMAN_MIRROR=http://ftp.lanet.kr/pub/archlinux
		#PACMAN_MIRROR=http://ftp.harukasan.org/archlinux
		PACMAN_MIRROR=http://mirror.anigil.com/archlinux
		PACMAN_MIRRORLIST="Server = ${PACMAN_MIRROR}/\$repo/os/\$arch"
		PACMAN_EXTRA_PKGS=""
		ARCH_KEYRING="archlinux"
	else
		#PACMAN_MIRROR=http://ca.us.mirror.archlinuxarm.org
		PACMAN_MIRROR=http://tw.mirror.archlinuxarm.org
		PACMAN_MIRRORLIST="Server = ${PACMAN_MIRROR}/\$arch/\$repo"
		PACMAN_EXTRA_PKGS="archlinuxarm-keyring"
		ARCH_KEYRING="archlinuxarm"
	fi

	fn_make_arch_common "${ARCH_ARCH}" "${PACMAN_MIRROR}" "${PACMAN_MIRRORLIST}" "${PACMAN_EXTRA_PKGS}" "${ARCH_KEYRING}"
}

fn_make_arch_common() {
	if [ ! -e /usr/bin/arch-chroot ]; then
		apk add arch-install-scripts
	fi

	echo "Bootstrap"

	local ARCH_ARCH="${1}"
	local PACMAN_MIRROR="${2}"
	local PACMAN_MIRRORLIST="${3}"
	local PACMAN_EXTRA_PKGS="${4}"
	local ARCH_KEYRING="${5}"

	#local PACMAN_BASE_PKGS=(bash bzip2 coreutils diffutils filesystem findutils gettext glibc grep gzip less pacman perl procps-ng sed shadow systemd)
	local PACMAN_BASE_PKGS="bash coreutils diffutils filesystem findutils gawk gettext glibc grep gzip less pacman procps-ng sed systemd haveged"
	#local PACMAN_REMOVE_PKGS="diffutils gettext gzip less procps-ng haveged"
	local PACMAN_REMOVE_PKGS="gawk gzip less procps-ng haveged"

	PACMAN_CONF="${TARGET_OUTPUT}/pacman.conf"

	cat <<- EOF > "${PACMAN_CONF}"
	[options]
	HoldPkg = pacman glibc
	Architecture = ${ARCH_ARCH}
	SigLevel = Never
	LocalFileSigLevel = Never
	[core]
	${PACMAN_MIRRORLIST}
	[extra]
	${PACMAN_MIRRORLIST}
	[community]
	${PACMAN_MIRRORLIST}
	EOF
	if [ "${ARCH_ARCH}" = "x86_64" ]; then
	cat <<- EOF >> "${PACMAN_CONF}"
	[multilib]
	${PACMAN_MIRRORLIST}
	EOF
	fi
	if [ "${ARCH_ARCH}" != "x86_64" ]; then
		cat <<- EOF >> "${PACMAN_CONF}"
		[alarm]
		${PACMAN_MIRRORLIST}
		[aur]
		${PACMAN_MIRRORLIST}
		EOF
	fi

	#fix error
	mkdir -p "${TARGET_OUTPUT}"
	mount -o bind "${TARGET_OUTPUT}" "${TARGET_OUTPUT}"

	#qemu
	if [ ! -z "${TARGET_QEMU}" ]; then
		mkdir -p ${TARGET_OUTPUT}/usr/bin
		cp extras/${TARGET_QEMU} ${TARGET_OUTPUT}/usr/bin/
		chroot_cmd() {
			#QEMU_EXECVE=1 PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl" arch-chroot "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve "${@}"
			PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl" arch-chroot "${TARGET_OUTPUT}" "${@}"
		}
	else
		chroot_cmd() {
			PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl" arch-chroot "${TARGET_OUTPUT}" "${@}"
		}
	fi

	mkdir -m 0755 -p ${TARGET_OUTPUT}/var/{cache/pacman/pkg,lib/pacman,log}
	mkdir -m 0755 -p ${TARGET_OUTPUT}/{dev,run,etc/pacman.d}
	mkdir -m 1777 -p ${TARGET_OUTPUT}/tmp
	mkdir -m 0555 -p ${TARGET_OUTPUT}/{sys,proc}

	echo "rootfs / rootfs rw 0 0" > "${TARGET_OUTPUT}/etc/mtab"
	mknod -m 0666 "${TARGET_OUTPUT}/dev/null" c 1 3
	mknod -m 0666 "${TARGET_OUTPUT}/dev/random" c 1 8
	mknod -m 0666 "${TARGET_OUTPUT}/dev/urandom" c 1 9

	extras/arch-bootstrap.sh -a ${ARCH_ARCH} -r "${PACMAN_MIRROR}" ${TARGET_OUTPUT}

	if [ ! -e ${TARGET_OUTPUT}/pacman.conf ]; then
		cp ${PACMAN_CONF} ${TARGET_OUTPUT}/
	fi
	chroot_cmd /usr/bin/pacman -Suy --noconfirm --overwrite "*" ${PACMAN_BASE_PKGS} ${PACMAN_EXTRA_PKGS}

	echo

	echo "Configuration"

	#users gid
	sed -i -e "s/^users:x:.*$/users:x:100:/g" ${TARGET_OUTPUT}/etc/group

	#resolve
	cat <<- EOF > ${TARGET_OUTPUT}/etc/resolv.conf
	nameserver 1.1.1.1
	nameserver 1.0.0.1
	EOF

	chroot_cmd passwd -d root

	#systemd-sysusers
	if [ -e "${TARGET_OUTPUT}/usr/bin/systemd-sysusers" ]; then
		chroot_cmd /usr/bin/systemd-sysusers
	fi

	#update-ca-trust
	chroot_cmd update-ca-trust

	#keyring
	chroot_cmd sh -c "/usr/bin/haveged ; /usr/bin/rm -fr /etc/pacman.d/gnupg ; /usr/bin/pacman-key --init ; /usr/bin/pacman-key --populate ${ARCH_KEYRING} ; /usr/bin/pkill haveged ; /usr/bin/pkill gpg-agent"

	#basic config
	echo "${PACMAN_MIRRORLIST}" > ${TARGET_OUTPUT}/etc/pacman.d/mirrorlist
	sed -i -e "s/\(Architecture =\) auto/\1 ${ARCH_ARCH}/g" ${TARGET_OUTPUT}/etc/pacman.conf
	sed -i -e "s/#\(NoUpgrade   =\)/\1 \/etc\/pacman.d\/mirrorlist/g" ${TARGET_OUTPUT}/etc/pacman.conf
	if [ "${ARCH_ARCH}" = "x86_64" ]; then
		sed -i -e "/^#\[multilib\]/{N; s/#\(\[multilib\]\)\n#\(.*\)$/\1\n\2/g}" ${TARGET_OUTPUT}/etc/pacman.conf
	fi

	#locale
	#if [ -e ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8.gz ]; then
	#	rm -rf ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8
	#	gzip -dk ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8.gz
	#fi
	sed -i -e "s/#*[ ]*${TARGET_LOCALE}/${TARGET_LOCALE}/g" ${TARGET_OUTPUT}/etc/locale.gen
	echo "LANG=${TARGET_LOCALE}" >> ${TARGET_OUTPUT}/etc/locale.conf
	echo "LC_ALL=${TARGET_LOCALE}" >> ${TARGET_OUTPUT}/etc/locale.conf
	chroot_cmd locale-gen

	#timezone
	if [ -e "${TARGET_OUTPUT}/usr/share/zoneinfo/${TARGET_TIMEZONE}" ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		ln -sf /usr/share/zoneinfo/${TARGET_TIMEZONE} ${TARGET_OUTPUT}/etc/localtime
	fi

	#skel
	cp -ar ${TARGET_OUTPUT}/etc/skel/. ${TARGET_OUTPUT}/root/

	#makepkg
	[ -e /usr/bin/makepkg ] && sed -i -e 's/(( EUID == 0 ))/false /g' /usr/bin/makepkg

	#busybox
	local busybox="https://mirror.xtom.com.hk/alpine/latest-stable/main/${ALPINE_ARCH}/$(wget https://mirror.xtom.com.hk/alpine/latest-stable/main/${ALPINE_ARCH}/ -q -O - | grep busybox-static | sed -e 's/^.*href="\([^"]*\)".*$/\1/g')"
	mkdir -p ${TARGET_OUTPUT}/usr/local/busybox
	wget "${busybox}" -q -O - | tar zxf - -C ${TARGET_OUTPUT}/usr/local/busybox/
	mv ${TARGET_OUTPUT}/usr/local/busybox/bin/busybox.static ${TARGET_OUTPUT}/usr/local/busybox/busybox.static
	chmod +s ${TARGET_OUTPUT}/usr/local/busybox/busybox.static
	rm -rf ${TARGET_OUTPUT}/usr/local/busybox/bin ${TARGET_OUTPUT}/usr/local/busybox/.PKGINFO ${TARGET_OUTPUT}/usr/local/busybox/.SIGN.RSA*
	chroot_cmd /usr/local/busybox/busybox.static --install -s /usr/local/busybox
	ln -s busybox.static ${TARGET_OUTPUT}/usr/local/busybox/busybox
	cat << EOF > ${TARGET_OUTPUT}/etc/profile.d/busybox.sh
#!/bin/sh

export PATH=\${PATH}:/usr/local/busybox
EOF

	echo


	echo "Clearing"
	rm -rf ${TARGET_OUTPUT}/.BUILDINFO ${TARGET_OUTPUT}/.MTREE ${TARGET_OUTPUT}/.PKGINFO
	rm -rf ${TARGET_OUTPUT}/pacman.conf
	find ${TARGET_OUTPUT}/etc -name \*.pacnew -exec rm -rf {} \;

	rm -rf ${TARGET_OUTPUT}/.BUILDINFO ${TARGET_OUTPUT}/.INSTALL ${TARGET_OUTPUT}/.MTREE ${TARGET_OUTPUT}/.PKGINFO
	if [ ! -z "${PACMAN_REMOVE_PKGS}" ]; then
		chroot_cmd /usr/bin/pacman -Rsn --noconfirm ${PACMAN_REMOVE_PKGS}
	fi
	echo

	#fix error
	umount "${TARGET_OUTPUT}"

	fn_make_common
}

fn_make_debian() {
	local DEBIAN_DIST=${TARGET_EDITION}
	if [ -z "${DEBIAN_DIST}" ]; then
		#DEBIAN_DIST="$(curl -sSL http://ftp.kaist.ac.kr/debian/dists/README | grep '^stable,' | sed -e 's/^stable, or \([^ ]\+\)\s\+.*$/\1/g')"
		#DEBIAN_DIST="${DEBIAN_DIST:-sid}"
		DEBIAN_DIST="${DEBIAN_DIST:-testing}"
	fi
	echo "Current version : ${DEBIAN_DIST}"

	local DEBIAN_ARCH=${TARGET_ARCH}
	DEBIAN_ARCH=${DEBIAN_ARCH/x64/amd64}
	DEBIAN_ARCH=${DEBIAN_ARCH/aarch64/arm64}
	DEBIAN_ARCH=${DEBIAN_ARCH/armv7/armhf}

	#local DEBIAN_MIRROR=http://ftp.kr.debian.org/debian
	#local DEBIAN_MIRROR=http://ftp.daumkakao.com/debian
	#local DEBIAN_MIRROR=http://ftp.lanet.kr/pub/debian
	#local DEBIAN_MIRROR=http://ftp.harukasan.org/debian
	#local DEBIAN_MIRROR=http://mirror.kakao.com/debian
	local DEBIAN_MIRROR=http://mirror.anigil.com/debian

	local DEBIAN_COMPONENTS="main contrib non-free"

	local DEBIAN_EXTRA=""
	#local DEBIAN_EXTRA=locales

	fn_make_debian_common "${DEBIAN_DIST}" "${DEBIAN_MIRROR}" "${DEBIAN_EXTRA}" "${DEBIAN_ARCH}" "${DEBIAN_COMPONENTS}"
}

fn_make_ubuntu() {
	local DEBIAN_DIST=${TARGET_EDITION}
	if [ -z "${DEBIAN_DIST}" ]; then
		#DEBIAN_DIST="$(curl -sSL http://ftp.kaist.ac.kr/ubuntu/dists/ | grep -v 'backports' | grep -v 'proposed' | grep -v 'security' | grep -v 'updates' | grep '<tr><td class="n">' | tail -1  | sed -e 's/^<tr><td class="n"><a href="\(.*\)\/">.*$/\1/g')"
		#DEBIAN_DIST="${DEBIAN_DIST:-eoan}"
		#DEBIAN_DIST="${DEBIAN_DIST:-focal}"
		#DEBIAN_DIST="${DEBIAN_DIST:-groovy}"
		DEBIAN_DIST="${DEBIAN_DIST:-hirsute}"
	fi
	echo "Current version : ${DEBIAN_DIST}"

	local DEBIAN_ARCH=${TARGET_ARCH}
	DEBIAN_ARCH=${DEBIAN_ARCH/x64/amd64}
	DEBIAN_ARCH=${DEBIAN_ARCH/aarch64/arm64}
	DEBIAN_ARCH=${DEBIAN_ARCH/armv7/armhf}

	local DEBIAN_MIRROR=
	if [ "${TARGET_ARCH}" = "x64" ]; then
		#DEBIAN_MIRROR=http://kr.archive.ubuntu.com/ubuntu
		#DEBIAN_MIRROR=http://ftp.daumkakao.com/ubuntu
		#DEBIAN_MIRROR=http://ftp.lanet.kr/pub/ubuntu
		#DEBIAN_MIRROR=http://ftp.harukasan.org/ubuntu
		#DEBIAN_MIRROR=http://mirror.kakao.com/ubuntu
		DEBIAN_MIRROR=http://mirror.anigil.com/ubuntu
	else
		#DEBIAN_MIRROR=https://mirrors.xtom.com.hk/ubuntu-ports
		#DEBIAN_MIRROR=http://ports.ubuntu.com/ubuntu-ports
		#DEBIAN_MIRROR=http://ftp.harukasan.org/ubuntu-ports
		DEBIAN_MIRROR=http://mirror.anigil.com/ubuntu-ports
	fi

	local DEBIAN_COMPONENTS="main universe restricted multiverse"

	local DEBIAN_EXTRA=""
	#local DEBIAN_EXTRA="language-pack-ko"
	#local DEBIAN_EXTRA="locales,tzdata"

	if [ ! -e /usr/share/debootstrap/scripts/${DEBIAN_DIST} -a -e /usr/share/debootstrap/scripts/gutsy ]; then
		ln -s gutsy /usr/share/debootstrap/scripts/${DEBIAN_DIST}
	fi

	fn_make_debian_common "${DEBIAN_DIST}" "${DEBIAN_MIRROR}" "${DEBIAN_EXTRA}" "${DEBIAN_ARCH}" "${DEBIAN_COMPONENTS}"
}

fn_make_debian_common() {
	if ! debootstrap --help &>/dev/null ; then
		#echo "Could not find debootstrap. Run pacman -S debootstrap"
		#exit 1
		apk add debootstrap
	fi

	local DEBIAN_DIST="${1}"
	local DEBIAN_MIRROR="${2}"
	local DEBIAN_EXTRA=("${3}")
	local DEBIAN_ARCH=("${4}")
	local DEBIAN_COMPONENTS="${5:-main}"
	local DEBIAN_OPTION=("--variant=minbase")
	if [ ! -z "${DEBIAN_EXTRA}" ]; then
		DEBIAN_OPTION=("${DEBIAN_OPTION[@]}" "--include=busybox,locales,${DEBIAN_EXTRA}")
	else
		DEBIAN_OPTION=("${DEBIAN_OPTION[@]}" "--include=busybox,locales")
	fi
	DEBIAN_OPTION=("${DEBIAN_OPTION[@]}" "--components=${DEBIAN_COMPONENTS// /,}")
	DEBIAN_OPTION=("${DEBIAN_OPTION[@]}" "--merged-usr")
	DEBIAN_OPTION=("--arch=${DEBIAN_ARCH}" "${DEBIAN_OPTION[@]}" "--exclude=bsdutils,e2fslibs,e2fsprogs,gzip,libcomerr2,lsb-base,mount,sed,sysvinit-utils")

	#Copy qemu
	if [ ! -z "${TARGET_QEMU}" ]; then
		mkdir -p "${TARGET_OUTPUT}/usr/bin"
		cp extras/${TARGET_QEMU} ${TARGET_OUTPUT}/usr/bin/

		chroot_cmd() {
			#QEMU_EXECVE=1 PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true chroot "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve "${@}"
			PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true chroot "${TARGET_OUTPUT}" "${@}"
		}
	else
		chroot_cmd() {
			PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true chroot "${TARGET_OUTPUT}" "${@}"
		}
	fi

	#debootstrap 1st
	mount -o remount,exec,dev "${TARGET_OUTPUT}"
	echo "debootstrap 1st"
	PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true debootstrap --foreign ${DEBIAN_OPTION[@]} ${DEBIAN_DIST} "${TARGET_OUTPUT}" ${DEBIAN_MIRROR}

	#Fetch busybox
	echo "fetch busybox"
	local url==""
	if [ "${TARGET_DISTRO}" = "debian" ]; then
		url="$(wget ${DEBIAN_MIRROR}/dists/${DEBIAN_DIST}/main/binary-${DEBIAN_ARCH}/Packages.gz -q -O - | zcat | grep "Filename: pool/.*/.*/.*/busybox_.*.deb" | sort -V | tail -1 | sed -e 's/Filename: //g')"
	elif [ "${TARGET_DISTRO}" = "ubuntu" ]; then
		url="$(wget ${DEBIAN_MIRROR}/dists/${DEBIAN_DIST}/universe/binary-${DEBIAN_ARCH}/Packages.gz -q -O - | zcat | grep "Filename: pool/.*/.*/.*/busybox_.*.deb" | sort -V | tail -1 | sed -e 's/Filename: //g')"
	fi
	echo ${url} ${DEBIAN_MIRROR}/${url}
	mkdir ${TARGET_OUTPUT}/busybox
	wget ${DEBIAN_MIRROR}/${url} -q -O ${TARGET_OUTPUT}/busybox/busybox.deb
	chroot_cmd /bin/sh -c "dpkg-deb -x /busybox/busybox.deb /busybox ; /busybox/bin/busybox cp /busybox/bin/busybox /bin/ ; /bin/busybox --install -s"
	rm -rf ${TARGET_OUTPUT}/busybox

	echo "${TARGET_TIMEZONE}" > ${TARGET_OUTPUT}/etc/timezone

	#debootstrap 2nd
	echo "debootstrap 2nd"
	chroot_cmd /bin/sh -c "/debootstrap/debootstrap --second-stage"

	#debootstrap 3rd
	echo "debootstrap 3rd"
	chroot_cmd /bin/sh -c "/usr/bin/dpkg --configure -a"

	#resolve
	echo "resolv.conf"
	cat <<- EOF > ${TARGET_OUTPUT}/etc/resolv.conf
	nameserver 1.1.1.1
	nameserver 1.0.0.1
	EOF

	#Mirror
	echo "mirror"
	if [ "${TARGET_DISTRO}" = "debian" ]; then
		cat <<- EOF > ${TARGET_OUTPUT}/etc/apt/sources.list
		deb ${DEBIAN_MIRROR} ${DEBIAN_DIST} ${DEBIAN_COMPONENTS}
		# deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST} ${DEBIAN_COMPONENTS}

		$([ "${DEBIAN_DIST}" = "sid" ] && echo "#")deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-updates ${DEBIAN_COMPONENTS}
		$([ "${DEBIAN_DIST}" = "sid" ] && echo "#")# deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-updates ${DEBIAN_COMPONENTS}

		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-proposed-updates ${DEBIAN_COMPONENTS}
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-proposed-updates ${DEBIAN_COMPONENTS}

		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-backports ${DEBIAN_COMPONENTS}
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-backports ${DEBIAN_COMPONENTS}

		$([ "${DEBIAN_DIST}" = "sid" -o "${DEBIAN_DIST}" = "testing" ] && echo "#")deb http://security.debian.org ${DEBIAN_DIST}/updates ${DEBIAN_COMPONENTS}
		$([ "${DEBIAN_DIST}" = "sid" -o "${DEBIAN_DIST}" = "testing" ] && echo "#")# deb-src http://security.debian.org ${DEBIAN_DIST}/updates ${DEBIAN_COMPONENTS}

		EOF
		if [ "${DEBIAN_DIST}" = "sid" -o "${DEBIAN_DIST}" = "testing" ] ; then
			cat <<- EOF >> ${TARGET_OUTPUT}/etc/apt/sources.list
			deb ${DEBIAN_MIRROR} stable ${DEBIAN_COMPONENTS}
			# deb-src ${DEBIAN_MIRROR} stable ${DEBIAN_COMPONENTS}

			EOF
		fi
		#cat <<- EOF > ${TARGET_OUTPUT}/etc/apt/sources.list
		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST} main
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST} main

		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-updates main
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-updates main

		#deb http://security.debian.org ${DEBIAN_DIST}/updates main
		## deb-src http://security.debian.org ${DEBIAN_DIST}/updates main
		#EOF
	fi
	if [ "${TARGET_DISTRO}" = "ubuntu" ]; then
		cat <<- EOF > ${TARGET_OUTPUT}/etc/apt/sources.list
		deb ${DEBIAN_MIRROR} ${DEBIAN_DIST} ${DEBIAN_COMPONENTS}
		# deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST} ${DEBIAN_COMPONENTS}

		deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-updates ${DEBIAN_COMPONENTS}
		# deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-updates ${DEBIAN_COMPONENTS}

		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-proposed ${DEBIAN_COMPONENTS}
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-proposed ${DEBIAN_COMPONENTS}

		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-backports ${DEBIAN_COMPONENTS}
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-backports ${DEBIAN_COMPONENTS}

		deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-security ${DEBIAN_COMPONENTS}
		# deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-security ${DEBIAN_COMPONENTS}
		EOF
		#cat <<- EOF > ${TARGET_OUTPUT}/etc/apt/sources.list
		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST} main restricted universe
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST} main restricted universe

		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-updates main restricted universe
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-updates main restricted universe

		#deb ${DEBIAN_MIRROR} ${DEBIAN_DIST}-security main restricted universe
		## deb-src ${DEBIAN_MIRROR} ${DEBIAN_DIST}-security main restricted universe
		#EOF
	fi

	#docker
	mkdir -p ${TARGET_OUTPUT}/run/systemd
	echo 'docker' > ${TARGET_OUTPUT}/run/systemd/container

	# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L40-L48
	echo '#!/bin/sh' > ${TARGET_OUTPUT}/usr/sbin/policy-rc.d
	echo 'exit 101' >> ${TARGET_OUTPUT}/usr/sbin/policy-rc.d
	chmod +x ${TARGET_OUTPUT}/usr/sbin/policy-rc.d

	# https://github.com/docker/docker/blob/9a9fc01af8fb5d98b8eec0740716226fadb3735c/contrib/mkimage/debootstrap#L54-L56
	chroot_cmd /bin/sh -c "dpkg-divert --local --rename --add /sbin/initctl ; cp -a /usr/sbin/policy-rc.d /sbin/initctl ; sed -i -e 's/^exit.*/exit 0/' /sbin/initctl"

	#apt
	echo "apt"
	if strings "${TARGET_OUTPUT}/usr/bin/dpkg" | grep -q unsafe-io; then
		# force dpkg not to call sync() after package extraction (speeding up installs)
		cat > "${TARGET_OUTPUT}/etc/dpkg/dpkg.cfg.d/docker-apt-speedup" <<-'EOF'
		force-unsafe-io
		EOF
	fi

	if [ -d "${TARGET_OUTPUT}/etc/apt/apt.conf.d" ]; then
		# _keep_ us lean by effectively running "apt-get clean" after every install
		aptGetClean='"rm -f /core /*.core /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true";'
		cat > "${TARGET_OUTPUT}/etc/apt/apt.conf.d/docker-clean" <<-EOF
		DPkg::Post-Invoke { ${aptGetClean} };
		APT::Update::Post-Invoke { ${aptGetClean} };

		Dir::Cache::pkgcache "";
		Dir::Cache::srcpkgcache "";
		EOF

		cat > "${TARGET_OUTPUT}/etc/apt/apt.conf.d/docker-no-check-valid" <<-'EOF'
		Acquire::Check-Valid-Until "0";
		EOF

		cat > "${TARGET_OUTPUT}/etc/apt/apt.conf.d/docker-no-languages" <<-'EOF'
		Acquire::Languages "none";
		EOF

		cat > "${TARGET_OUTPUT}/etc/apt/apt.conf.d/docker-gzip-indexes" <<-'EOF'
		Acquire::GzipIndexes "true";
		Acquire::CompressionTypes::Order:: "gz";
		EOF

		cat > "${TARGET_OUTPUT}/etc/apt/apt.conf.d/docker-autoremove-recommends-suggests" <<- 'EOF'
		APT::Install-Recommends "false";
		APT::Install-Suggests "false";
		EOF
	fi
	cat <<- EOF > "${TARGET_OUTPUT}/etc/profile.d/debconf.sh"
	export DEBIAN_FRONTEND=noninteractive
	export DEBCONF_NONINTERACTIVE_SEEN=true
	EOF
	chmod 755 "${TARGET_OUTPUT}/etc/profile.d/debconf.sh"

	#skel
	if [ -e ${TARGET_OUTPUT}/etc/skel ]; then
		cp -ar ${TARGET_OUTPUT}/etc/skel/. ${TARGET_OUTPUT}/root/
	fi

	#locale
	if [ -e "${TARGET_OUTPUT}/usr/sbin/locale-gen" ]; then
		sed -i -e "s/#*[ ]*${TARGET_LOCALE}/${TARGET_LOCALE}/g" ${TARGET_OUTPUT}/etc/locale.gen
		#if [ -e ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8.gz ]; then
		#	rm -rf ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8
		#	gzip -dk ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8.gz
		#fi
		chroot_cmd /bin/sh -c "/usr/sbin/locale-gen"
		echo "LANG=${TARGET_LOCALE}" >> ${TARGET_OUTPUT}/etc/default/locale
		echo "LANGUAGE=${TARGET_LOCALE}" >> ${TARGET_OUTPUT}/etc/default/locale
		echo "LC_ALL=${TARGET_LOCALE}" >> ${TARGET_OUTPUT}/etc/default/locale
	fi

	#timezone
	echo "${TARGET_TIMEZONE}" > ${TARGET_OUTPUT}/etc/timezone
	if [ -e ${TARGET_OUTPUT}/usr/share/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		ln -s /usr/share/zoneinfo/${TARGET_TIMEZONE} ${TARGET_OUTPUT}/etc/localtime
	elif [ -e /usr/share/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		cat /usr/share/zoneinfo/${TARGET_TIMEZONE} > ${TARGET_OUTPUT}/etc/localtime
	elif [ -e /etc/zoneinfo/${TARGET_TIMEZONE} ]; then
		rm -rf ${TARGET_OUTPUT}/etc/localtime
		cat /etc/zoneinfo/${TARGET_TIMEZONE} > ${TARGET_OUTPUT}/etc/localtime
	fi

	fn_make_common
}

fn_make_common() {
	fn_target_unmount
}

fn_update() {
	echo "Update"
	#resolve
	cat <<- EOF > ${TARGET_OUTPUT}/etc/resolv.conf
	nameserver 1.1.1.1
	nameserver 1.0.0.1
	EOF

	#echo "Create chroot envoronment"
	#mount -t proc /proc ${TARGET_OUTPUT}/proc/
	#mount --rbind /sys ${TARGET_OUTPUT}/sys/
	#mount --rbind /dev ${TARGET_OUTPUT}/dev
	#echo

	mkdir -p ${TARGET_OUTPUT}/usr/bin ${TARGET_OUTPUT}/usr/sbin ${TARGET_OUTPUT}/usr/local/bin ${TARGET_OUTPUT}/usr/local/sbin

	#clear
	rm -rf ${TARGET_OUTPUT}/usr/local/bin/docker-*

	#qemu
comment='
	if [ ! -z "${TARGET_QEMU}" ]; then
		cp -f extras/${TARGET_QEMU} "${TARGET_OUTPUT}/usr/bin/"
		ln "${TARGET_OUTPUT}/usr/bin/${TARGET_QEMU}" "${TARGET_OUTPUT}/usr/local/bin/${TARGET_QEMU}"
		chmod 4755 "${TARGET_OUTPUT}/usr/local/bin/${TARGET_QEMU}"
		cat << EOF > ${TARGET_OUTPUT}/usr/local/bin/sudo
#!/bin/sh

qemu=/usr/local/bin/${TARGET_QEMU}
sudo=/usr/bin/sudo

if [ ! -x \${sudo} -o ! -x \${qemu} ]; then
		"\${@}"
elif grep -q -w lm /proc/cpuinfo ; then
		if [ "\$(basename "\${0}")" = "sudoedit" ]; then
				\${qemu} -execve -0 /bin/sh \${sudo} -e "\${@}"
		else
				\${qemu} -execve -0 /bin/sh \${sudo} "\${@}"
		fi
else
		if [ "\$(basename "\${0}")" = "sudoedit" ]; then
				\${sudo} -e "\${@}"
		else
				\${sudo} "\${@}"
		fi
fi

exit \$?
EOF
		chmod 4755 ${TARGET_OUTPUT}/usr/local/bin/sudo
		ln -sf sudo ${TARGET_OUTPUT}/usr/local/bin/sudoedit
	fi
'

	#docker-run
	cp extras/docker-run ${TARGET_OUTPUT}/usr/local/bin/docker-run

	#docker-install
	if [ -e "${TARGET_OUTPUT}/etc/alpine-release" ]; then
		cp -f extras/docker-install.alpine ${TARGET_OUTPUT}/usr/local/bin/docker-install
	elif [ -e "${TARGET_OUTPUT}/opt/bin/opkg" ]; then
		cp -f extras/docker-install.entware ${TARGET_OUTPUT}/usr/local/bin/docker-install
	elif [ -e "${TARGET_OUTPUT}/etc/arch-release" ]; then
		mount -o bind "${TARGET_OUTPUT}" "${TARGET_OUTPUT}"
		cp -f extras/docker-install.arch ${TARGET_OUTPUT}/usr/local/bin/docker-install
		rm -rf ${TARGET_OUTPUT}/usr/local/bin/docker-sysusers ${TARGET_OUTPUT}/usr/local/bin/docker-tmpfiles
		#cp extras/docker-sysusers ${TARGET_OUTPUT}/usr/local/bin/
		#cp extras/docker-tmpfiles ${TARGET_OUTPUT}/usr/local/bin/
		#mount -o bind ${TARGET_OUTPUT} ${TARGET_OUTPUT}
	elif [ -e "${TARGET_OUTPUT}/etc/os-release" -a ! -z "$(grep "ID=\(debian\|ubuntu\)" "${TARGET_OUTPUT}/etc/os-release")" ]; then
		cp -f extras/docker-install.deb ${TARGET_OUTPUT}/usr/local/bin/docker-install
	elif [ -e "${TARGET_OUTPUT}/etc/os-release" -a ! -z "$(grep "ID=busybox" "${TARGET_OUTPUT}/etc/os-release")" ]; then
		cp -f extras/docker-install.busybox ${TARGET_OUTPUT}/usr/local/bin/docker-install
	fi

	#docker-adduser
	cp -f extras/docker-adduser ${TARGET_OUTPUT}/usr/local/bin/docker-adduser

	#docker-chown
	cp -f extras/docker-chown ${TARGET_OUTPUT}/usr/local/bin/docker-chown

	#debian locale
	if [ -e ${TARGET_OUTPUT}/etc/debian_version -a -e "${TARGET_OUTPUT}/usr/sbin/locale-gen" ]; then
		if [ -z "$(grep "^${TARGET_LOCALE}" ${TARGET_OUTPUT}/etc/locale.gen)" ]; then
			if [ ! -z "${TARGET_QEMU}" ]; then
				chroot_cmd() {
					#QEMU_EXECVE=1 PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true chroot "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve "${@}"
					PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true chroot "${TARGET_OUTPUT}" "${@}"
				}
			else
				chroot_cmd() {
					PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true chroot "${TARGET_OUTPUT}" "${@}"
				}
			fi
			sed -i -e "s/#*[ ]*${TARGET_LOCALE}/${TARGET_LOCALE}/g" ${TARGET_OUTPUT}/etc/locale.gen
			#if [ -e ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8.gz ]; then
			#	rm -rf ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8
			#	gzip -dk ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8.gz
			#fi
			chroot_cmd /bin/sh -c "/usr/sbin/locale-gen"
			echo "LANG=${TARGET_LOCALE}" >> ${TARGET_OUTPUT}/etc/default/locale
			echo "LANGUAGE=${TARGET_LOCALE}" >> ${TARGET_OUTPUT}/etc/default/locale
			echo "LC_ALL=${TARGET_LOCALE}" >> ${TARGET_OUTPUT}/etc/default/locale
		fi
	fi

	#archlinux fix
	if [ -e "${TARGET_OUTPUT}/etc/arch-release" ]; then
		if [ -e ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8.gz ]; then
			rm -rf ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8
			gzip -dk ${TARGET_OUTPUT}/usr/share/i18n/charmaps/UTF-8.gz
		fi

		if [ ! -z "$(find ${TARGET_OUTPUT}/usr/share/terminfo/ 2> /dev/null | grep '_ADMIN_')" ]; then
			for t in ${TARGET_OUTPUT}/usr/share/terminfo/*_ADMIN_*
			do
				mv ${t} ${t/_ADMIN_*/}
			done
		fi
	fi

	#update
	prev_md5=
	post_md5=
	PATH_CHROOT=
	CHROOT_CMD=chroot
	if [ "${TARGET_UPDATE}" = "Y" ]; then
		if [ -e "${TARGET_OUTPUT}/etc/alpine-release" ]; then
			prev_md5=$(md5sum ${TARGET_OUTPUT}/lib/apk/db/installed | cut -f 1 -d ' ')
			PATH_CHROOT=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
		elif [ -e "${TARGET_OUTPUT}/opt/bin/opkg" ]; then
			prev_md5=$(md5sum ${TARGET_OUTPUT}/opt/lib/opkg/status | cut -f 1 -d ' ')
			PATH_CHROOT=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
		elif [ -e "${TARGET_OUTPUT}/etc/arch-release" ]; then
			prev_md5=$(tar -cf - ${TARGET_OUTPUT}/var/lib/pacman/local 2> /dev/null | md5sum | cut -f 1 -d ' ')
			PATH_CHROOT="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"
			if [ -e /usr/bin/arch-chroot ]; then
				CHROOT_CMD=arch-chroot
			fi
		elif [ -e "${TARGET_OUTPUT}/etc/os-release" -a ! -z "$(grep "ID=\(debian\|ubuntu\)" "${TARGET_OUTPUT}/etc/os-release")" ]; then
			prev_md5=$(tar -cf - ${TARGET_OUTPUT}/var/lib/dpkg/info 2> /dev/null | md5sum | cut -f 1 -d ' ')
			PATH_CHROOT="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
			rm -rf ${TARGET_OUTPUT}/var/lib/apt/lists/lock
		elif [ -e "${TARGET_OUTPUT}/etc/os-release" -a ! -z "$(grep "ID=busybox" "${TARGET_OUTPUT}/etc/os-release")" ]; then
			prev_md5=$(md5sum ${TARGET_OUTPUT}/bin/busybox.static | cut -f 1 -d ' ')
			PATH_CHROOT=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
		fi

		if [ "${TARGET_DISTRO}" = "debian" -o "${TARGET_DISTRO}" = "ubuntu" -o "${TARGET_DISTRO}" = "entware" ]; then
			if [ ! -z "${TARGET_QEMU}" ]; then
				#QEMU_EXECVE=1 PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve /bin/sh -c "docker-install -r -u -f -c"
				PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /bin/sh -c "docker-install -r -u -f -c"
			else
				PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /bin/sh -c "docker-install -r -u -f -c"
			fi
		else
			if [ ! -z "${TARGET_QEMU}" ]; then
				#QEMU_EXECVE=1 PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve /bin/sh -c "docker-install -r -u -c"
				PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /bin/sh -c "docker-install -r -u -c"
			else
				PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /bin/sh -c "docker-install -r -u -c"
			fi
		fi

		#archlinux update-ca-trust
		if [ -e "${TARGET_OUTPUT}/etc/arch-release" ]; then
			if [ ! -z "${TARGET_QEMU}" ]; then
				#QEMU_EXECVE=1 PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve /bin/sh -c "update-ca-trust"
				PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /bin/sh -c "update-ca-trust"
			else
				PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /bin/sh -c "update-ca-trust"
			fi
		fi

		#alpinelinux update baselayout
		if [ -e "${TARGET_OUTPUT}/etc/alpine-release" ]; then
			if [ ! -z "${TARGET_QEMU}" ]; then
				#QEMU_EXECVE=1 PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /usr/bin/${TARGET_QEMU} -execve /bin/sh -c "apk --no-cache --allow-untrusted --quiet fetch alpine-base ; cat /alpine-base*.apk | tar -zxf - -C / etc/ ; rm -rf /alpine-base*.apk"
				PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /bin/sh -c "apk --no-cache --allow-untrusted --quiet fetch alpine-base ; cat /alpine-base*.apk | tar -zxf - -C / etc/ ; rm -rf /alpine-base*.apk"
			else
				PATH="${PATH_CHROOT}" LANG=C LC_ALL=C ${CHROOT_CMD} "${TARGET_OUTPUT}" /bin/sh -c "apk --no-cache --allow-untrusted --quiet fetch alpine-base ; cat /alpine-base*.apk | tar -zxf - -C / etc/ ; rm -rf /alpine-base*.apk"
			fi
		fi

		if [ -e "${TARGET_OUTPUT}/etc/alpine-release" ]; then
			post_md5=$(md5sum ${TARGET_OUTPUT}/lib/apk/db/installed | cut -f 1 -d ' ')
		elif [ -e "${TARGET_OUTPUT}/opt/bin/opkg" ]; then
			post_md5=$(md5sum ${TARGET_OUTPUT}/opt/lib/opkg/status | cut -f 1 -d ' ')
		elif [ -e "${TARGET_OUTPUT}/etc/arch-release" ]; then
			post_md5=$(tar -cf - ${TARGET_OUTPUT}/var/lib/pacman/local 2> /dev/null | md5sum | cut -f 1 -d ' ')
		elif [ -e "${TARGET_OUTPUT}/etc/os-release" -a ! -z "$(grep "ID=debian" "${TARGET_OUTPUT}/etc/os-release")" ]; then
			post_md5=$(tar -cf - ${TARGET_OUTPUT}/var/lib/dpkg/info 2> /dev/null | md5sum | cut -f 1 -d ' ')
		elif [ -e "${TARGET_OUTPUT}/etc/os-release" -a ! -z "$(grep "ID=ubuntu" "${TARGET_OUTPUT}/etc/os-release")" ]; then
			post_md5=$(tar -cf - ${TARGET_OUTPUT}/var/lib/dpkg/info 2> /dev/null | md5sum | cut -f 1 -d ' ')
		elif [ -e "${TARGET_OUTPUT}/etc/os-release" -a ! -z "$(grep "ID=busybox" "${TARGET_OUTPUT}/etc/os-release")" ]; then
			post_md5=$(md5sum ${TARGET_OUTPUT}/bin/busybox.static | cut -f 1 -d ' ')
		fi
		echo

		if [ ! -z "${prev_md5}" -a ! -z "${post_md5}" ]; then
			echo "PREV_MD5 : ${prev_md5}"
			echo "POST_MD5 : ${post_md5}"
			if [ "${prev_md5}" = "${post_md5}" ]; then
				echo "Already up-to-date"
			else
				echo "Distro update"
			fi
			echo
		fi
	fi

	#clean
	find ${TARGET_OUTPUT}/var -name \*.log -o -name \*-old -exec rm -rf "{}" \;

	rm -rf ${TARGET_OUTPUT}/core ${TARGET_OUTPUT}/*.core

	#umount ${TARGET_OUTPUT}/proc/
	#umount -R ${TARGET_OUTPUT}/sys/
	#umount -R ${TARGET_OUTPUT}/dev

	if [ -e "${TARGET_OUTPUT}/etc/arch-release" ]; then
		#mount -o bind "${TARGET_OUTPUT}" "${TARGET_OUTPUT}"
		umount "${TARGET_OUTPUT}"
	fi
}

fn_import() {
	echo "Import image"

	for id in $(docker ps -a -q -f ancestor=${TARGET_NAME}:${TARGET_TAG})
	do
		docker rm -f ${id}
	done
	for id in $(docker images -a -q ${TARGET_NAME}:${TAGET_TAG})
	do
		docker rmi -f ${id}
	done

	#import
	cmd=
	shell=
	if [ -e "${TARGET_OUTPUT}/bin/bash" ]; then
		shell=/bin/bash
	else
		shell=/bin/sh
	fi

	cmd="tar --numeric-owner --xattrs --acls -C ${TARGET_OUTPUT} -c ."
	cmd+=" | docker import --change \"ENTRYPOINT docker-run\""
	if [ "${TARGET_DISTRO}" = "entware" ] ; then
		cmd+=" --change \"ENV LD_LIBRARY_PATH=/opt/lib\""
		cmd+=" --change \"ENV PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin\""
	fi
	#if [ "${TARGET_ARCH}" != "amd64" ] ; then
	#	cmd+=" --change \"ENV QEMU_EXECVE=1\""
	#fi
	cmd+=" - ${TARGET_NAME}:${TARGET_TAG}"

	echo
	if [ "${DEBUG}" = "Y" ]; then
		echo "COMMAND : ${cmd}"
	fi
	eval ${cmd} #&> /dev/null
	echo Success.
	echo
}

fn_push() {
	echo "Push image"

	docker push ${TARGET_NAME}:${TARGET_TAG}
}

#if [ "$(uname -m)" != "x86_64" ]; then
#	echo "Not support host architecture (only for x86_64)"
#	exit 1
#fi

if [ "${IS_DOCKER}" = "Y" -a -e "${DOCKER_WORKDIR}" ]; then
	cd "${DOCKER_WORKDIR}"
fi

DEBUG=N

TARGET_DISTRO=
TARGET_ARCH=
TARGET_EDITION=
TARGET_OUTPUT=
TARGET_LOCALE=
TARGET_TIMEZONE=
TARGET_NAME=
TARGET_TAG=
TARGET_MAKE=
TARGET_MAKE_ONLY=
TARGET_UPDATE=
TARGET_IMPORT=
TARGET_PUSH=
TARGET_QEMU=

INCLUDE_PACKAGES=
EXCLUDE_PACKAGES=

EXTRA_ARGS=

QUIET=
VERBOSE=

while [[ ${#} > 0 ]]
do
	case "${1}" in
		-d|--distro) TARGET_DISTRO="${2}" ; shift 1 ;;
		-a|--arch|--archtecture) TARGET_ARCH="${2}" ; shift 1 ;;
		-e|--edition) TARGET_EDITION="${2}" ; shift 1 ;;
		-o|--out|--output) TARGET_OUTPUT="${2}" ; shift 1 ;;
		-l|--locale) TARGET_LOCALE="${2}" ; shift 1 ;;
		-z|--timezone) TARGET_TIMEZONE="${2}" ; shift 1 ;;
		--include) INCLUDE_PACKAGES="${2}" ; shift 1 ;;
		--exclude) EXCLUDE_PACKAGES="${2}" ; shift 1 ;;
		-n|--name) TARGET_NAME="${2/:*/}" ; TARGET_TAG="${2/*:/}" ; shift 1 ;;
		-u|--update) TARGET_UPDATE="Y" ;;
		-i|--import) TARGET_IMPORT="Y" ;;
		-m|--make) TARGET_MAKE="Y" ;;
		-mo) TARGET_MAKE="Y" ; TARGET_MAKE_ONLY="Y" ;;
		-p|--push) TARGET_PUSH="Y" ;;
		-q|--quiet) QUIET="Y" ;;
		-v|--verbose) VERBOSE="Y" ;;
		-h|--help) fn_usage ;;
	   	*) EXTRA_ARGS+=(${1}) ;;
	esac
	shift
done

#create dist.img
mkdir -p dist
pushd "$(realpath "$(pwd)")" &> /dev/null
mntopt=
while true
do
	if [ ! -z "$(mount | grep "on $(pwd) ")" ]; then
		mntopt="$(mount | grep "on $(pwd) ")"
		break
	fi
	if [ "$(pwd)" = "/" ]; then
		break;
	fi

	cd ..
done
popd &> /dev/null
if [ "${mntopt}" != "${mntopt/noexec/}" -o "${mntopt}" != "${mntopt/nodev/}" ]; then
	if [ ! -e dist.img ]; then
		truncate -s 5G dist.img
		mkfs.ext4 -F dist.img
		#losetup -f ./dist.img
		#lo_dev="$(losetup -j ./dist.img | cut -d ':' -f 1)"
		#mkfs.ext4 -F ${lo_dev}
		#losetup -d ${lo_dev}
		mount -o loop,dev,exec dist.img dist
		touch dist/img
	elif [ ! -e dist/img ]; then
		mount -o loop,dev,exec dist.img dist
	fi

	if [ ! -e dist/img ]; then
		echo "Errof dist.img"
		exit 1
	fi
fi

#set default
#TARGET_DISTRO="${TARGET_DISTRO:-arch}"
if [ "${TARGET_DISTRO}" != "alpine" -a "${TARGET_DISTRO}" != "arch" -a "${TARGET_DISTRO}" != "debian" -a "${TARGET_DISTRO}" != "ubuntu" -a "${TARGET_DISTRO}" != "entware" -a "${TARGET_DISTRO}" != "busybox" ]; then
	fn_usage
fi
if [ -z "${TARGET_ARCH}" -o "${TARGET_ARCH}" = "x64" -o "${TARGET_ARCH}" = "amd64" -o "${TARGET_ARCH}" = "x86_64" ]; then
	TARGET_ARCH=x64
elif [ "${TARGET_ARCH}" = "aarch64" -o "${TARGET_ARCH}" = "arm64" ]; then
	TARGET_ARCH=aarch64
elif [ "${TARGET_ARCH}" = "armv7" -o "${TARGET_ARCH}" = "armhf" ]; then
	TARGET_ARCH=armv7
else
	fn_usage
fi
TARGET_LOCALE=${TARGET_LOCALE:-ko_KR.UTF-8}
TARGET_TIMEZONE=${TARGET_TIMEZONE:-Asia/Seoul}
if [ -z "${TARGET_EDITION}" ]; then
	TARGET_NAME=${TARGET_NAME:-forumi0721/${TARGET_DISTRO}-base}
	if [ -z "${TARGET_TAG}" ]; then
		if [ "${TARGET_ARCH}" = "x64" ]; then
			TARGET_TAG=latest
		else
			TARGET_TAG=${TARGET_ARCH}
		fi
	else
		TARGET_TAG=${TARGET_TAG:-latest}
	fi
else
	TARGET_NAME=${TARGET_NAME:-forumi0721/${TARGET_DISTRO}-base}
	if [ -z "${TARGET_TAG}" ]; then
		if [ "${TARGET_ARCH}" = "x64" ]; then
			TARGET_TAG=x64-${TARGET_EDITION}
		else
			TARGET_TAG=${TARGET_ARCH}${TARGET_EDITION}
		fi
	else
		TARGET_TAG=${TARGET_TAG:-latest}
	fi
fi
TARGET_TAG=${TARGET_TAG:-latest}
if [ -z "${TARGET_OUTPUT}" ]; then
	TARGET_OUTPUT=dist-${TARGET_DISTRO}-${TARGET_TAG}
	TARGET_OUTPUT="dist/${TARGET_OUTPUT}"
	TARGET_OUTPUT=$(realpath ${TARGET_OUTPUT})
fi
if [ -e "${TARGET_OUTPUT}" ]; then
	TARGET_MAKE=${TARGET_MAKE:-N}
else
	TARGET_MAKE=Y
fi
if [ "${TARGET_MAKE_ONLY}" != "Y" -a "${TARGET_MAKE}" = "Y" -a -z "${TARGET_UPDATE}" ]; then
	TARGET_UPDATE=Y
else
	TARGET_UPDATE=${TARGET_UPDATE:-N}
fi
TARGET_IMPORT=${TARGET_IMPORT:-N}
TARGET_PUSH=${TARGET_PUSH:-N}
if [ "${TARGET_PUSH}" = "Y" ]; then
	TARGET_IMPORT=Y
fi
if [ "${TARGET_ARCH}" = "aarch64" ]; then
	TARGET_QEMU=qemu-aarch64-static
elif [ "${TARGET_ARCH}" = "armv7" ]; then
	TARGET_QEMU=qemu-arm-static
fi
QUIET=${QUIET:-N}
if [ "${QUIET}" = "Y" ]; then
	VERBOSE=${VERBOSE:-N}
else
	VERBOSE=${VERBOSE:-Y}
fi

#always make image
if [ "${TARGET_UPDATE}" = "Y" ]; then
	if [ "${TARGET_DISTRO}" = "alpine" -o "${TARGET_DISTRO}" = "entware" ]; then
		TARGET_MAKE=Y
	fi
fi

#confirm
if [ "${DEBUG}" = "Y" -o "${VERBOSE}" = "Y" ]; then
	echo "TARGET_DISTRO=${TARGET_DISTRO}"
	echo "TARGET_ARCH=${TARGET_ARCH}"
	if [ ! -z "${TARGET_EDITION}" ]; then
		echo "TARGET_EDITION=${TARGET_EDITION}"
	fi
	echo "TARGET_OUTPUT=${TARGET_OUTPUT}"
	echo "TARGET_LOCALE=${TARGET_LOCALE}"
	echo "TARGET_TIMEZONE=${TARGET_TIMEZONE}"
	echo "TARGET_NAME=${TARGET_NAME}"
	echo "TARGET_TAG=${TARGET_TAG}"
	echo "TARGET_OUTPUT=$(basename "${TARGET_OUTPUT}")"
	echo "TARGET_MAKE=${TARGET_MAKE}"
	echo "TARGET_UPDATE=${TARGET_UPDATE}"
	echo "TARGET_IMPORT=${TARGET_IMPORT}"
	echo "TARGET_PUSH=${TARGET_PUSH}"
	echo "TARGET_QEMU=${TARGET_QEMU}"
	echo ""
	echo "INCLUDE_PACKAGES=${INCLUDE_PACKAGES}"
	echo "EXCLUDE_PACKAGES=${EXCLUDE_PACKAGES}"
	echo ""
	echo "EXTRA_ARGS=${EXTRA_ARGS}"
	echo ""
	if [ "${QUIET}" != "Y" ]; then
		echo "Do you want to do this now? [y|N]"
		read -r confirm
		if [[ ${confirm} =~ ^([yY][eE][sS]|[yY])$ ]]; then
			echo ""
		else
			fn_usage
		fi
	fi
fi

if [ -e /sbin/apk ]; then
	apk add util-linux
fi

#prepare
fn_target_unmount

#Check arch linux
if [ "${TARGET_DISTRO}" = "arch" ] && [ "${TARGET_MAKE}" != "Y" ]; then
	if [ -z "$(ls ${TARGET_OUTPUT}/etc/ca-certificates/extracted)" ]; then
		TARGET_MAKE=Y
	fi
fi

#Make
if [ "${TARGET_MAKE}" = "Y" ]; then
	if [ "${IS_DOCKER}" = "Y" -a -e /etc/alpine-release ]; then
		rm -rf "${TARGET_OUTPUT}" || (echo "Cannot remove ${TARGET_OUTPUT}" ; exit 1)
		mkdir -p "${TARGET_OUTPUT}" || (echo "Cannot create ${TARGET_OUTPUT}" ; exit 1)
		chmod 755 ${TARGET_OUTPUT}

		eval fn_make_${TARGET_DISTRO}
	else
		if [ "${IS_DOCKER}" = "Y" ]; then
			echo "Cannot execute in docker (2)"
			exit 1
		else
			tgt="$(echo "${TARGET_OUTPUT}" | sed -e "s#$(realpath "$(pwd)")#/build#g")"
			fn_run_docker -d "${TARGET_DISTRO}" -a "${TARGET_ARCH}" $([ ! -z "${TARGET_EDITION}" ] && echo "-e ${TARGET_EDITION}") -o "${tgt}" -l "${TARGET_LOCALE}" -z "${TARGET_TIMEZONE}" $([ ! -z "${INCLUDE_PACKAGES}" ] && echo "--include \"${INCLUDE_PACKAGES}\"") $([ ! -z "${EXCLUDE_PACKAGES}" ] && echo "--exclude \"${EXCLUDE_PACKAGES}\"") -n "${TARGET_NAME}:${TARGET_TAG}" -m -u -q ${EXTRA_ARGS[*]}
			TARGET_UPDATE=N
		fi
	fi
fi

#Update
if [ "${TARGET_UPDATE}" = "Y" ]; then
	if [ "${IS_DOCKER}" = "Y" -a -e /etc/alpine-release ]; then
		eval fn_update
	else
		if [ "${IS_DOCKER}" = "Y" ]; then
			echo "Cannot execute in docker (3)"
			exit 1
		else
			tgt="$(echo "${TARGET_OUTPUT}" | sed -e "s#$(realpath "$(pwd)")#/build#g")"
			fn_run_docker -d "${TARGET_DISTRO}" -a "${TARGET_ARCH}" $([ ! -z "${TARGET_EDITION}" ] && echo "-e ${TARGET_EDITION}") -o "${tgt}" -l "${TARGET_LOCALE}" -z "${TARGET_TIMEZONE}" $([ ! -z "${INCLUDE_PACKAGES}" ] && echo "--include \"${INCLUDE_PACKAGES}\"") $([ ! -z "${EXCLUDE_PACKAGES}" ] && echo "--exlcude \"${EXCLUDE_PACKAGES}\"") -n "${TARGET_NAME}:${TARGET_TAG}" -u -q ${EXTRA_ARGS[*]}
		fi
	fi
fi

#clean
rm -rf ${TARGET_OUTPUT}/qemu_*.core

#dockerenv
if [ "${IS_DOCKER}" = "Y" ]; then
	if [ "${TARGET_MAKE}" != "Y" -a "${TARGET_UPDATE}" != "Y" ]; then
		echo "Cannot exeucte in docker (4)"
	fi
	exit
fi

#Import
if [ "${IS_DOCKER}" != "Y" -a "${TARGET_IMPORT}" = "Y" ]; then
	fn_import
fi

#Push
if [ "${IS_DOCKER}" != "Y" -a "${TARGET_PUSH}" = "Y" ]; then
	fn_push
fi

umount dist &> /dev/null || true

