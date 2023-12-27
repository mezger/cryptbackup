#!/bin/bash
########################################################
# cryptbackup
# (c)2016 Matthias Mezger
#
# prepare/encrypt partition (e.g.: /dev/sdg1):
# root@pc:~# cryptsetup luksFormat -c aes-xts-plain64 -s 512 /dev/sdg1
# find UUID of encrypted partition:
# root@pc:~# lsblk -l -o +UUID /dev/sdg1
########################################################
#set -x


function show_usage_and_exit {
    echo -e "usage: ${0} <projectname>"
    exit 1
}


function check_prerequisites {
    # auf UID=root prüfen
    if [ $(id -u) -ne 0 ]; then
        echo -e "ERROR: you must be root to run ${0}!"
        exit 1
    fi

    # prüfen ob notwendige executables existieren
    # TODO readlink, cryptsetup, mount, rsync, umount, id
}


function parse_commandline {
    if [ ${#} -ne 1 ]; then
        echo -e "ERROR: wrong number of parameters!"
        show_usage_and_exit
    fi
    PROJECT=${1}
    SCRIPTNAME=${0##*/}
    SCRIPTNAME=${SCRIPTNAME%.sh}
    local SCRIPTPATH=$(/bin/readlink -f ${0})
    HOST=$(hostname -s)
    # CFGFILE=${SCRIPTPATH%.sh*}-${PROJECT}.conf
    CFGFILE=/etc/${SCRIPTNAME}/${PROJECT}.conf
    # EXCLUDESFILE=${SCRIPTPATH%.sh*}-${PROJECT}.excludes
    EXCLUDESFILE=/etc/${SCRIPTNAME}/${PROJECT}.excludes
}


function read_project_config {
    if [ ! -r ${CFGFILE} ]; then
        echo -e "ERROR: configfile \"${CFGFILE}\" for project \"${PROJECT}\" does not exist!"
        exit 1
    fi
    # source configfile
    . ${CFGFILE}
}


function read_project_excludes {
  EXCLUDESPARAM=
	if [ -r ${EXCLUDESFILE} ]; then
    if [ "${OPERATION_MODE}" == "sync" ]; then
      EXCLUDESPARAM=--exclude-from=${EXCLUDESFILE}
    elif [ "${OPERATION_MODE}" == "backup" ]; then
      EXCLUDESPARAM="--exclude-globbing-filelist ${EXCLUDESFILE}"
    fi
	fi
	return 0
}


function check_params {
	if [ ! -r ${SOURCE_DIR} ]; then
		echo -e "ERROR: source dir \"${SOURCE_DIR}\" does not exist!"
		exit 1
	fi
}


function set_variables {
	HOST=$(hostname -s)
	TARGET=/dev/disk/by-uuid/${TARGET_UUID}
	MAPPERNAME=${SCRIPTNAME}-${HOST}-${PROJECT}
	MOUNTPATH=/media/${MAPPERNAME}
}


function check_and_open_target_device {
	echo -e "checking device ${TARGET}..."

	if ! $(/sbin/cryptsetup isLuks ${TARGET}); then
	  echo -e "ERROR: target device ${TARGET} is no luks crypto device!"
	  exit 1
	fi

	echo -e "opening ${TARGET} as ${MAPPERNAME}..."

	/sbin/cryptsetup luksOpen ${TARGET} ${MAPPERNAME}
	RESULT=$?
	if [ ! $RESULT ]; then
	  echo -e "ERROR: could not luksOpen target ${TARGET} as ${MAPPERNAME}!"
	  exit 1
	fi

	/sbin/cryptsetup status ${MAPPERNAME}
	RESULT=$?
	if [ ! $RESULT ]; then
	  echo -e "ERROR: cryptopartition ${TARGET} is not ready!"
	  exit 1
	fi

	# TODO prüfen ob ${MOUNTPATH} leer ist
	[ -d ${MOUNTPATH} ] || mkdir ${MOUNTPATH}

	echo -e "mounting ${MAPPERNAME} as ${MOUNTPATH}..."

	/bin/mount /dev/mapper/${MAPPERNAME} ${MOUNTPATH}
	RESULT=$?
	if [ ! $RESULT ]; then
	  echo -e "ERROR: could not mount ${MAPPERNAME} as ${MOUNTPATH}!"
	  exit 1
	fi

	if [ ! -d ${MOUNTPATH}/${HOST}/${PROJECT}  ]; then
	  echo -e "ERROR: target directory ${MOUNTPATH}/${HOST}/${PROJECT} not found!"
	  exit 1
	fi
}


function do_backup {
  if [ "${OPERATION_MODE}" == "sync" ]; then
    echo -e "starting rsync job ${PROJECT}..."
#/usr/bin/rsync ${RSYNC_PARAMS} ${EXCLUDESPARAM} "${SOURCE_DIR}" "${MOUNTPATH}/${HOST}/${PROJECT}"
    echo -e "finished rsync job ${PROJECT}"
	elif [ "${OPERATION_MODE}" == "backup" ]; then
		echo -e "starting backup job ${PROJECT}..."
    /usr/bin/rdiff-backup ${EXCLUDESPARAM} "${SOURCE_DIR}" "${MOUNTPATH}/${HOST}/${PROJECT}"
    sleep 3
    echo -e "finished backup job ${PROJECT}"
	else
		echo -e "ERROR: invalid operation mode!"
	fi
}


function close_target_device {
	echo -e "unmounting ${MOUNTPATH}..."

	/bin/umount ${MOUNTPATH}

	echo -e "closing ${MAPPERNAME}..."

	/sbin/cryptsetup luksClose ${MAPPERNAME}
}


# main script
check_prerequisites
parse_commandline ${@}
read_project_config
read_project_excludes
check_params
set_variables
echo -e "${SCRIPTNAME} project \"${PROJECT}\" on \"${HOST}\""
check_and_open_target_device
do_backup
close_target_device
echo -e "backup done."
exit 0


### ab hier alt ###

########################################################
# Parameter "Projektname"
if [ ${#} -ne 1 ]; then
	echo -e "usage: ${0} <projectname>"
	exit 1
fi

PROJECT=${1}
SCRIPTNAME=${0##*/}
SCRIPTNAME=${SCRIPTNAME%.sh}
SCRIPTPATH=$(/bin/readlink -f ${0})

# auf UID=root prüfen
if [ $(id -u) -ne 0 ]; then
	echo -e "ERROR: you must be root to run ${0}!"
	exit 1
fi

# prüfen ob notwendige executables existieren
# TODO readlink, cryptsetup, mount, rsync, umount

# prüfen ob Konfigdatei existiert
CFGFILE=${SCRIPTPATH%.sh*}-${PROJECT}.conf
if [ ! -r ${CFGFILE} ]; then
	echo -e "ERROR: configfile \"${CFGFILE}\" for project \"${PROJECT}\" does not exist!"
	exit 1
fi

# prüfen ob Excludesdatei existiert
EXCLUDESFILE=${SCRIPTPATH%.sh*}-${PROJECT}.excludes
if [ ! -r ${EXCLUDESFILE} ]; then
	echo -e "ERROR: excludesfile \"${EXCLUDESFILE}\" for project \"${PROJECT}\" does not exist!"
	exit 1
fi

# Konfigdatei einlesen
. ${CFGFILE}

# Parameter prüfen
if [ ! -r ${SOURCE_DIR} ]; then
	echo -e "ERROR: source dir \"${SOURCE_DIR}\" does not exist!"
	exit 1
fi

# hostname ermitteln
HOST=$(hostname -s)

TARGET=/dev/disk/by-uuid/${TARGET_UUID}
MAPPERNAME=${SCRIPTNAME}-${HOST}-${PROJECT}
MOUNTPATH=/media/${MAPPERNAME}

echo -e "${SCRIPTNAME} project \"${PROJECT}\" on \"${HOST}\""

# prüfen ob zieldevice mit luks verschlüsselt ist
echo -e "checking device ${TARGET}..."
if ! $(/sbin/cryptsetup isLuks ${TARGET}); then
  echo -e "ERROR: target device ${TARGET} is no luks crypto device!"
  exit 1
fi

echo -e "opening ${TARGET} as ${MAPPERNAME}..."
/sbin/cryptsetup luksOpen ${TARGET} ${MAPPERNAME}
RESULT=$?
if [ ! $RESULT ]; then
  echo -e "ERROR: could not luksOpen target ${TARGET} as ${MAPPERNAME}!"
  exit 1
fi

/sbin/cryptsetup status ${MAPPERNAME}
RESULT=$?
if [ ! $RESULT ]; then
  echo -e "ERROR: cryptopartition ${TARGET} is not ready!"
  exit 1
fi

# TODO prüfen ob ${MOUNTPATH} leer ist
[ -d ${MOUNTPATH} ] || mkdir ${MOUNTPATH}

echo -e "mounting ${MAPPERNAME} as ${MOUNTPATH}..."
/bin/mount /dev/mapper/${MAPPERNAME} ${MOUNTPATH}
RESULT=$?
if [ ! $RESULT ]; then
  echo -e "ERROR: could not mount ${MAPPERNAME} as ${MOUNTPATH}!"
  exit 1
fi

if [ ! -d ${MOUNTPATH}/${HOST}/${PROJECT}  ]; then
  echo -e "ERROR: target directory ${MOUNTPATH}/${HOST}/${PROJECT} not found!"
  exit 1
fi

# excludes
#for INDEX in $(seq 0 $((${#SYNC_SOURCE_EXCLUDES[@]}-1)))
#do
#	EXCLUDES+=("--exclude \"${SYNC_SOURCE_EXCLUDES[INDEX]}\" ")
#done

#echo -e "excludes: ${EXCLUDES[@]}"


echo -e "starting rsync backup job..."
/usr/bin/rsync ${SYNC_PARAMS} --exclude-from=${EXCLUDESFILE} "${SOURCE_DIR}" "${MOUNTPATH}/${HOST}/${PROJECT}"
#/usr/bin/rsync -a -x --delete --delete-before --exclude /backup --exclude /media --exclude /cdrom --exclude /tmp --exclude /dev --exclude /floppy --exclude /lost+found --exclude /mnt --exclude /proc --exclude /sys  --exclude /export --exclude ${MOUNTPATH} / ${MOUNTPATH}/${HOST}/${PROJECT}

echo -e "unmounting ${MOUNTPATH}..."
/bin/umount ${MOUNTPATH}

echo -e "closing ${MAPPERNAME}..."
/sbin/cryptsetup luksClose ${MAPPERNAME}

echo -e "backup done."
