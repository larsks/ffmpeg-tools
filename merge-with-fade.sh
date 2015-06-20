#!/bin/bash

# This script will merge a number of individual video files into a single video
# file, with fade in/fade out transitions in between.

count_frames () {
	ffprobe -v error -count_frames -select_streams v:0 \
		-show_entries stream=nb_read_frames \
		-of default=nokey=1:noprint_wrappers=1 "$@"
}

while getopts o: ch; do
	case $ch in
		(o) output=$OPTARG;;
	esac
done
shift $((OPTIND-1))

[ "$output" ] || {
	echo "ERROR: you must provide an output filename" >&2
	exit 2
}

workdir=$(mktemp -d fadeXXXXXX)
trap "rm -rf $workdir" EXIT

echo "processing $1"
frames=$(count_frames "$1")
ffmpeg -v error -i "$1" -vf fade=out:$((frames-15)):15 \
	-c:v libx264 -qp 0 -preset ultrafast \
	-strict -2 -y \
	$workdir/first.mp4
echo "file '$PWD/$workdir/first.mp4'" >> $workdir/concat
shift

for vid in "$@"; do
	echo "processing $vid"
	vidtmp=$(mktemp $workdir/vidXXXXXX.mp4)
	frames=$(count_frames "$vid")
	ffmpeg -v error -i "$vid" \
		-vf "fade=in:0:15,fade=out:$((frames-15)):15" \
		-c:v libx264 -qp 0 -preset ultrafast \
		-strict -2 -y \
		$vidtmp
	echo "file '$PWD/$vidtmp'" >> $workdir/concat
done

echo "concatenating segments"
ffmpeg -v error -f concat -i $workdir/concat -c copy -y $workdir/final.mp4

mv $workdir/final.mp4 $output

