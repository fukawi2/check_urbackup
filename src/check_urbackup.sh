#!/bin/bash

###############################################################################
# Copyright (C) 2014 Phillip Smith
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
###############################################################################

set -e
set -u

readonly PROGNAME=$(basename "$0")
readonly PROGDIR=$(readlink -m "$(dirname \"$0\")")
readonly ARGS="$*"

function bomb {
  printf "BOMBS AWAY: %s\n", "$1" >&2
  exit 1;
}
function warn() {
  printf "WARNING: %s\n", "$1" >&2
}
function dbg {
  printf "DEBUG: %s\n", "$1" >&2
}

function usage {
  printf "Usage: %s [options]\n" "$0"
  printf "Options:\n"
  printf "   %-25s %-50s\n" '-d /path/to/db'  'Specify path to database file'
  printf "   %-25s %-50s\n" '-w secs'         'Warning age in SECONDS for file backups'
  printf "   %-25s %-50s\n" '-c secs'         'Critical age in SECONDS for file backups'
  printf "   %-25s %-50s\n" '-W secs'         'Warning age in SECONDS for image backups'
  printf "   %-25s %-50s\n" '-C secs'         'Critical age in SECONDS for image backups'
  printf "   %-25s %-50s\n" '-h'              'Display this help and exit'
}

function is_sqlite_db {
  local _dbfile="$1"
  declare -i schema_version=$(sqlite3 "$_dbfile" 'pragma schema_version;')
  if [[ $schema_version -ne 0 ]] ; then
    return 0
  else
    return 1
  fi
}

function main() {
  declare -i estat=0  # our exit status code (0,1,2,3)
  declare -i file_warning_age='86400'      # 24 hours
  declare -i file_critical_age='259200'    # 3 days
  declare -i image_warning_age='604800'    # 7 days
  declare -i image_critical_age='1209600'  # 3 days
  declare db_fname='/usr/local/var/urbackup/backup_server.db'

  ### fetch cmdline options
  while getopts ":hw:c:W:C:d:" opt; do
    case $opt in
      d)
        db_fname="$OPTARG"
        ;;
      w)
        file_warning_age="$OPTARG"
        ;;
      c)
        file_critical_age="$OPTARG"
        ;;
      W)
        image_warning_age="$OPTARG"
        ;;
      C)
        image_critical_age="$OPTARG"
        ;;
      h)
        usage
        exit 0
        ;;
      \?)
        echo "ERROR: Invalid option: -$OPTARG" >&2
        usage
        exit 1
        ;;
      :)
        echo "ERROR: Option -$OPTARG requires an argument." >&2
        exit 1
        ;;
    esac
  done
  readonly db_fname
  declare -r sqlite3="sqlite3 $db_fname"

  # validate data
  [[ ! -f "$db_fname" ]] && { echo "File not found: $db_fname"; exit 3; }
  [[ ! -r "$db_fname" ]] && { echo "Permission denied: $db_fname"; exit 3; }
  [[ $file_critical_age -lt $file_warning_age ]]    && { echo "File CRITICAL time must be greater than WARNING time"; exit 3; }
  [[ $image_critical_age -lt $image_warning_age ]]  && { echo "Image CRITICAL time must be greater than WARNING time"; exit 3; }
  is_sqlite_db "$db_fname" || { echo "Does not appear to be a valid database: $dbname"; exit 3; }

  ### check file backups
  declare -r last_file_backups=$($sqlite3 '
    SELECT  name,
            datetime(lastbackup, "localtime"),
            strftime("%s",CURRENT_TIMESTAMP) - strftime("%s",lastbackup)
    FROM clients;
  ')
  OLDIFS=$IFS; IFS=$'\n'
  for row in $last_file_backups ; do
    client_name=$(cut -d'|' -f1 <<< "$row")
    last_backup_abs=$(cut -d'|' -f2 <<< "$row")
    last_backup_age=$(cut -d'|' -f3 <<< "$row")
    if [[ $last_backup_age -gt $file_critical_age ]] ; then
      echo "CRITICAL: $client_name last file backup was $last_backup_abs"
      estat=2
    elif [[ $last_backup_age -gt $file_warning_age ]] ; then
      echo "WARNING: $client_name last file backup was $last_backup_abs"
      estat=1
    fi
  done
  IFS=$OLDIFS

  ### check image backups
  declare -r last_image_backups=$($sqlite3 '
    SELECT  name,
            datetime(lastbackup, "localtime"),
            strftime("%s",CURRENT_TIMESTAMP) - strftime("%s",lastbackup_image)
    FROM clients;
  ')
  OLDIFS=$IFS; IFS=$'\n'
  for row in $last_image_backups ; do
    client_name=$(cut -d'|' -f1 <<< "$row")
    last_backup_abs=$(cut -d'|' -f2 <<< "$row")
    last_backup_age=$(cut -d'|' -f3 <<< "$row")
    if [[ $last_backup_age -gt $image_critical_age ]] ; then
      echo "CRITICAL: $client_name last image backup was $last_backup_abs"
      estat=2
    elif [[ $last_backup_age -gt $image_warning_age ]] ; then
      echo "WARNING: $client_name last image backup was $last_backup_abs"
      estat=1
    fi
  done
  IFS=$OLDIFS

  if [[ $estat -eq 0 ]] ; then
    echo "OK: All backups up to date"
  fi
  exit $estat
}

main "$@"

exit 0
