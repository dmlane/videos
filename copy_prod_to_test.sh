#!/bin/bash

video_user="$(my_print_defaults -s videos)"
admin_user="$(my_print_defaults -s admin)"

echo Exporting
mysqldump $admin_user videos >/tmp/videos.dump || echo Export failed

echo Importing
mysql $admin_user test </tmp/videos.dump || echo Import failed
echo Done
