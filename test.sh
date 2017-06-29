#!/bin/bash

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
	mkdir -p ${RESULT_DIR}
	mkdir -p ${RESULT_BACKUP_DIR}

	mkdir -p ${BUILD_TMP_DIR}

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
	# create x86_list
	if [[ ! -f ${X86_LIST} ]]; then
		create_x86_list
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
			# failed to get package source from mips64el repos
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
	reprepro includedeb unstable ${RESULT_DIR}/*.deb
	cd - > /dev/null
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


create_x86_list()
{
	echo "deb-src [trusted=yes] http://pools.corp.deepin.com/deepin unstable main contrib non-free" > ${X86_LIST}
}


to_build_list()
{
	if [[ ! -f ${BUILD_LIST} ]]; then
		echo "dogtag-pki failed
hfst-ospell
uthash
opencv x86
gvfs x86
libvoikko
ruby-ffi
tcl8.5
tk8.5
labltk
lablgl
gtkgl2
gtksourceview2
lablgtk2
camlp4
ounit
ocaml-re
ocamlgraph
cudf
checkpolicy
setools
cunit
libsepol x86
libselinux x86
libsemanage x86
a52dec
aalib
accountsservice
acl
acpid
acpi-support
adduser
adwaita-icon-theme
aisleriot
alabaster
albatross-gtk-theme
alien
allegro4.4
alsa-lib
alsa-plugins
alsa-utils
alure
anacron
anjuta
ann
ant
antlr
apache2
apparmor
appconfig
appstream-glib
apr
apr-util
apt
apt-file
aptitude
arduino
argyll
asciidoc
aspcud
aspell
aspell-en
astroid
atk1.0
atkmm1.6
atril
at-spi2-atk
at-spi2-core
attica-kf5
attr
auctex
audacious
audiofile
audit
autoconf
autoconf2.13
autoconf2.59
autoconf2.64
autoconf-archive
autogen
automake1.11
automake-1.15
automoc
autopkgtest
autotools-dev
avahi
avalon-framework
avfs
avrdude
avr-libc
bamf
base-files
base-passwd
bash
bash-completion
bats
bc
bcel
bcloud
bdfresize
beautifulsoup4
bf-utf
bind9
binfmt-support
bino
bison
bison27
blackbird-gtk-theme
blends
blinker
blt
bluebird-gtk-theme
bluefish
bluez
blur-effect
bogl
boost1.58
boost1.61
boost1.62
boost-defaults
boot-info-script
botan1.10
brasero
bridge-utils
brltty
bsd-mailx
bsdmainutils
btrfs-progs
build-essential
busybox
byzanz
bzip2
ca-certificates
ca-certificates-java
cairo
cairocffi
cairomm
caja
camlbz2
camlzip
c-ares
casablanca
cdbs
cdebconf
cdebootstrap
cdparanoia
cdrkit
cdrom-detect
ceph
cgmanager
chardet
check
cheese
cheetah
cherrypy3
chromaprint
chrpath
clasp
cld2
cloog
clucene-core
clutter-1.0
clutter-gst-3.0
clutter-gtk
cmake
cmdtest
cmocka
cm-super
codeblocks
gamin
glewmx
leveldb
libdumb
libs3
linuxdoc-tools
neon27
codelite
codenarc
cofoja
cogl
colorchooser
colord
colorpicker
colorspacious
commons-beanutils
commons-configuration
commons-csv
commons-daemon
commons-exec
commons-httpclient
commons-io
commons-javaflow
commons-jci
commons-jcs
commons-math
commons-math3
commons-parent
commons-pool
commons-pool2
commons-vfs
compress-lzf
concurrent-dfsg
configparser
confuse
consolekit
console-setup
conversant-disruptor
corebird
coreutils
cortado
cov-core
cowdancer
cpio
cppo
cppunit
cpufrequtils
cracklib2
crda
cron
crossguid
cryptsetup
cscope
cssparser
csvjdbc
cups
cups-filters
curl
curvesapi
cvc3
cwidget
cxxtest
cyrus-sasl2
cython
libidn2-0
gengetopt
dae
dash
datefudge
db5.3
db-defaults
dblatex
dbus
dbus-c++
dbus-factory
dbus-glib
dbus-java
dbus-python
d-conf
dconf-editor
dctrl-tools
debconf
debhelper
debian-archive-keyring
debian-astro
debiandoc-sgml
debian-games
debianutils
debootstrap
debtree
deja-dup
dejagnu
derby
desktop-base
desktop-file-utils
devhelp
devscripts
d-feet
dh-autoreconf
dh-buildinfo
dh-di
dh-exec
dh-golang
dh-lisp
dh-lua
dh-make
dh-ocaml
dh-python
dictionaries-common
diffstat
diffutils
directfb
dirgra
discount
discover
disruptor
distro-info
distro-info-data
djvulibre
dmidecode
dmraid
dmz-cursor-theme
dnprogs
dnsjava
dnsmasq
dnspython
dns-root-data
dnssecjava
docbook
docbook2x
docbook5-xml
docbook-dsssl
docbook-to-man
docbook-utils
docbook-xml
docbook-xsl
dokujclient
dom4j
dos2unix
dose3
dosfstools
dotconf
double-conversion
dovecot
downthemall
doxia
doxia-maven-plugin
doxia-sitetools
doxygen
dpatch
dpkg
dpkg-repack
dput
dropwizard-metrics
d-shlibs
dtd-parser
dumbster
duplicity
dvipng
dynalang
e2fsprogs
eag-healpix
easybind
easyconf
easymock
ebtables
ecj failed
eclipse failed
eclipse-aether
eclipselink
eclipselink-jpa-2.1-spec
ed
efibootmgr failed
efl
egenix-mx-base
ehcache
eigen3
eigenbase-farrago
eigenbase-resgen
eject
elasticsearch
elfutils
elinks
emacs24
emacs25
emacs-defaults
emacsen-common
emma-coverage
enca
encfs
enchant
engrampa
enum34
eom
eperl
epydoc
equivs
erlang failed
esound
espeak
espeak-ng
espeakup
etherwake
ethtool
evas-loaders
evince
excalibur-logger
excalibur-logkit
exec-maven-plugin
exempi
exim4
expat
expect
explorercanvas
extlib
extra-cmake-modules
exuberant-ctags
f2j
faad2
fakeroot
faketime
fam
famfamfam-flag
fannj
farstream-0.2
fastinfoset
fastjar
fcitx
fcitx-configtool
fcitx-qt5
fcitx-sunpinyin
fdupes
felix-bundlerepository
felix-framework
felix-gogo-command
felix-gogo-runtime
felix-gogo-shell
felix-main
felix-osgi-obr
felix-shell
felix-shell-tui
felix-utils
fest-assert
fest-reflect
fest-test
fest-util
ffmpeg
ffmpegthumbnailer
fftw3
file
file-roller
findbugs
findbugs-bcel
findlib
findutils
finish-install
fio
firebird3.0
firefox failed
firefox-esr failed
firewalld
flac
flask
flattr-icon-theme
flex
flite
fltk1.1
fluidsynth
flup
flute
fontchooser
fontconfig
fontforge
fonts-android
fonts-arabeyes
fonts-arphic-ukai
fonts-arphic-uming
fonts-cabin
fonts-cantarell
fonts-comfortaa
fonts-crosextra-caladea
fonts-crosextra-carlito
fonts-dejavu
fonts-dejima-mincho
fonts-ebgaramond
fonts-farsiweb
fonts-font-awesome
fonts-freefont
fonts-gfs-artemisia
fonts-gfs-baskerville
fonts-gfs-complutum
fonts-gfs-didot
fonts-gfs-neohellenic
fonts-gfs-olga
fonts-gfs-porson
fonts-gfs-solomos
fonts-gubbi
fonts-inconsolata
fonts-ipafont
fonts-junicode
fonts-khmeros
fonts-lao
fonts-lato
fonts-liberation
fonts-linuxlibertine
fonts-lklug-sinhala
fonts-lobstertwo
fonts-lohit-guru
fonts-lohit-telu
fonts-noto
fonts-noto-cjk
fonts-oflb-asana-math
fonts-roboto
fonts-samyak
fonts-sil-abyssinica
fonts-sil-gentium
fonts-sil-gentium-basic
fonts-sil-gentiumplus
fonts-sil-gentiumplus-compact
fonts-sil-padauk
fonts-sil-scheherazade
fonts-smc
fonts-stix
fonts-tibetan-machine
fonts-tlwg
fonts-ukij-uyghur
fonts-uralic
fonts-wqy-microhei
fonts-wqy-zenhei
fop
freeglut
freehep-chartableconverter-plugin
freehep-export
freehep-graphics2d
freehep-graphicsio
freehep-graphicsio-emf
freehep-graphicsio-java
freehep-graphicsio-pdf
freehep-graphicsio-ps
freehep-graphicsio-svg
freehep-graphicsio-swf
freehep-graphicsio-tests
freehep-io
freehep-swing
freehep-util
freehep-xml
freeimage
freeplane
freerdp
freetds
freetype
freexl
frei0r
fribidi
friendly-recovery
fsplib
fstrm
ftgl
fuse
policycoreutils
python-nss" > ${BUILD_LIST}
	fi
}

main()
{
	# support multi lists
	if [[ x$1 != "x" ]];then
	        BUILD_LIST=$1
	else
	        BUILD_LIST="/tmp/packs.list"
	        to_build_list
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
