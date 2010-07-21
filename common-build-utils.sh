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
		(cd $build_dir; ../configure --prefix=$PREFIX $args $extra_configure_args) || return 1
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
	echo "### fix pkgconfig files"
	fix_pkgconfig_files $build_dir $TARGET $PREFIX || return 1

	if [ $package = "true" ]; then
		echo ""
		echo "### package $component"
		(cd $build_dir; $sudo_cmd make install DESTDIR=$TARGET) || return 1
	fi

	echo ""
	echo "### install $component"
	(cd $build_dir; $sudo_cmd make install DESTDIR=$TARGET) || return 1
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


function git_update() {
	gitrepo=$1
	gitbranch=$2
	if [ -n "$3" ]; then gitdir="$3"; else gitdir=; fi

	# do we have a checkout?
	if [ -d .git/ ]; then
		have_checkout=true
	else
		have_checkout=false
	fi

	if [ "$have_checkout" = "true" ]; then
		# try to pull from a predefined branch
		git pull
	else
		# we need to git-clone first, maybe
		pushd .. > /dev/null
		git clone $gitrepo $gitdir
		popd > /dev/null

		# checkout specific branch (if there is one)
		if [ -n "$gitbranch" ]; then
			if [ ! "$gitbranch" = "master" ]; then
				echo "Checking out branch $gitbranch..."
				git checkout -b $gitbranch --track origin/$gitbranch
			else
				echo "Sticking to master branch"
			fi
		fi
	fi
}


function check_update_submodule_status() {
	dir=$1
	pushd . > /dev/null
	cd $dir
	if [ -f components.conf ]; then
		for subcomp in `cat components.conf | awk '{print $1}'`; do
			[ -d $subcomp ] || mkdir -p $subcomp
			pushd $subcomp > /dev/null
			# assume we're working and fetching
			# from the the right branch
			echo "Ok to update $dir/$subcomp (which will overwrite any private changes you have made)?"
			prompt_yes_no && force_bootstrap="yes" && git_update `grep ^$subcomp ../components.conf | awk '{print $2,$3,$1}'`
			popd > /dev/null
		done
	else
		git submodule init
		for submodule in `git submodule status | grep "^[-+]" | awk '{print $2}'`; do
			echo "Ok to update $dir/$submodule (which will overwrite any private changes you have made)?"
			prompt_yes_no && force_bootstrap="yes" && git submodule update $submodule
		done
	fi
	popd > /dev/null
}


function fix_pkgconfig_files ()
{
	dir=$1
	targetdir=$2
	prefixdir=$3
	actualdir=`readlink -f $targetdir/$prefixdir || echo $targetdir/$prefixdir`

	# find and check
	pctotal=`find $dir -type f -name "*.pc" | wc -l`
	echo "Found $pctotal pc file(s) to fix."

	if [ $pctotal -gt 0 ]; then
		pcsample=`find $dir -type f -name "*.pc" | head -n1`
		a=`cat $pcsample | grep ^prefix=`
		prefixprev=${a##*=}
		echo "Previous prefix was [$prefixprev]; will change to [$actualdir]"

		for pcfile in `find $dir -type f -name "*.pc"`; do
			[ ! -f $pcfile.orig ] && cp -p $pcfile $pcfile.orig
			perl -i -p -e "s#^prefix\=${prefixprev}#prefix\=${actualdir}#g" $pcfile
		done
	fi
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

function print_info_git() {
	tag=`git describe --tags 2> /dev/null`
	cid=`git log --oneline -1 2> /dev/null`
	echo "$subcomp is known as [$tag]: $cid"
}

function print_info_dir() {
	dir=$1
	pushd $dir > /dev/null
	if [ -f components.conf ]; then
		for subcomp in `cat components.conf | awk '{print $1}'`; do
			pushd $subcomp > /dev/null
			print_info_git
			popd > /dev/null
		done
	else
		for submodule in `git submodule status | grep "^[-+]" | awk '{print $2}'`; do
			pushd $submodule > /dev/null
			print_info_git
			popd > /dev/null
		done
	fi
	popd > /dev/null
}
