#!/bin/bash

# Be nice in case user forgets to execute via scratchbox:
if [ `uname -m` != "arm" ]; then
	echo "executing $0 $* in scratchbox!"
	exec sb2 $0 $*
fi

# setup some env vars for build:
export TARGET=${TARGET:-`pwd`/target}
export NOCONFIGURE=1
export AUTOGEN_SUBDIR_MODE=1
export PREFIX=$TARGET/usr
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig
export PATH=$PREFIX/bin:$PATH
export ACLOCAL_FLAGS="-I $PREFIX/share/aclocal"
export CFLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=softfp -fno-tree-vectorize"
#export CFLAGS="-I$PREFIX/include -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=softfp -fno-tree-vectorize"
#export LDFLAGS="-L$PREFIX/lib -L$TARGET/lib"

# work-around for libtool bug:
export echo=echo

###############################################################################
# Components to build in dependency order with configure args:

CONFIG_COMMON="--host=arm-none-linux-gnueabi --prefix=$PREFIX"
CONFIG_GST_COMMON="$CONFIG_COMMON --disable-docs-build  --disable-examples --disable-tests --disable-failing-tests --disable-valgrind --disable-debug --disable-gtk-doc"

components="\
	bash              $CONFIG_COMMON
	gtk-doc           $CONFIG_COMMON
	glib              $CONFIG_COMMON
	libxml2           $CONFIG_COMMON
	liboil            $CONFIG_COMMON
	faad2             $CONFIG_COMMON
	gstreamer         $CONFIG_GST_COMMON --with-buffer-alignment=128
	ttif              $CONFIG_COMMON
	omap4-omx/syslink/bridge                $CONFIG_COMMON
	omap4-omx/tiler/memmgr                  $CONFIG_COMMON
	omap4-omx/syslink/syslink               $CONFIG_COMMON
	omap4-omx/tiler/d2c                     $CONFIG_COMMON
	omap4-omx/system-omx/system/omx_core    $CONFIG_COMMON
	omap4-omx/audio-omx/system/lcml         $CONFIG_COMMON
	omap4-omx/system-omx/system/mm_osal     $CONFIG_COMMON
	omap4-omx/audio-omx/system/omx_base     $CONFIG_COMMON
	omap4-omx/audio-omx/audio/audio_decode  $CONFIG_COMMON
	omap4-omx/audio-omx/audio/audio_encode  $CONFIG_COMMON
	omap4-omx/domx                          $CONFIG_COMMON
	gst-plugins-base  $CONFIG_GST_COMMON
	gst-plugins-good  $CONFIG_GST_COMMON --enable-experimental
	gst-plugins-bad   $CONFIG_GST_COMMON
	gst-plugin-h264   $CONFIG_GST_COMMON
	gst-openmax       $CONFIG_GST_COMMON
"
# todo.. add gst-plugin-bc if dependencies are satisfied..

###############################################################################
# Helper functions:

build_subdir="00BUILD"
force_bootstrap="no"
do_it=build_it
extra_configure_args=""

function build_it() {
	component=$1
	shift 1
	args=$*
	echo ""
	echo ""
	echo "############################################################"
	echo "###### Building $component"

	bootstrap=""
	for f in autogen.sh bootstrap.sh bootstrap; do
		if [ -x "$component/$f" ]; then
			bootstrap=$f
			break;
		fi
	done

	if [ ! -n $bootstrap ] && [ ! -x "$component/configure" ]; then
		echo "I am confused!"
		return 1
	fi

	build_dir="$component/$build_subdir"

	if [ $force_bootstrap = "yes" ] || [ ! -e $build_dir/Makefile ]; then
		if [ -n "$bootstrap" ]; then
			echo ""
			echo "### bootstrap $component"
			(cd $component; ./$bootstrap) || return 1
			# some bootstrap files are silly and don't let you supress 
			# the configure step:
			if [ -e $component/Makefile ]; then
				(cd $component; make distclean)
			fi
		fi
	
		echo ""
		echo "### configure"
		mkdir -p $build_dir
		(cd $build_dir; ../configure $args $extra_configure_args) || return 1
	fi

	echo ""
	echo "### make $component"
	(cd $build_dir; make -w -j4) || return 1

	echo ""
	echo "### install $component"
	(cd $build_dir; make install) || return 1
}

function clean_it() {
	component=$1
	echo ""
	echo ""
	echo "############################################################"
	echo "####### Cleaning $component"
	
	build_dir="$component/$build_subdir"
	
	if [ -e $build_dir/Makefile ]; then
		(cd $build_dir; make distclean) || echo "error cleaning $component... continuing"
	fi
}

function prompt_yes_no() {
	while `true`; do
		echo -n "  Y/N> "
		read -n 1 result
		echo ""
		case $result in
			Y|y) return 0 ;;
			N|n) return 1 ;;
			*) echo "invalid input: $result"
		esac
	done
}


function check_update_submodule_status() {
	dir=$1
	pushd . > /dev/null
	cd $dir
	git submodule init
	for submodule in `git submodule status | grep "^[-+]" | awk '{print $2}'`; do 
		echo "Ok to update $dir/$submodule (which will overwrite any private changes you have made)?"
		prompt_yes_no && force_bootstrap="yes" && git submodule update $submodule
	done
	popd > /dev/null
}

check_update_submodule_status . || exit $?
check_update_submodule_status omap4-omx || exit $?


###############################################################################
# Argument parsing:

for arg in $*; do
	# todo.. add args for kernel and gfx ddk path..
	case $arg in
		--force-bootstrap)
			force_bootstrap="yes"
			shift 1
			;;
		--clean)
			do_it=clean_it
			shift 1
			;;
		--help)
			echo "$0 [--force-bootstrap] [--clean] [component-path]*"
			echo "	--force-bootstrap  -  re-run bootstrap and configure even if it has already been run"
			echo "	--clean            -  clean derived objects"
			echo "	--help             -  show usage"
			echo ""
			echo "  example:  $0 --force-bootstrap syslink/bridge audio-omx/system/lcml"
			exit 0
			;;
		*)
			components="$*"
			break
			;;
	esac
done

###############################################################################
# Main loop:

SAVED_IFS=$IFS
IFS="
"
for line in $components; do
	IFS=$SAVED_IFS
	$do_it $line
	if [ $? != 0 ]; then
		echo "failed on $component, bailing out"
		exit 1
	fi
done
IFS=$SAVED_IFS

