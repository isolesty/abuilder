#!/bin/bash

# all path in this script shuould be complete path
INITSCRIPT="initbuild"

# TODO: use tmpfs to build
#BUILD_PLACE="/dev/shm/build-"

BASE_TGZ="/var/cache/pbuilder/rebuild.tgz"

X86_LIST="/tmp/x86.list"
# X86_SWITCH is set to get source from x86 directly
X86_SWITCH=0
# build failed flag, ignore this package
FAILED_FLAG=0

RESULT_DIR="/home/deepin/pbuilder-results"
RESULT_BACKUP_DIR="/home/deepin/pbuilder-results-backup"

REPOS="/home/deepin/rebuild-repos"
# record the *_all.deb, which should not been built
RECORD_LIST_FILE="checked_all.list"

BUILD_TMP_DIR="/tmp/rebuild"

BUILD_LIST=""

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
	sudo apt update
}

prepare_source()
{
	echo "get source: $1"
	mkdir -p $1 && cd $1

	# get source from x86 directly
	if [[ ${X86_SWITCH} -eq 1 ]]; then
		get_source_x86 $1
	else
		apt source $1
		
		dsc_file=$(ls ./ | grep 'dsc')
		if [[ x${dsc_file} == "x" ]]; then
			# failed to get package source from arch repos
			# try x86 repo
			get_source_x86 $1
		fi
	fi

	dsc_file=$(ls ./ | grep 'dsc')
	# cd back to ${BUILD_TMP_DIR}
	cd - > /dev/null

	if [[ x${dsc_file} == "x" ]]; then
		# failed to get source from x86 too
		return 1
	fi

	# get source successfully
	update_version $1
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
	sudo pbuilder --build --basetgz ${BASE_TGZ} --buildresult ${RESULT_DIR} --hookdir /var/cache/pbuilder/hooks/ --logfile ${RESULT_DIR}/buildlog --debbuildopts -sa $1/$1*.dsc

	if [[ $? -ne 0 ]]; then
		# failed to build
		echo "Failed to build $1."
		# TODO: check the error, rebuild it or not

		# now, if build failed in pbuilder, run the C10shell in pbuilder
		clean_build $1
		exit 1
	fi
}

clean_build()
{
	rm -rf ${BUILD_TMP_DIR}/$1
	# reset RESULT_DIR
	RESULT_DIR="/home/deepin/pbuilder-results"
	# reset X86_SWITCH
	X86_SWITCH=0
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
	search_pack=$(reprepro -b ${REPOS} list unstable | grep source | grep -w $1 | awk '{print $2}' | grep $1$ | grep ^$1 )

	if [[ ${search_pack} == $1 ]]; then
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
	line=$1
	# $2 is a flag
	if [[ x$2 == "xx86" ]]; then
		X86_SWITCH=1
	elif [[ x$2 == "xfailed" ]]; then
		FAILED_FLAG=1
	fi
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
		# special format in $line, split it to normal package name
		# split_line example: split_line aaa x86
		split_line $line

		if [[ ${FAILED_FLAG} -eq 1 ]]; then
			# build failed before
			echo "${line} cann't build."
			# reset FAILED_FLAG
			FAILED_FLAG=0
			continue
		fi

		if build_pass ${line}; then
			# if ${line} is in repo, pass this build
			echo "${line} had been built."
			continue
		fi

		if prepare_source ${line}; then
			if check_all ${line}; then
				rebuild ${line}
			else
				echo ${line} "is arch independent. Build pass."
				continue
			fi
		fi

		clean_build ${line}
		
	done < ${BUILD_LIST}
}

init
main $@
clean
