#!/bin/bash

# This will create a simple title animation and overlay it on 
# another video.

font='Helvetica'
pointsize=48
chunksize=20
output="title-animation.mov"
duration=10
ffmpeg="ffmpeg -v error"
fgcolor='204,0,0'
bgcolor='100,100,100'

while getopts 'f:p:c:d:Fqw:K:B:' ch; do
	case $ch in
		(f) font=$OPTARG;;
		(p) pointsize=$OPTARG;;
		(c) chunksize=$OPTARG;;
		(d) duration=$OPTARG;;
		(F) force=1;;
		(q) quick=1;;
		(w) watermark="$OPTARG";;
		(K) fgcolor="$OPTARG";;
		(B) bgcolor="$OPTARG";;
	esac
done
shift $((OPTIND - 1))

[ $# -eq 3 ] || {
	echo "$0: usage: $0 [-f font] [-p pointsize] [-c chunksize] input output title" <&2
	exit 2
}

input=$1
output=$2
text=$3

workdir=$(mktemp -d titleXXXXXX)
trap "rm -rf $workdir" EXIT

# get the size of the text. This uses MSL
# (http://www.imagemagick.org/script/conjure.php) to figure out the image size
# required for the given text, font, and size.
echo "determining the size of the title"
msl=$workdir/fontquery.msl
cat > $msl <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<image>
  <query-font-metrics text="%[text]" font="$font" pointsize="$pointsize" />
  <print output="%[msl:font-metrics.width]x%[msl:font-metrics.height]\n" />
</image>
EOF

geo=$(conjure -text "$text" $msl)
width=${geo%x*}
height=${geo#*x}
padw=$((width+40))
padh=$((height+20))

# create title image
echo "generating title image"
title=$workdir/title.png
convert -size ${padw}x${padh} xc:none \
	-fill "rgb($bgcolor)" \
	-draw "rectangle 10,10 $padw,$padh" \
	-fill "rgb($fgcolor)" \
	-draw "rectangle 0,0 $((padw-10)),$((padh-10))" \
	-fill 'rgb(0,0,0)' \
	-font "$font" -pointsize $pointsize -draw "text 10,$((height-10)) '$text'" \
	$title


echo "generating mask"
convert -size ${padw}x${padh} xc:none $workdir/mask.png

echo "generating frames"
for ((i=1; i*chunksize <= padw; i++)); do
	pos=$((i*chunksize))
	convert "$title" -crop ${pos}x${padh}+0+0 $workdir/frame-$i-raw.png
	composite $workdir/frame-$i-raw.png $workdir/mask.png $workdir/frame-$i.png
done

convert "$title" -crop $((i*frame))x$padh $workdir/frame-$i.png

echo "generating title animation"
$ffmpeg -start_number 1 -i $workdir/frame-%d.png -pix_fmt argb -c:v qtrle -y $workdir/sequence.mov

if [ "x$quick" = x1 ] && ! [ "$watermark" ]; then
	# This uses the technique described in http://superuser.com/questions/508859/how-can-i-specify-how-long-i-want-an-overlay-on-a-video-to-last-with-ffmpeg
	# in which we chop the video into two pieces, perform the overlay on the short opening
	# portion, and then concatenate everything back together.  These means we don't need
	# to re-encode the entire video.

	echo '*** THIS MECHANISM DOES NOT APPEAR TO WORK ***'
	exit 1

	echo "compositing title onto video (quick)"
	$ffmpeg -i "$input" -i $workdir/sequence.mov \
		-filter_complex "[0:v][1:v]overlay=0:(main_h-overlay_h-20):enable='between(t,0,${duration})'" \
		-c:v libx264 -c:a copy -t $duration -preset ultrafast $workdir/start.mp4
	$ffmpeg -i "$input" -ss $duration -c copy $workdir/end.mp4

	echo "generating final output"
	$ffmpeg -f concat -i <(printf "file '$PWD/$workdir/start.mp4'\nfile '$PWD/$workdir/end.mp4'\n") \
		-c copy $([ "x$force" = x1 ] && echo "-y") "$output"

else
	# This reencodes the entire video.
	echo "compositing title onto video (accurate)"
	ffmpeg -i "$input" -i $workdir/sequence.mov ${watermark:+-i "$watermark"} \
		-filter_complex "
			[0:v][1:v]overlay=0:(main_h-overlay_h):enable='between(t,0,${duration})'[out1]
			${watermark:+;[out1][2:v]overlay=(main_w-overlay_w-10):10[out2]}" \
		-map "[$([ "$watermark" ] && echo out2 || echo out1)]" -map 0:a \
		-c:v libx264 -c:a copy $([ "x$force" = x1 ] && echo "-y") "$output"
fi


# Reference material
#
# http://www.imagemagick.org/script/conjure.php
# http://stackoverflow.com/questions/1392858/with-imagemagick-how-can-you-see-all-available-fonts
# http://www.imagemagick.org/Usage/draw/
# http://superuser.com/questions/508859/how-can-i-specify-how-long-i-want-an-overlay-on-a-video-to-last-with-ffmpeg
# http://ksloan.net/watermarking-videos-from-the-command-line-using-ffmpeg-filters/
# http://superuser.com/questions/624567/ffmpeg-create-a-video-from-images
# http://video.stackexchange.com/questions/12105/add-an-image-in-front-of-video-using-ffmpeg

