#!/bin/bash

# Be nice in case user forgets to execute via scratchbox:
if [ `uname -m` != "arm" ]; then
	echo "executing $0 $* in scratchbox!"
	exec sb2 $0 $*
fi

cd `dirname $0`
dir=`pwd`

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

# work-around for aclocal:
mkdir -p $TARGET/usr/share/aclocal

escaped_target=`echo $TARGET | sed s/"\/"/"\\\\\\\\\/"/g`

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
	omap4-omx/tiler/memmgr                  $CONFIG_COMMON
	omap4-omx/syslink/syslink               $CONFIG_COMMON
	omap4-omx/syslink/syslink/d2c           $CONFIG_COMMON
	omap4-omx/system-omx/system/omx_core    $CONFIG_COMMON
	omap4-omx/system-omx/system/mm_osal     $CONFIG_COMMON
	omap4-omx/domx                          $CONFIG_COMMON
	gst-plugins-base  $CONFIG_GST_COMMON
	gst-plugins-good  $CONFIG_GST_COMMON --enable-experimental
	gst-plugins-bad   $CONFIG_GST_COMMON
	gst-plugin-h264   $CONFIG_GST_COMMON
	gst-openmax       $CONFIG_GST_COMMON
"
# todo.. add gst-plugin-bc if dependencies are satisfied..

source $dir/common-build-utils.sh

###############################################################################
# Argument parsing:

DEBUG_CFLAGS="-O3"     # Default optimize instead of debug..

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
		--debug)
			DEBUG_CFLAGS="-g"
			shift 1
			;;
		--with-*|--enable-*|--disable-*)
			echo "adding extra_configure_args: $arg"
			extra_configure_args="$extra_configure_args $arg"
			shift 1
			;;
		--help)
			echo "$0 [--force-bootstrap] [--clean] [component-path]*"
			echo "	--force-bootstrap  -  re-run bootstrap and configure even if it has already been run"
			echo "	--clean            -  clean derived objects"
			echo "	--debug            -  build debug build"
			echo "  --with-*           -  passed to configure scripts"
			echo "  --enable-*         -  passed to configure scripts"
			echo "  --disable-*        -  passed to configure scripts"
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

CFLAGS="$DEBUG_CFLAGS $CFLAGS"

yes_all="false"   # reset yes/no/all to != all..
check_update_submodule_status . || exit $?
check_update_submodule_status omap4-omx || exit $?
yes_all="false"   # reset in case someone adds other calls to prompt_yes_no()

# workaround for tiler build:
mkdir -p omap4-omx/tiler/memmgr/m4
mkdir -p omap4-omx/tiler/d2c/m4

main_loop

