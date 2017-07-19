#!/bin/bash

# TODO: use pbuilder check build depends

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
		
		dsc_file=$(ls ./ | grep 'dsc')
		if [[ x${dsc_file} == "x" ]]; then
			# failed to get package source from arch repos
			# try x86 repo
			get_source_x86 ${SOURCE_NAME}
		fi
	fi

	dsc_file=$(ls ./ | grep 'dsc')
	# cd back to ${BUILD_TMP_DIR}
	cd - > /dev/null

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
			
			SOURCE_NAME=${dsc_name}
		fi
	fi

	# get source successfully
	update_version ${SOURCE_NAME}
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
	cd - > /dev/null

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
		BUILD_IN_MEMORY=0
		sudo mkdir -p ${BUILD_PLACE}
	fi

	# 
	if [[ ${BUILD_IN_MEMORY} -eq 1 ]]; then
		# use shm to build 
		sudo pbuilder --build --use-network yes --basetgz ${BASE_TGZ} --buildplace ${BUILD_PLACE} --buildresult ${RESULT_DIR} --hookdir /var/cache/pbuilder/hooks/ --logfile ${RESULT_DIR}/buildlog --debbuildopts -sa $1/$1*.dsc
	else
		sudo pbuilder --build --use-network yes --basetgz ${BASE_TGZ} --buildresult ${RESULT_DIR} --hookdir /var/cache/pbuilder/hooks/ --logfile ${RESULT_DIR}/buildlog --debbuildopts -sa $1/$1*.dsc
	fi

	if [[ $? -ne 0 ]]; then
		# failed to build
		echo "Failed to build $1."
		
		iter_build_depends

		# after the function iter_build_depends, ${SOURCE_NAME} should be built
		# this clean_build may be failed
		clean_build $1

		# now, if build failed in pbuilder, run the C10shell in pbuilder
		# TODO: if the depends is a arch independent, the script will run in a loop
		exit 1
	fi
}

iter_build_depends()
{
	build_error_log=${RESULT_DIR}/buildlog
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
	cd - > /dev/null
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
	run_pbuilder $1
	reprepro_include $1
	backup_result $1
}

check_all()
{
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
		# return 0 to pass this build
		return 0
	else
		# check the record file of tested all packages
		pack_all=$(cat ${REPOS}/${RECORD_LIST_FILE} | grep -w $1 | grep $1$ | grep ^$1 )
		if [[ ${pack_all} == $1 ]]; then
			# return 0 to pass this build
			return 0
		fi

		return 1
	fi
}


# usage example: split_line aaa x86
split_line()
{
	# $1 must be a package name
	SOURCE_NAME=$1
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
# $1 is the ${line}
remove_passed_package()
{
	if [[ -f ${BUILD_LIST} ]]; then
		echo "delete $1 from ${BUILD_LIST}"
		sed -i "/^$1$/d" ${BUILD_LIST}
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
