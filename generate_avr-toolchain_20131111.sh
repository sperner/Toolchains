#!/bin/bash
#
# original Author:		unknown
# updated & enhanced by:	Sven Sperner	<cethss@gmail.com>
#
# gen-avr-toolchain.sh 2007-11-05
# Tested under gentoo & ubuntu linux. Should work on other distros too :)
#
# Patches can be found under
# http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-binutils/files/
# http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-gcc/files/
# http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-libc/files/
#
# for file in $(curl http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-binutils/files/ 2>/dev/null|grep ./patch|sed 's/^.*href="\.\///'|sed 's/">.*//g'); do { wget http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-binutils/files/$file; }; done
# for file in $(curl http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-gcc/files/ 2>/dev/null|grep ./patch|sed 's/^.*href="\.\///'|sed 's/">.*//g'); do { wget http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-gcc/files/$file; }; done
# for file in $(curl http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-libc/files/ 2>/dev/null|grep ./patch|sed 's/^.*href="\.\///'|sed 's/">.*//g'); do { wget http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-libc/files/$file; }; done

#target to build the tools for
TARGET=avr

#this is the install path
export CONFIG_PREFIX=/usr/local
#export CONFIG_PREFIX=/usr/local/avr
#temporary build directory
BUILD="build"
#where to log errors
LOG=/tmp/buildavr.log

#versions
BINUTILS=2.20.1
GCC=4.3.4
AVRLIBC=1.6.8
GDB=6.8
INSIGHT=6.8-1

#set to 1 to check for needed tools
CHECK=0
#set to 1 to verify archive integrity
VERIFY=0
#set to 1 to delete directories first
DELETE=1
#set num of cores for make's "-j"
CORES=6

#set to 1 to build & install
binutils=1
gcccore=1
avrlibc=1
gdb=0
insight=0

#some colors
CEND="\033[1;31m\n# "
CTOP="\033[1;32m\n### "
CE=" ###\033[0m\n"
CDOW="\033[1;34m\n# "
CS=" #\033[0m\n"

#Keep these lists sorted or they may not work!
PATCHES_BINUTILS="patch-aa patch-as-dwarf patch-as-dwarf-avrstudio patch-avr-size patch-coff-avr patch-newdevices patch-newsections patch-xmega"
PATCHES_GCC="patch-avr-libgcc.S patch-bug11259 patch-bug18145 patch-bug19636-24894-31644-31786 patch-bug33009 patch-bug34210-35508 patch-bug35013 patch-builtins patch-disable-ssp patch-libiberty-Makefile.in patch-newdevices patch-param-inline-call-cost patch-xmega patch-xx-os_main"
PATCHES_GDB="patch-atmega256x-gdb patch-gdb::remote.c" #for gdb-6.8 (insight-6.8)

##PATCHES_BINUTILS="patch-aa patch-avr25-wrap patch-coff-avr patch-data-origin patch-newdevices patch-newsections patch-xmega patch-zzz-atmega128rfa1"
##PATCHES_GCC="patch-avr-libgcc.S patch-bug11259 patch-bug19636-24894-31644-31786 patch-bug33009 patch-bug34210-35508 patch-bug35013 patch-libiberty-Makefile.in patch-newdevices patch-xmega patch-xx-os_main"


#############################################################################################
# declaration of functions(){...}
#############################################################################################

usage()
{
	echo -e "AVR-Toolchain (binutils, gcc-core, avrlibc, gdb, insight)"
	echo -e "Download, verify, extract, patch, configure, build & install!"
	echo
	echo "usage: $0 [<binutils,gcccore,avrlibc,gdb,insight>]"
	echo
	echo "start without any parameter to use script-defaults"
}

info()				# print information screen
{
	echo
	echo -e "\033[1;32m\n ----- THIS WILL INSTALL THE AVR_TOOLCHAIN -----\033[0m"
	echo
	if [ $avrlibc -eq 1 ] ; then
		echo " avr-libc version          $AVRLIBC"
	fi
	if [ $gcccore -eq 1 ] ; then
		echo " avr-gcc version           $GCC"
	fi
	if [ $binutils -eq 1 ] ; then
		echo " avr-binutils version      $BINUTILS"
	fi
	if [ $gdb -eq 1 ] ; then
		echo " avr-gdb version           $GDB"
	fi
	if [ $insight -eq 1 ] ; then
		echo " avr-insight version       $INSIGHT"
	fi
	if [ $DELETE -eq 1 ] ; then
		echo " delete tmporary build-folders"
	fi
	echo " install path              $CONFIG_PREFIX"
	echo
	echo -e "\033[1;32m ----- PRESS ENTER TO CONTINUE OR CTRL-C TO ABORT -----\033[0m\n"
	echo
	read -s foobar
}

