#!/bin/bash

escaped_target=`echo $TARGET | sed s/"\/"/"\\\\\\\\\/"/g`


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
		if [ -r $build_dir/config.h ]; then
			sed s/"$escaped_target"//g $build_dir/config.h > $build_dir/.tmp.config.h &&
				mv $build_dir/.tmp.config.h $build_dir/config.h
			cat $build_dir/config.h
		fi
	fi

	echo ""
	echo "### make $component"
	(cd $build_dir; make -w -j4) || return 1

	echo ""
	echo "### install $component"
	(cd $build_dir; $sudo_cmd make install) || return 1

	if [ $package = "true" ]; then
		echo ""
		echo "### package $component"
		(cd $build_dir; make install DESTDIR=$TARGET/$PREFIX) || return 1
	fi
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

yes_all="false"
function prompt_yes_no() {
	if [ $yes_all = "true" ]; then
		echo "  Y/N/A> a"
		return 0
	fi
	while `true`; do
		echo -n "  Y/N/A> "
		read -n 1 result
		echo ""
		case $result in
			A|a) yes_all="true"; return 0 ;;
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


###############################################################################
# Main loop:

function main_loop() {
	SAVED_IFS=$IFS
	IFS="
"
	for line in $components; do
		IFS=$SAVED_IFS
		if [ -n "$build_components" ]; then
			component=${line%% *}
			if ! `echo $build_components | grep $component > /dev/null 2>&1`; then
				continue
			fi
		fi
		$do_it $line
		if [ $? != 0 ]; then
			echo "failed on $component, bailing out"
			exit 1
		fi
	done
	IFS=$SAVED_IFS
	echo "Success!"
}

