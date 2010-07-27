#!/bin/bash

pushd `dirname $0` > /dev/null
dir=`pwd`
source $dir/common-build-utils.sh
print_info_dir .
print_info_dir omap4-omx
popd > /dev/null