check()				# check if we have everything we need
{
	which emerge &> /dev/null && EMERGE_SUPPORTED="1"

	which patch &> /dev/null
	[ ! $? -eq 0 ] && echo -e $CEND"Please install the utility 'patch' before continuing"$CS && exit 1

	if [ ! "$EMERGE_SUPPORTED" = "1" ] ; then
		echo -e $CEND"You are not on a Gentoo system!? Hmm... that's ok but i cannot determine if the libraries 'mpfr' and 'gmp' are installed. If build fails make sure these libraries are installed or hit CTRL-C now and make things sure before you proceed.
			Hit Enter to Continue or CTRL-C to exit"$CS
		read -s foobar
	else
		echo -e $CDOW"Checking for mpfr and gmp libraries"$CS
		emerge -s gmp  | grep "dev-libs" -A2  | grep -i "Not Installed" &> /dev/null && need_lib_install="1"
		emerge -s mpfr | grep -i "Not Installed" &> /dev/null && need_lib_install="1"
	
		if [ "$need_lib_install" = "1" ] ; then
			echo -e $CEND"The libraries gmp and mpfr are needed. Setup will emerge them now"$CS
			echo -e $CEND"Give Root-Password to emerge them"$CS
			su -c "emerge --update mpfr gmp" || exit 1
		else
			echo "Both libraries installed :-)"
		fi
	fi
}


#############################################################################################
# declaration of install-functions(){...}
# -->> test, wget, gpg, untar, patch, configure, make, make install
#############################################################################################

install_binutils()
{
	if [ $DELETE -eq 1 ] ; then
		echo -e $CDOW"Removing old build-directory"$CS
		test -d "binutils-$BINUTILS" && ( echo -n "removing binutils-$BINUTILS...  " ; rm -rf binutils-$BINUTILS || exit 1 ; echo "ok" )
	fi

	echo -e $CDOW"Checking for binutils and patches"$CS
	test -r "binutils-$BINUTILS.tar.bz2" || (echo -e "Downloading binutils source...  " ; wget "http://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS.tar.bz2" || exit 1 ; echo "ok")

	if [ $VERIFY -eq 1 ] ; then
		echo "Fetching PGP key 0x4AE55E93 from server"
		gpg --keyserver pgp.mit.edu --recv 4AE55E93 &> /dev/null
		test -r "binutils-$BINUTILS.tar.bz2.sig" || (
			echo "Downloading binutils signature...  " ; wget "http://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS.tar.bz2.sig" &> /dev/null || exit 1 ; echo "ok"
		)
		echo -n "Checking binutils-$BINUTILS.tar.bz2...  "
		gpg --verify binutils-$BINUTILS.tar.bz2.sig &> /dev/null
		if [ $? -ne 0 ] ; then echo "failed" ; exit 1 ; fi ; echo "ok"
	fi

	test -d "patches_binutils" || (echo -e "Creating patch directory: patches_binutils...  " ; mkdir patches_binutils || exit 1 ; echo "ok")
	echo -e "Downloading binutils patches (if needed)"
	cd patches_binutils
	for p in $PATCHES_BINUTILS ; do
		test -r "$p" || (wget "http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-binutils/files/$p" || exit 1)
	done
	cd ..

	echo -n "Unpacking binutils-$BINUTILS.tar.bz2... " ; tar -xjvf "binutils-$BINUTILS.tar.bz2" > /dev/null || exit 1 ; echo "ok"

	cd binutils-$BINUTILS				|| exit 1
	
	echo -e $CDOW"Patching binutils"$CS
	for p in $PATCHES_BINUTILS ; do
		echo -e "\n *** Patching $p"
		patch -p0 < ../patches_binutils/$p	|| exit 1
	done
	
	test -d "$BUILD " || (echo -e $CDOW"Creating build directory: $BUILD"$CS ; mkdir "$BUILD" || exit 1)
	cd $BUILD || exit 1

	echo -e $CDOW"Configuring binutils"$CS
	../configure --target=$TARGET --prefix=$CONFIG_PREFIX --disable-werror	|| exit 1
	
	echo -e $CDOW"Building binutils"$CS
	make -j$CORES					|| exit 1
	
	echo -e $CDOW"Give Root-Password to install binutils"$CS
	su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install" || (
		echo -e $CEND"Wrong password! Please try again"$CS
		su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install"	|| exit 1
	)
	cd ../..
}

