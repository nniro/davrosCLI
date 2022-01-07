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
	echo "	get [-s] [-a] <path>		download a single file. (-s -> to stdout) (-a -> get all the content of a folder, but not subfolders)"
	echo "	put [<path>] [directory/]	upload a set of files where the last entry is a destination directory which *must* end with '/'"
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
		getAll="false"
		while getopts sa f 2>/dev/null; do
			case $f in
				s) toStdout="true";;
				a) getAll="true";;
			esac
		done
		[ $(($OPTIND > 1)) = 1 ] && shift $(expr $OPTIND - 1)

		extraArgs=""


		if [ "$getAll" = "true" ]; then
			fList="$(list "$url" "$args" $1 | sed -e 's/^\/*//')"
			for f in $fList; do
				if echo $f | grep -q '/$'; then # this is a directory
					[ ! -d $f ] && mkdir $f
				else
					runCurl $args $url/$f $extraArgs -o "$(printf "%s" "$f" | sed -e 's/%20/ /g')"
				fi
			done
		else
			if [ "$toStdout" = "false" ]; then extraArgs="$extraArgs -o \"$(basename $1 | sed -e 's/%20/ /g')\""; fi
			runCurl $args $url/$1 $extraArgs
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
