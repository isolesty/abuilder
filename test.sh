#!/bin/bash

# TODO: use pbuilder check build depends

### return 1 for build, return 0 for build pass

BUILD_PLACE="/dev/shm/rebuild"
BUILD_IN_MEMORY=0

BASE_TGZ="/var/cache/pbuilder/rebuild.tgz"

X86_LIST="/tmp/x86.list"
# X86_SWITCH is set to get source from x86 directly
X86_SWITCH=0
# build failed flag, ignore this package
FAILED_FLAG=0

# enable pacakges' name build
SOURCE_NAME=''
PACKAGE_NAME=''
# enable version update build
SOURCE_VERSION=''
REPO_VERSION=''
VERSION_CHECK=0

# build all packages
NO_SKIP_ALL=1

RESULT_DIR="$HOME/pbuilder-results"
RESULT_BACKUP_DIR="$HOME/pbuilder-results-backup"

REPOS="$HOME/rebuild-repos"
# record the *_all.deb, which should not been built
RECORD_LIST_FILE="checked_all.list"

BUILD_TMP_DIR="/tmp/rebuild"

BUILD_LIST=""
TMP_BUILD_LIST=""

# path of scripts
# all path in this script shuould be complete path
INITSCRIPT="$HOME/rebuild-scripts/initbuild"
SCRIPT_PATH="$HOME/rebuild-scripts/test.sh"
if [[ ! -f ${SCRIPT_PATH} ]]; then
	echo "Check the script path failed."
	echo "Set SCRIPT_PATH in this script correctly."
	exit 9
fi

# use this to check the build depends
BACKUP_CHROOT="/var/cache/pbuilder/build/check"

init()
{
	# check the init script
	# init script should create the local repo
	if [[ -f ${INITSCRIPT} ]]; then
		source ${INITSCRIPT}
	else
		echo "Missing init scripts. Exit."
		exit 1
	fi

	mkdir -p ${RESULT_DIR}
	mkdir -p ${RESULT_BACKUP_DIR}

	mkdir -p ${BUILD_TMP_DIR}

	# check the repo
	if [[ ! -d ${REPOS} ]]; then
		init_repo ${REPOS}
	fi

	# TODO: add init_pbuilder

	# check the log file
	if [[ ! -f ${REPOS}/${RECORD_LIST_FILE} ]]; then
		touch ${REPOS}/${RECORD_LIST_FILE}
	fi

	cd ${BUILD_TMP_DIR}
}

clean()
{
	echo "Clean"
	if [[ -d ${BUILD_TMP_DIR} ]]; then
		rm -rf ${BUILD_TMP_DIR}
	fi

	if [[ -d ${RESULT_DIR} ]]; then
		rm -rf ${RESULT_DIR}
	fi

	if [[ -f ${X86_LIST} ]]; then
		rm ${X86_LIST}
	fi
	
}

# get source from x86
get_source_x86()
{
	echo "get source from x86: $1"
	# create x86_list
	if [[ ! -f ${X86_LIST} ]]; then
		create_x86_list ${X86_LIST}
	fi

	sudo apt -oDir::Etc::SourceList=${X86_LIST} update 
	apt -oDir::Etc::SourceList=${X86_LIST} source $1

}

prepare_source()
{
	echo "get source: $1"
	mkdir -p $1 && cd $1

	# get source from x86 directly
	if [[ ${X86_SWITCH} -eq 1 ]]; then
		get_source_x86 ${SOURCE_NAME}
	else
		sudo apt update
		apt source ${SOURCE_NAME}
		
		# TODO: document this special method for the special source code
		# sometimes, prepare a special source before the script runs
		# so don't check the $(apt source)'s return code 
		dsc_file=$(ls ./ | grep 'dsc')
		if [[ x${dsc_file} == "x" ]]; then
			# failed to get package source from arch repos
			# try x86 repo
			get_source_x86 ${SOURCE_NAME}
		fi
	fi

	dsc_file=$(ls ./ | grep 'dsc')
	# cd back to ${BUILD_TMP_DIR}
	cd ${BUILD_TMP_DIR} > /dev/null

	if [[ x${dsc_file} == "x" ]]; then
		# failed to get source from x86 too
		return 1
	else
		# check the dsc name
		dsc_name=$(echo ${dsc_file} | awk -F'_' '{print $1}')
		# ${line} in ${BUILD_LIST} is a source name
		if [[ x${dsc_name} == x${SOURCE_NAME} ]]; then
			#statements
			echo "SOURCE_NAME is ${dsc_name}"
		else
			# ${line} in ${BUILD_LIST} is a package name
			echo "Get source ${dsc_name} from ${SOURCE_NAME}"
			echo "Set SOURCE_NAME to ${dsc_name}"
			# mv the tobuild dir name from package name to source name
			if [[ -d ${dsc_name} ]]; then
				# sometimes failed build source exists in ${BUILD_TMP_DIR}, remove it
				rm -rf ${dsc_name}
			fi
			mv -v ${SOURCE_NAME} ${dsc_name}
			
			# backup the SOURCE_NAME and set it to the dsc file's name
			PACKAGE_NAME=${SOURCE_NAME}
			SOURCE_NAME=${dsc_name}
		fi
	fi

	return 0

}


