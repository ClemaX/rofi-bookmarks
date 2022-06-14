#!/usr/bin/env bash

# Abort on errors.
set -euo pipefail

# Table information

# moz_bookmarks
# {
#	id: integer, primary key
#	type: enum { FILE=1 DIRECTORY=2 }
#	fk: integer, foreign key
#	title: string, default ''
# }

# moz_places
# {
#	id: integer, primary key
#	parent: integer, foreign key (moz_bookmarks where type=DIRECTORY)
#	title: string, default ''
#	url: string
# }

BOOKMARK_FILE=1
BOOKMARK_DIRECTORY=2

BOOKMARK_ROOT=5

validate_id()
{
	local id="$1"
	local message="$FUNCNAME: ${2:-id} must be a positive integer!"

	if ! [[ "$id" =~ ^[0-9]+$ ]] ; then
		echo "$message" >&2
		return 1
	fi
}

moz_bookmark_parent_id()
{
	local id="$1"

	validate_id "$id"

	local query="SELECT parent
FROM moz_bookmarks WHERE id=$id"

	sqlite3 "$db" <<< "$query"
}

moz_bookmarks() # db [parent_id]
{
	local db="$1"
	local parent_id="${2:-$BOOKMARK_ROOT}"

	validate_id "$parent_id" "parent_id"

	local query="SELECT
	b.id, b.type, b.parent, b.title,
	p.title, p.site_name, p.description, p.url
FROM moz_bookmarks as b
LEFT OUTER JOIN moz_places AS p ON b.fk=p.id
WHERE b.parent=$parent_id
ORDER BY b.type desc, b.title asc;"

	local b_id b_type b_title
	local p_title p_sitename p_description p_url

	local title

	if [ "$parent_id" != "$BOOKMARK_ROOT" ]
	then
		b_id=$(moz_bookmark_parent_id "$parent_id")
		echo -e "..\0icon\x1ffolder\x1finfo\x1f$BOOKMARK_DIRECTORY:$b_id"
	fi

	sqlite3 "$db" <<< "$query" \
	| while IFS='|' read -r b_id b_type b_parent b_title p_title p_sitename p_description p_url
	do
		title="${b_title:-${p_title:-${p_sitename:-$p_url}}}"
		if [ "$b_type" = "$BOOKMARK_DIRECTORY" ]
		then
			echo -e "$title\0icon\x1ffolder\x1finfo\x1f$b_type:$b_id"
		elif [ "$b_type" = "$BOOKMARK_FILE" ]
		then
			echo -e "$title\0icon\x1flink\x1finfo\x1f$b_type:$b_id"
		fi
	done
}

moz_bookmark_url() # db id
{
	local db="$1"
	local id="$2"

	local query

	validate_id "$id"

	query="SELECT p.url
FROM moz_bookmarks as b
LEFT OUTER JOIN moz_places AS p ON b.fk=p.id
WHERE b.id = $id"

	sqlite3 "$db" <<< "$query"
}

# Get cache directory.
UNAME=$(uname -s)
case "$UNAME" in
	Linux*)		CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bookmarks";;
	Darwin*)	CACHE_DIR="$HOME/Library/Caches/fr.42lyon.chamada.bookmarks";;
	*)			echo "Unknown system: '$UNAME'!" >&2 && exit 1;;
esac

# Script directory.
PARENT_DIR=$(dirname "$0")

# Firefox profile directory.
PROFILE=$(<"$PARENT_DIR/.profile")

# Temporary database copy location.
DB_TMP="$CACHE_DIR/places.sqlite"

# Create cache directory.
mkdir -p "$CACHE_DIR"

# Files should be accessible only to the current user.
umask 177

if [ $# -eq 0 ]
then
	# Update database.
	cp -u "$PROFILE/places.sqlite" "$DB_TMP"

	# Extract bookmarks.
	moz_bookmarks "$DB_TMP" 5
else
	b_type="${ROFI_INFO%%:*}"
	b_type="${b_type:-$BOOKMARK_FILE}"
	b_id="${ROFI_INFO#*:}"
	[ "$b_id" = "$ROFI_INFO" ] && b_id=

	if [ "$b_type" -eq "$BOOKMARK_FILE" ]
	then
		i3-msg -q "exec xdg-open '$(moz_bookmark_url "$DB_TMP" "$b_id")'"
	elif [ "$b_type" -eq "$BOOKMARK_DIRECTORY" ]
	then
		moz_bookmarks "$DB_TMP" "$b_id"
	fi
fi
