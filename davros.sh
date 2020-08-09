#! /bin/sh

token="$(printf "%s" "$1" | sed -ne 's/[^\#]*\#\(.*\)$/\1/ p')"
url="$(printf "%s" "$1" | sed -e 's/^\(.*\)\#.*$/\1/')"

if [ "$token" != "" ]; then
	token="-H 'Authorization: Bearer $token'"
fi

if ! echo "$url" | grep -q "^https://"; then
	echo "The first argument must be a Sandstorm webkey"
	exit 1
fi

pathPrefix=remote.php/webdav

url=$url/$pathPrefix
shift

args="--silent $token"

putData() {
	if [ -d $1 ]; then
		echo "directory copy mode"
		echo "TODO, WIP"
		exit 0
	fi

	dst=$(echo "$@" | sed -e 's/^.* \(.*\)$/\1/') # spaces in directories and files are not supported

	if [ "$1" = "$dst" ]; then
		# copy a single file on the root
		eval curl $args -T "$1" "$url/$(basename $1)"
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

		eval curl $args -T "$1" "$url/$curDst"
		shift
	done
}

showHelp() {
	echo "Valid commands : "
	echo ""
	echo "	ls <path>			list the content of a directory"
	echo "	get [-s] <path>			download a single file. (-s -> to stdout)"
	echo "	put [<path>] [directory/]	upload a set of files where the last entry is a destination directory which *must* end with '/'"
	echo "	mv <path> <path>		move a file or directory to a new destination"
	echo "	rm <path>			delete a file or directory"
	echo "	mkdir <path>			create a new directory"
	echo ""
}

case $1 in
	h|help)
		showHelp
	;;

	ls|list)
		shift
		if [ "$1" != "" ]; then url="$url/$1"; fi
		result=$(eval curl $args -X PROPFIND $url | gzip -dc 2>/dev/null || eval curl $args -X PROPFIND $url)
		printf "%s" "$result" | sed -e 's/\(<\/[^>]*>\)/\1\n/g' | sed -ne '/<d:href>/ s/.*<d:href>\(.*\)<\/d:href>/\1/ p' | sed -e "s@/$pathPrefix@@"
	;;

	get)
		shift
		toStdout="false"
		while getopts s f 2>/dev/null; do
			case $f in
				s) toStdout="true";;
			esac
		done
		[ $(($OPTIND > 1)) = 1 ] && shift $(expr $OPTIND - 1)

		extraArgs=""
		if [ "$toStdout" = "false" ]; then extraArgs="$extraArgs -o $(basename $1)"; fi

		eval curl $args $url/$1 $extraArgs
	;;

	put)
		shift

		putData $@
	;;

	mv)
		shift
		eval curl $args -X MOVE --header "'Destination: /remote.php/webdav/$2'" "'$url/$1'"
	;;

	rm)
		shift
		if [ "$1" != "" ]; then # just a small failsafe
			eval curl $args -X DELETE $url/$1
		fi
	;;

	mkdir)
		shift
		eval curl $args -X MKCOL $url/$1
	;;

	*)
		echo "Invalid command entered"
		showHelp
	;;
esac