install_gcc()
{
	if [ $DELETE -eq 1 ] ; then
		echo -e $CDOW"Removing old build-directory"$CS
		test -d "gcc-$GCC"       && ( echo -n "removing gcc-$GCC...  "   ; rm -rf gcc-$GCC || exit 1 ; echo "ok" )
	fi

	echo -e $CDOW"Checking for gcc and patches"$CS
	test -r "gcc-core-$GCC.tar.bz2"  || (echo -e "Downloading gcc-core source...  " ; wget "ftp://ftp.gwdg.de/pub/misc/gcc/releases/gcc-$GCC/gcc-core-$GCC.tar.bz2" || exit 1 ; echo "ok")

	if [ $VERIFY -eq 1 ] ; then
		test -r "md5.sum"  || (
			echo "Downloading gcc-core hash...  " ; wget "ftp://ftp.gwdg.de/pub/misc/gcc/releases/gcc-$GCC/md5.sum" -O gcccore.md5.sum &> /dev/null  || exit 1 ; echo "ok"
		)
		echo -n "Checking gcc-core-$GCC.tar.bz2...  "
		grep `md5sum gcc-core-$GCC.tar.bz2` gcccore.md5.sum &> /dev/null || ( echo "failed" ; exit 1 )
		echo "ok"
	fi

	test -d "patches_gcc" || (echo -e "Creating patch directory: patches_gcc...  " ; mkdir patches_gcc || exit 1 ; echo "ok")
	echo -e "Downloading gcc patches (if needed)"
	cd patches_gcc
	for p in $PATCHES_GCC ; do
		test -r "$p" || (wget "http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-gcc/files/$p" || exit 1)
	done
	cd ..

	echo -n "Unpacking gcc-core-$GCC.tar.bz2...  " ; tar -xjvf "gcc-core-$GCC.tar.bz2"  > /dev/null || exit 1 ; echo "ok"

	cd gcc-$GCC 				|| exit 1
	
	echo -e $CDOW"Patching gcc"$CS
	for p in $PATCHES_GCC ; do
		echo -e "\n *** Patching $p"
		patch -p0 < ../patches_gcc/$p		|| exit 1
	done
	
	test -d "$BUILD " || (echo -e $CDOW"Creating build directory: $BUILD"$CS ; mkdir "$BUILD" || exit 1)
	cd $BUILD || exit 1
	
	echo -e $CDOW"Configuring gcc"$CS
	../configure --target=$TARGET --prefix=$CONFIG_PREFIX --enable-languages=c --disable-libssp --enable-__cxa_atexit --enable-clocale=gnu --disable-nls --with-dwarf2 --with-gmp=/usr/local --with-mpfr=/ || exit 1
	
	echo -e $CDOW"Building gcc"$CS
	make -j$CORES					|| exit 1
	
	echo -e $CDOW"Give Root-Password to install gcc"$CS
	su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install" || (
		echo -e $CEND"Wrong password! Please try again"$CS
		su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install"	|| exit 1
	)
	cd ../..
}

install_libc()
{
	if [ $DELETE -eq 1 ] ; then
		echo -e $CDOW"Removing old build-directory"$CS
		test -d "avr-libc-$AVRLIBC"  && ( echo -n "removing avr-libc-$AVRLIBC...  "   ; rm -rf avr-libc-$AVRLIBC  || exit 1 ; echo "ok" )
	fi

	echo -e $CDOW"Checking for avr-libc"$CS
	test -r "avr-libc-$AVRLIBC.tar.bz2"  || (echo -e "Downloading avr-libc source... " ; wget "http://download.savannah.gnu.org/releases/avr-libc/avr-libc-$AVRLIBC.tar.bz2" || exit 1 ; echo "ok")

	if [ $VERIFY -eq 1 ] ; then
		echo "Fetching PGP key 0x69A85873 from server"
		gpg --keyserver pgp.mit.edu --recv 69A85873 &> /dev/null
		test -r "avr-libc-$AVRLIBC.tar.bz2.sig"  || (
			echo "Downloading avr-libc signature...  " ; wget "http://download.savannah.gnu.org/releases/avr-libc/avr-libc-$AVRLIBC.tar.bz2.sig" &> /dev/null || exit 1 ; echo "ok"
		)
		echo -n "Checking avr-libc-$AVRLIBC.tar.bz2...  "
		gpg --verify avr-libc-$AVRLIBC.tar.bz2.sig  &> /dev/null
		if [ $? -ne 0 ] ; then echo "failed" ; exit 1 ; fi ; echo "ok"
	fi

	echo -n "Unpacking avr-libc-$AVRLIBC.tar.bz2...  "   ; tar -xjvf "avr-libc-$AVRLIBC.tar.bz2"  > /dev/null || exit 1 ; echo "ok"

	cd avr-libc-$AVRLIBC								|| exit 1
	
	test -d "$BUILD " || (echo -e $CDOW"Creating build directory: $BUILD"$CS ; mkdir "$BUILD" || exit 1)
	cd $BUILD || exit 1

	echo -e $CDOW"Configuring avr-libc"$CS
	../configure --build=`./config.guess` --host=$TARGET --prefix=$CONFIG_PREFIX 	|| exit 1
	
	echo -e $CDOW"Building avr-libc"$CS
	make -j$CORES									|| exit 1
	
	echo -e $CDOW"Give Root-Password to install avr-libc"$CS
	su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install" || (
		echo -e $CEND"Wrong password! Please try again"$CS
		su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install"		|| exit 1
	)
	cd ../..
}