# set rebuild version to ***deepin1 or ***deepin2
update_version()
{
	cd $1/$1-*
	# example: tree (1.7.0-5deepin) unstable; urgency=medium
	nmu=$(cat debian/changelog | head -n 1 | awk '{print $2}' | sed 's/(\(.*\))/\1/g')
	if [[ ${nmu:0 -6:6} == 'deepin' ]]; then
		# package's version endswith deepin
		dch -D unstable -m -v ${nmu}1 "rebuild"
	else
		dch -D unstable -m -l deepin "rebuild"
	fi

	# clean old dsc
	rm ../*.dsc
	# create new dsc
	dpkg-source -b .
	cd ${BUILD_TMP_DIR} > /dev/null

}

compare_version()
{
	# compare the version
	# ${SOURCE_NAME} should be set correctly
	if [[ ${VERSION_CHECK} -eq 1 ]]; then
		SOURCE_VERSION=$(echo ${dsc_file} | awk -F'_' '{print $2}' | sed 's/.dsc//')
		# use the repo dir to get the right version
		# example: /home/deepin/rebuild-repos/pool/main/d/dde/dde_15.4+10deepin1.dsc
		REPO_VERSION=$( find ${REPOS}/ -type f -name "$1*.dsc" | awk -F'/' '{print $NF}' | grep ^$1 | grep $1_ | awk -F'_' '{print $2}' | sed 's/.dsc//')
		# source version in repos should be xxxdeepin*, ignore the deepin*
		# REPO_VERSION=${REPO_VERSION%%deepin*}

		# use command dpkg to compare the version
		dpkg --compare-versions ${SOURCE_VERSION} gt ${REPO_VERSION}
		if [[ $? -eq 0 ]]; then
			# ${SOURCE_VERSION} is greater than ${REPO_VERSION}, shoule build it
			echo "${SOURCE_VERSION} is a update build"
			return 0
		else
			# pass this build
			echo "Same version in repos, pass this build"
			remove_passed_package ${SOURCE_NAME}
			return 1
		fi
	else
		# no ${VERSION_CHECK} set, build it anyway
		return 0
	fi

}

prepare_build()
{
	echo "Prepare to build $1"
	RESULT_DIR=${RESULT_DIR}/$1

	mkdir -p ${RESULT_DIR}
}

run_pbuilder()
{
	echo "Use pbuilder to build $1"

	# check the free memory
	free_memory=$(free | grep Mem | awk '{print $4}')
	# enable build in memory if free memory more than 10G
	# TODO: enable this
	if [[ ${free_memory} -gt 10000000 ]]; then
		BUILD_IN_MEMORY=1
		BUILD_PLACE="${HOME}/build-tmpdir/chroot-autobuild-tmpfs"
		mkdir -p ${HOME}/build-tmpdir/chroot-autobuild

		sudo mkdir -p /dev/shm/build-shm
		sudo mkdir -p /dev/shm/build-work

		mkdir -p ${BUILD_PLACE}

		sudo mount -t overlay overlay -o lowerdir=${HOME}/build-tmpdir/chroot-autobuild,upperdir=/dev/shm/build-shm,workdir=/dev/shm/build-work ${BUILD_PLACE}

	fi

	# build log
	build_log=${RESULT_DIR}/buildlog
	if [[ ${BUILD_IN_MEMORY} -eq 1 ]]; then
		# use shm to build 
		sudo pbuilder --build --use-network yes --basetgz ${BASE_TGZ} --buildplace ${BUILD_PLACE} --buildresult ${RESULT_DIR} --hookdir /var/cache/pbuilder/hooks/ --logfile ${build_log} --debbuildopts -sa $1/$1*.dsc
	else
		sudo pbuilder --build --use-network yes --basetgz ${BASE_TGZ} --buildresult ${RESULT_DIR} --hookdir /var/cache/pbuilder/hooks/ --logfile ${build_log} --debbuildopts -sa $1/$1*.dsc
	fi

	if [[ $? -ne 0 ]]; then
		# failed to build
		echo "Failed to build $1."
		clean_build $1
		
		iter_build_depends ${build_log}

		# now, if build failed in pbuilder, run the C10shell in pbuilder
		# TODO: if the depends is a arch independent, the script will run in a loop
		exit 1
	fi
}

iter_build_depends()
{
	build_error_log=$1
	# generate new BUILD_LIST
	TMP_BUILD_LIST="/tmp/tmpbuild-$(date +%s)"
	# examples:
	# pbuilder-satisfydepends-dummy : Depends: erlang-base which is a virtual package and is not provided by any available package.
    #                             Depends: php5 which is a virtual package and is not provided by any available package.
    #                             Depends: php5-dev which is a virtual package and is not provided by any available package.
	grep 'which is a virtual package' ${build_error_log} |  sed 's/.*Depends: //g' | awk '{print $1}' > ${TMP_BUILD_LIST}

	# build the depends
	# ${TMP_BUILD_LIST} should be exist
	if [[ ! -f ${TMP_BUILD_LIST}  ]]; then
		echo "Failed to check the depends for ${SOURCE_NAME}"
		exit 2
	fi
	if [[ $(stat -t ${TMP_BUILD_LIST} | awk '{print $2}') -eq 0 ]]; then
		# TMP_BUILD_LIST is empty
		echo "Generate the depends for ${SOURCE_NAME} failed"
		exit 3
	else
		# TODO: disable
		# add this failed build to TMP_BUILD_LIST
		# echo ${SOURCE_NAME} >> ${TMP_BUILD_LIST}
		bash ${SCRIPT_PATH} ${TMP_BUILD_LIST}
	fi
}


clean_build()
{
	# clean $(apt source xxx) files
	if [[ -d ${BUILD_TMP_DIR}/${SOURCE_NAME} ]]; then
		rm -rf ${BUILD_TMP_DIR}/${SOURCE_NAME}
	fi
	
	# reset RESULT_DIR
	RESULT_DIR="$HOME/pbuilder-results"

	# clean build place
	if [[ ${BUILD_IN_MEMORY} -eq 1 ]]; then
		while grep -q "${HOME}/build-tmpdir/chroot-autobuild-tmpfs" /proc/mounts;do
			    sudo umount -l "${HOME}/build-tmpdir/chroot-autobuild-tmpfs" || true
			    sleep 1
		done

		if [ -d "${HOME}/build-tmpdir/chroot-autobuild-tmpfs" ];then
			   sudo rm -rf /dev/shm/build-shm
			   sudo rm -rf /dev/shm/build-work
		fi
		if [[ -d ${HOME}/build-tmpdir ]]; then
			sudo rm -rf ${HOME}/build-tmpdir
		fi
	fi

}

reprepro_include()
{
	cd $REPOS
	reprepro includedsc unstable ${RESULT_DIR}/*.dsc
	if [[ $? -ne 0 ]]; then
		# try to includedsc with default parameters
		# fix the *.dsc missing these fileds
		reprepro -S utils -P optional includedsc unstable ${RESULT_DIR}/*.dsc
	fi
	reprepro includedeb unstable ${RESULT_DIR}/*.deb
	reprepro includeudeb unstable ${RESULT_DIR}/*.udeb

	cd ${BUILD_TMP_DIR} > /dev/null
}

backup_result()
{
	# RESULT_DIR has been changed in function prepare_build()
	# clean old RESULT_DIR in RESULT_BACKUP_DIR
	if [[ -d ${RESULT_BACKUP_DIR}/$1 ]]; then
		rm -rf ${RESULT_BACKUP_DIR}/$1
	fi
	mv -v ${RESULT_DIR} ${RESULT_BACKUP_DIR}/
}

rebuild()
{
	prepare_build $1

	if compare_version $1 ; then
		update_version $1
		run_pbuilder $1
		reprepro_include $1
		backup_result $1
	fi
	
}

check_all()
{
	# if NO_SKIP_ALL is set, build all pacakges
	if [[ ${NO_SKIP_ALL} -eq 1 ]]; then
		# return code 0 to build the ${SOURCE_NAME}
		return 0
	fi

	# example:
	# Architecture: any all
	pack_arch=$(cat $1/$1*.dsc | grep 'Architecture:' | awk -F': ' '{print $2}')
	if [[ ${pack_arch} == 'all' ]]; then
		# pass the packages only build all files
		# clean source
		clean_build $1

		# echo this package to record file
		echo $1 >> ${REPOS}/${RECORD_LIST_FILE}
		# return 1 to pass this build
		return 1
	fi
}

# check the package had been build
build_pass()
{
	# only grep the word $1, not *$1*, *$1-* and *-$1*
	# TODO: $1-$1 is still in this grep result
	search_source=$(reprepro -b ${REPOS} list unstable | grep source: | grep -w $1 | awk '{print $2}' | grep $1$ | grep ^$1 )
	search_pack=$(reprepro -b ${REPOS} list unstable | grep mips64el: | grep -w $1 | awk '{print $2}' | grep $1$ | grep ^$1 )

	if [[ ${search_source} == $1 || ${search_pack} == $1 ]]; then
		# package had been built 
		# compare the repos version and the build version
		VERSION_CHECK=1
		return 1
	else
		# if NO_SKIP_ALL is set, build all pacakges
		if [[ ${NO_SKIP_ALL} -eq 1 ]]; then
			# return code 1 to build the ${SOURCE_NAME}
			return 1
		else
			# check the record file of tested all packages
			pack_all=$(cat ${REPOS}/${RECORD_LIST_FILE} | grep -w $1 | grep $1$ | grep ^$1 )
			if [[ ${pack_all} == $1 ]]; then
				# return 0 to pass this build
				return 0
			fi
			return 1
		fi		
	fi
}


# usage example: split_line aaa x86
split_line()
{
	# $1 must be a package name or a source name
	SOURCE_NAME=$1
	PACKAGE_NAME=$1
	# $2 is a flag
	if [[ x$2 == "xx86" ]]; then
		X86_SWITCH=1
	elif [[ x$2 == "xfailed" ]]; then
		FAILED_FLAG=1
	# elif [[ x$2 == "xsource" ]]; then
	# 	SOURCE_FLAG=1
	# 	# set get source name, used in apt source
	# 	GET_SOURCE_NAME=$3
	fi
}

# remove all and build pacakges in ${BUILD_LIST}
# always remove PACKAGE_NAME, not the SOURCE_NAME
remove_passed_package()
{

	if [[ -f ${BUILD_LIST} ]]; then
		echo "delete ${PACKAGE_NAME} from ${BUILD_LIST}"
		sed -i "/^${PACKAGE_NAME}$/d" ${BUILD_LIST}
	fi
}


# check build depends
# TODO: do this in normal env, not in a chroot environment
check_build_depends()
{
	echo "Pass."
}

main()
{
	# support multi lists
	if [[ x$1 != "x" ]];then
	        BUILD_LIST=$1
	else
	        BUILD_LIST="/tmp/packs.list"
	        to_build_list ${BUILD_LIST}
	fi

	while read -r line; do
		# if $line is a blank line, ignore it
		if [[ x${line} == 'x' ]]; then
			continue
		fi
		# reset X86_SWITCH
		X86_SWITCH=0
		# reset BUILD_IN_MEMORY
		BUILD_IN_MEMORY=0
		# reset check version
		VERSION_CHECK=0

		# special format in $line, split it to normal package name
		# set the ${SOURCE_NAME}
		# split_line example: split_line aaa x86
		split_line ${line}


		if [[ ${FAILED_FLAG} -eq 1 ]]; then
			# build failed before
			echo "${SOURCE_NAME} cann't build."
			# reset FAILED_FLAG
			FAILED_FLAG=0
			continue
		fi

		if build_pass ${SOURCE_NAME}; then
			# if ${SOURCE_NAME} is in repo, pass this build
			echo "${SOURCE_NAME} had been built."
			# remove it from ${BUILD_LIST}
			remove_passed_package ${SOURCE_NAME}
			continue
		fi

		if prepare_source ${SOURCE_NAME}; then
			# ${SOURCE_NAME} may be reset in prepare_source and different from ${SOURCE_NAME} 
			if check_all ${SOURCE_NAME}; then
				rebuild ${SOURCE_NAME}
			else
				echo ${SOURCE_NAME} "is arch independent. Build pass."
				# remove it from ${BUILD_LIST}
				remove_passed_package ${SOURCE_NAME}
				continue
			fi
		fi

		clean_build ${line}
		
	done < ${BUILD_LIST}
}

init
main $@
clean