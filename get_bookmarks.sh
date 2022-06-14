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
	local message="${FUNCNAME[0]}: ${2:-id} must be a positive integer!"

	if ! [[ "$id" =~ ^[0-9]+$ ]] ; then
		echo "$message" >&2
		return 1
	fi
}

rofi_render()
{
	local b_id b_type b_title
	local p_title p_sitename p_description p_url

	local title icon info meta

	while IFS='|' read -r b_id b_type b_parent b_title \
		p_title p_sitename p_description p_url
	do
		title="${b_title:-${p_title:-${p_sitename:-$p_url}}}"
		if [ "$b_type" = "$BOOKMARK_DIRECTORY" ]
		then
			icon='folder'
		elif [ "$b_type" = "$BOOKMARK_FILE" ]
		then
			icon='link'
		fi
		info="$b_type:$b_id:$b_parent:$p_url"
		meta="$p_url $p_description"

		echo -e "$title\0icon\x1f$icon\x1finfo\x1f$info\x1fmeta\x1f$meta"
	done
}

rofi_info() # [dest_type] [dest_id] [dest_backref] [dest_url]
{
	IFS=':' read -r "$@" <<< "$ROFI_INFO"
}

moz_bookmarks() # db [parent_id] [backref_id]
{
	local db="$1"
	local parent_id="${2:-$BOOKMARK_ROOT}"
	local backref_id="${3:-$BOOKMARK_ROOT}"

	validate_id "$parent_id" "parent_id"
	[ -n "$backref_id" ] || validate_id "$backref_id" "backref_id"

	local query="SELECT
	b.id, b.type, b.parent, b.title,
	p.title, p.site_name, p.description, p.url
FROM moz_bookmarks as b
LEFT OUTER JOIN moz_places AS p ON b.fk=p.id"

	if [ "$parent_id" != "$BOOKMARK_ROOT" ]
	then
		query+=" WHERE b.parent=$parent_id"

		echo -e "..\0icon\x1ffolder\x1finfo\x1f$BOOKMARK_DIRECTORY:$backref_id:$BOOKMARK_ROOT:"
	fi

	query+=" ORDER BY b.type desc, b.title asc;"

	sqlite3 "$db" <<< "$query" | rofi_render
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
	# TODO: Select firefox profile on first launch

	# Update database.
	cp -u "$PROFILE/places.sqlite" "$DB_TMP"

	# Extract bookmarks.
	moz_bookmarks "$DB_TMP" 5
else
	echo "$ROFI_INFO" >&2
	rofi_info b_type b_id b_backref p_url

	echo "$b_type $b_id $b_backref $p_url" >&2

	if [ "$b_type" -eq "$BOOKMARK_FILE" ]
	then
		# Replace with coproc when using another wm:
		# coproc ( xdg-open "$p_url" ) > /dev/null  2>1 )
		i3-msg -q "exec xdg-open '$p_url'"
	elif [ "$b_type" -eq "$BOOKMARK_DIRECTORY" ]
	then
		moz_bookmarks "$DB_TMP" "$b_id"
	fi
fi
