#! /bin/sh

token="$(printf "%s" "$1" | sed -ne 's/[^\#]*\#\(.*\)$/\1/ p')"
url="$(printf "%s" "$1" | sed -e 's/^\(.*\)\#.*$/\1/' | sed -e 's/^\(.*\)\/\+$/\1/')"

if [ "$token" != "" ]; then
	token="-H 'Authorization: Bearer $token'"
fi

alias runCurl="curl $token"

if ! echo "$url" | grep -q "^https://"; then
	echo "The first argument must be a Sandstorm webkey"
	exit 1
fi

pathPrefix=remote.php/webdav

url=$url/$pathPrefix
shift

args="--silent"

putData() {
	if [ -d $1 ]; then
		echo "directory copy mode"
		echo "TODO, WIP"
		exit 0
	fi

	dst=$(echo "$@" | sed -e 's/^.* \(.*\)$/\1/') # spaces in directories and files are not supported

	if [ "$1" = "$dst" ]; then
		# copy a single file on the root
		runCurl $args -T "$1" "$url/$(basename $1)"
		return
	fi

	while [ "$1" != "$dst" ]; do
		if [ ! -e $1 ]; then
			echo "file \`$1' does not exist, skipping"
			shift
			continue
		fi

		if [ -d $1 ]; then
			echo "we do not yet support copying directories, skipping \`$1'"
			shift
			continue
		fi

		if $(echo $dst | grep '\/$' >/dev/null); then
			curDst="${dst}$(basename $1)"
		else
			curDst="${dst}"
		fi

		if [ "$dst" = "" ]; then
			curDst=$(basename $1)
		fi

		runCurl $args -T "$1" "$url/$curDst"
		shift
	done
}

showHelp() {
	echo "Valid commands : "
	echo ""
	echo "	ls <path>			list the content of a directory"
	echo "	get [-s] [-r] <path>		download a file or directory."
	echo "					-s : to stdout (only works with files)"
	echo "					-r : get files recursively"
	echo "	put [<path>] [directory/]	upload a set of files where the last entry is a"
	echo "					destination directory which *must* end with '/'"
	echo "	mv <path> <path>		move a file or directory to a new destination"
	echo "	rm <path>			delete a file or directory"
	echo "	mkdir <path>			create a new directory"
	echo ""
}

list() {
	url=$1
	args=$2
	shift 2
	if [ "$1" != "" ]; then url="$url/$1"; fi

	result=$(runCurl $args -X PROPFIND $url | gzip -dc 2>/dev/null || runCurl $args -X PROPFIND $url)
	printf "%s" "$result" | sed -e 's/\(<\/[^>]*>\)/\1\n/g' | sed -ne '/<d:href>/ s/.*<d:href>\(.*\)<\/d:href>/\1/ p' | sed -e "s@/$pathPrefix@@"
}

removeStartingSlashes() {
	sed -e 's/^\/*//'
}

removeEndingSlashes() {
	sed -e 's/\/*$//'
}

isRemoteDirectory() {
	[ "$1" = "/" ] && return 0
	local path=$(echo $1 | removeEndingSlashes | removeStartingSlashes)

	fList="$(list "$url" "$args" $path | removeStartingSlashes)"

	set -- $fList

	echo $1 | grep -q "^$path/$"
}

getDirectoryContent() {
	local path=$1
	local recursive=$2

	[ "$path" != "/" ] && path="$(echo $path | removeStartingSlashes)"

	echo $path | grep -q '\/$' || path="$path/"

	[ "$recursive" = "" ] && recursive="false"

	fList="$(list "$url" "$args" $path | removeStartingSlashes)"
	for f in $fList; do
		[ -d ./$f ] && [ "$f" = "$path" ] && continue
		if echo $f | grep -q '/$'; then # this is a directory
			if [ "$recursive" = "true" ]; then
				[ ! -d ./$f ] && mkdir -p ./$f
				getDirectoryContent "$f" true
			else
				[ ! -d ./$f ] && [ "$f" = "$path" ] && mkdir -p ./$f
			fi
		else
			runCurl $args $url/$f $extraArgs -o "$(printf "%s" "$f" | sed -e 's/%20/ /g')"
		fi
	done
}

case $1 in
	h|help)
		showHelp
	;;

	ls|list)
		shift
		list "$url" "$args" $1
	;;

	get)
		shift
		toStdout="false"
		recursive="false"
		while getopts sr f 2>/dev/null; do
			case $f in
				s) toStdout="true";;
				r) recursive="true";;
			esac
		done
		[ $(($OPTIND > 1)) = 1 ] && shift $(expr $OPTIND - 1)

		extraArgs=""

		if isRemoteDirectory $1; then
			getDirectoryContent $1 $recursive
		else
			if [ "$toStdout" = "false" ]; then
				runCurl $args $url/$1 $extraArgs -o "$(basename $1 | sed -e 's/%20/ /g')"
			else
				runCurl $args $url/$1 $extraArgs
			fi
		fi
	;;

	put)
		shift

		putData $@
	;;

	mv)
		shift
		runCurl $args -X MOVE --header "'Destination: /remote.php/webdav/$2'" "'$url/$1'"
	;;

	rm)
		shift
		if [ "$1" != "" ]; then # just a small failsafe
			runCurl $args -X DELETE $url/$1
		fi
	;;

	mkdir)
		shift
		runCurl $args -X MKCOL $url/$1
	;;

	*)
		echo "Invalid command entered"
		showHelp
	;;
esac
