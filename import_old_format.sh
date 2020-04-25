#!/usr/bin/env bash

vdir=/System/Volumes/Data/Unix/Videos/Raw

function sqlrun {
	echo ".bail on">/tmp/sqlrun.sql
	echo "PRAGMA foreign_keys=ON;">>/tmp/sqlrun.sql
	echo "begin;">>/tmp/sqlrun.sql
	echo "$1">>/tmp/sqlrun.sql
	echo "commit;">>/tmp/sqlrun.sql
	sqlite3 ~/data/videos.db </tmp/sqlrun.sql
	if [ $? -ne 0 ] ; then
		echo Failed to run 
		cat /tmp/sqlrun.sql
		exit 1
	fi
	}
function process_line {
	program="$(tr '[:lower:]' '[:upper:]' <<< ${1:0:1})${1:1}"
	series=$2
	episode=$3
	section=$4
	start_time=$5
	end_time=$6

	sqlrun "insert or ignore into program(name) values ('$program');"
	sqlrun "insert or ignore into series(program_id,series_number,max_episodes) 
		values ((select id from program where name='$program'),$series,0);"
	sqlrun "insert or ignore into episode(series_id,episode_number,status) 
		values ((select series_id from videos where series_number=$series and program_name='$program'),$episode,0);"
	sqlrun "insert into section(episode_id,section_number,start_time,end_time,raw_file_id)
	values ((select episode_id from videos where series_number=$series 
	and program_name='$program' and episode_number=$episode),
	$section,strftime('%H:%M:%f','$start_time'),strftime('%H:%M:%f','$end_time'),
	(select id from raw_file where name='$name'));"
}
function process_info {
	for rec in $(cat $info)
	do
		process_line $(tr ',' ' '<<<$rec)
	done
	
}
for fn in $(find "$vdir" -type f -name "*mp4"|sort --version-sort)
do
	info=${fn/\.mp4/.info}
	name=${fn##*/}
	video_length=$(./mp4_length.pl $fn)
	sqlrun "insert or replace into raw_file(id,name,video_length,last_updated,status)
		values ((select id from raw_file where name='$name'),
		'$name',strftime('%H:%M:%f','$video_length'),datetime('now'),4);"
	test -f $info && process_info 

done
	