install_gdb()
{
	if [ $DELETE -eq 1 ] ; then
		echo -e $CDOW"Removing old build-directory"$CS
		test -d "gdb-$GDB"  && ( echo -n "removing gdb-$GDB...  " ; rm -rf gdb-$GDB || exit 1 ; echo "ok" )
	fi

	echo -e $CDOW"Checking for gdb"$CS
	test -r "gdb-$GDB.tar.bz2"  || (echo -e "Downloading gdb source... " ; wget "http://ftp.gnu.org/gnu/gdb/gdb-$GDB.tar.bz2" || exit 1 ; echo "ok")

	if [ $VERIFY -eq 1 ] ; then
		echo "Fetching PGP key 0xFF325CF3 from server"
		gpg --keyserver pgp.mit.edu --recv FF325CF3 &> /dev/null
		test -r "gdb-$GDB.tar.bz2.sig"  || (
			echo "Downloading gdb hash...  " ; wget "http://ftp.gnu.org/gnu/gdb/gdb-$GDB.tar.bz2.sig" &> /dev/null || exit 1 ; echo "ok"
		)
		echo -n "Checking gdb-$GDB.tar.bz2...  "
		gpg --verify gdb-$GDB.tar.bz2.sig  &> /dev/null
		if [ $? -ne 0 ] ; then echo "failed" ; exit 1 ; fi ; echo "ok"
	fi

#	test -d "patches_gdb" || (echo -e "Creating patch directory: patches_gdb...  " ; mkdir patches_gdb || exit 1 ; echo "ok")
#	echo -e "Downloading gdb patches (if needed)"
#	cd patches_gdb
#	for p in $PATCHES_GDB ; do
#		test -r "$p" || (wget "http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-gdb/files/$p" || exit 1)
#	done
#	cd ..

	echo -n "Unpacking gdb-$GDB.tar.bz2...  " ; tar -xjvf "gdb-$GDB.tar.bz2"  > /dev/null || exit 1 ; echo "ok"

	cd gdb-$GDB									|| exit 1
	
#	echo -e $CDOW"Patching gdb"$CS
#	for p in $PATCHES_GDB ; do
#		echo -e "\n *** Patching $p"
#		patch -p0 < ../patches_gdb/$p		|| exit 1
#	done

	test -d "$BUILD " || (echo -e $CDOW"Creating build directory: $BUILD"$CS ; mkdir "$BUILD" || exit 1)
	cd $BUILD || exit 1

	echo -e $CDOW"Configuring gdb"$CS
	../configure --target=$TARGET --prefix=$CONFIG_PREFIX || exit 1	
	echo -e $CDOW"Building gdb"$CS
	make -j$CORES									|| exit 1
	
	echo -e $CDOW"Give Root-Password to install gdb"$CS
	su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install" || (
		echo -e $CEND"Wrong password! Please try again"$CS
		su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install"		|| exit 1
	)
	cd ../..
}

install_insight()
{
	if [ $DELETE -eq 1 ] ; then
		echo -e $CDOW"Removing old build-directory"$CS
		test -d "insight-$INSIGHT"  && ( echo -n "removing insight-$INSIGHT...  "   ; rm -rf insight-$INSIGHT  || exit 1 ; echo "ok" )
	fi

	echo -e $CDOW"Checking for insight"$CS
	test -r "insight-$INSIGHT.tar.bz2"  || (echo -e "Downloading insight source...  " ; wget "ftp://sourceware.org/pub/insight/releases/insight-$INSIGHT.tar.bz2" || exit 1 ; echo "ok")

	if [ $VERIFY -eq 1 ] ; then
		test -r "insight.md5.sum"  || (
			echo "Downloading insight hash...  " ; wget "ftp://sourceware.org/pub/insight/releases/md5.sum" -O insight.md5.sum &> /dev/null || exit 1 ; echo "ok"
		)
		echo -n "Checking insight-$INSIGHT.tar.bz2...  "
		grep `md5sum insight-$INSIGHT.tar.bz2` insight.md5.sum &> /dev/null || ( echo "failed" ; exit 1 )
		echo "ok"
	fi

	test -d "patches_gdb" || (echo -e "Creating patch directory: patches_gdb...  " ; mkdir patches_gdb || exit 1 ; echo "ok")
	echo -e "Downloading gdb patches (if needed)"
	cd patches_gdb
	for p in $PATCHES_GDB ; do
		test -r "$p" || (wget "http://www.freebsd.org/cgi/cvsweb.cgi/~checkout~/ports/devel/avr-gdb/files/$p" || exit 1)
	done
	cd ..

	echo -n "Unpacking insight-$INSIGHT.tar.bz2...  "   ; tar -xjvf "insight-$INSIGHT.tar.bz2"  > /dev/null || exit 1 ; echo "ok"

	cd insight-$INSIGHT								|| exit 1

	echo -e $CDOW"Patching insight"$CS
	for p in $PATCHES_GDB ; do
		echo -e "\n *** Patching $p"
		patch -p0 < ../patches_gdb/$p		|| exit 1
	done

	test -d "$BUILD " || (echo -e $CDOW"Creating build directory: $BUILD"$CS ; mkdir "$BUILD" || exit 1)
	cd $BUILD || exit 1

	echo -e $CDOW"Configuring insight"$CS
	../configure --target=$TARGET --prefix=$CONFIG_PREFIX --disable-werror || exit 1	
	echo -e $CDOW"Building insight"$CS
	make -j$CORES									|| exit 1
	
	echo -e $CDOW"Give Root-Password to install insight"$CS
	su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install" || (
		echo -e $CEND"Wrong password! Please try again"$CS
		su -c "export PATH=$PATH:$CONFIG_PREFIX/bin; make install"		|| exit 1
	)
	cd ../..
}


#############################################################################################
# int main(int argc, char* argv[]){
#############################################################################################

if [ $# -gt 0 ]
then
	binutils=0
	gcccore=0
	avrlibc=0
	gdb=0
	insight=0
	for PACKAGE in $*; do
		case "$PACKAGE" in
			--help)		usage 2>&1 | tee $LOG ; exit 0	;;
			binutils)	binutils=1			;;
			gcccore)	gcccore=1			;;
			avrlibc)	avrlibc=1			;;
			gdb)		gdb=1				;;
			insight)	insight=1			;;
			delete)		delete=1			;;
			*)	echo -e $CEND"$0: unknown parameter: $PACKAGE"$CS ;;
		esac
	done
fi

info 2>&1 | tee $LOG

if [ $CHECK -eq 1 ] ; then
	echo -e $CTOP"Checking for needed utils:"$CE
	( check || exit 1 ) 2>&1 | tee $LOG
fi

export PATH=$PATH:$CONFIG_PREFIX/bin

if [ $binutils -eq 1 ] ; then
	echo -e $CTOP">>Binutils-$BINUTILS:"$CE
	( install_binutils || exit 1 ) 2>&1 | tee $LOG
fi
if [ $gcccore -eq 1 ] ; then
	echo -e $CTOP">>Gcc-$GCC:"$CE
	( install_gcc || exit 1 ) 2>&1 | tee $LOG
fi
if [ $avrlibc -eq 1 ] ; then
	echo -e $CTOP">>AVRLibC-$AVRLIBC:"$CE
	( install_libc || exit 1 ) 2>&1 | tee $LOG
fi
if [ $gdb -eq 1 ] ; then
	echo -e $CTOP">>GDb-$GDB:"$CE
	( install_gdb || exit 1 ) 2>&1 | tee $LOG
fi
if [ $insight -eq 1 ] ; then
	echo -e $CTOP">>Insight-$INSIGHT:"$CE
	( install_insight || exit 1 ) 2>&1 | tee $LOG
fi
if [ $DELETE -eq 1 ] ; then
	echo -e $CTOP" Removing temporary folder "$CE
	for FOLDER in {binutils-$BINUTILS,gcc-$GCC,avr-libc-$AVRLIBC,gdb-$GDB,insight-$INSIGHT} ; do
		echo -e ">Removing temporary folder \"$FOLDER\""
		rm -rf $FOLDER || ( echo "failed" ; exit 1 )
	done
fi

echo -e $CEND"-->> All Done! <<--"$CS
exit 0

#############################################################################################
# }
#############################################################################################
