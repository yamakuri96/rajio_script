#!/usr/local/bin/bash

##timefree
if [ $# -eq 2 ]; then
  CHANNEL=$1
  RECTIME=$2
##livestreaming
elif  [ $# -eq 1 ]; then
  CHANNEL=$1
else
  echo "使い方 : $0 局ID [タイムフリー時の時刻]"
  exit 1;
fi

if [ $# -eq 2 ]; then

	TIMEFREE=1
	AREAID=$CHANNEL

#RECTIME 202311131200-202311131215
	if [ ${#RECTIME} -ne 25 ]; then
		echo "タイムフリーの時間はこの形で   YYYYMMDDhhmm-YYYYMMDDhhmm";
		exit 1;
	fi
	START=${RECTIME:0:12}
	STOP=${RECTIME:13}
	if  [ `expr "$START" : '[0-9]*'` -ne 12 ] ; then
		echo "Not Number in TIME string"
		exit 1;
	fi
	if  [ `expr "$STOP" : '[0-9]*'` -ne 12 ] ; then
		echo "Not Number in TIME string"
		exit 1;
	fi
	if [ $START -gt $STOP ]; then
		echo "Start time is greater than Stop time"
		exit 1;
	fi
	DATESTR=${START:0:4}-${START:4:2}-${START:6:2}-${START:8:4}
	OUTFILENAME=${DATESTR}-${CHANNEL}-${OUTFILEPREFIX}_TF

else
	OUTFILENAME=`date '+%Y-%m-%d-%H%M'`-${CHANNEL}-${OUTFILEPREFIX}
	TIMEFREE=0
	MARGINTIME=120
	RECTIME=`expr ${RECTIME}  + ${MARGINTIME}`
	if [ $? -ne 0 ]; then
		echo "録画時間が不正です"
		exit 1;
	fi
fi

##

keyfile=0Key-radiko.bin

##
perl 0Random-radiko.pl $CHANNEL > mysetenv-$$.sh
if [ $? -ne 0 ]; then
	echo "局IDが一致しません";
	rm mysetenv-$$.sh
	exit 1;
fi

##
source mysetenv-$$.sh
##
rm mysetenv-$$.sh
##


if [ -f auth1_fms_hls_$$__${OUTFILEPREFIX}_${CHANNEL} ]; then
  rm -f auth1_fms_hls_$$__${OUTFILEPREFIX}_${CHANNEL}
fi

##
#
# access auth1
#
wget --user-agent="${USERAGENT}" \
     --header="pragma: no-cache" \
     --header="X-Radiko-App: aSmartPhone7a" \
     --header="X-Radiko-App-Version: ${APPVER}" \
     --header="X-Radiko-User: user-${USERID}" \
     --header="X-Radiko-Device: ${DEVICE}" \
     --save-headers \
     --tries=10 \
     --retry-connrefused \
     --waitretry=5 \
     --timeout=10 \
     -O auth1_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL} \
     https://radiko.jp/v2/api/auth1

if [ $? -ne 0 ]; then
  echo "アクセスに失敗しました"
  exit 1;
fi

#
# get partial key
#
authtoken=`cat auth1_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL} | perl -ne 'print $1 if(/x-radiko-authtoken: ([\w-]+)/i)'`
offset=`cat auth1_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL} | perl -ne 'print $1 if(/x-radiko-keyoffset: (\d+)/i)'`
length=`cat auth1_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL} | perl -ne 'print $1 if(/x-radiko-keylength: (\d+)/i)'`

partialkey=`dd if=$keyfile bs=1 skip=${offset} count=${length} 2> /dev/null | base64`

#echo "authtoken: ${authtoken} offset: ${offset} length: ${length} partialkey: $partialkey"

rm -f auth1_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL}

if [ -f auth2_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL} ]; then
  rm -f auth2_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL}
fi

#
# access auth2
#
wget --user-agent="${USERAGENT}" \
     --header="pragma: no-cache" \
     --header="X-Radiko-App: aSmartPhone7a" \
     --header="X-Radiko-App-Version: ${APPVER}" \
     --header="X-Radiko-User: user-${USERID}" \
     --header="X-Radiko-Device: ${DEVICE}" \
     --header="X-Radiko-AuthToken: ${authtoken}" \
     --header="X-Radiko-PartialKey: ${partialkey}" \
     --header="X-Radiko-Location: ${GPSLocation}" \
     --header="X-Radiko-Connection: wifi" \
     --retry-connrefused \
     --waitretry=5 \
     --tries=10 \
     --timeout=10 \
     -O auth2_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL} \
     https://radiko.jp/v2/api/auth2

if [ $? -ne 0 -o ! -f auth2_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL} ]; then
  echo "アクセスに失敗しました"
  exit 1;
fi

echo "準備OK"

auth_areaid=`cat auth2_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL} | perl -ne 'print $1 if(/^([^,]+),/i)'`
echo "エリアID: $auth_areaid"

rm -f auth2_fms_hls_$$_${OUTFILEPREFIX}_${CHANNEL}


#########
CRLF=$(printf '\r\n')

#########
if [ $TIMEFREE -eq 0 ] ;then
wget --user-agent="${USERAGENT}" "https://radiko.jp/v2/station/stream_smh_multi/${CHANNEL}.xml" -O ${CHANNEL}-$$.xml

stream_url=`echo "cat /urls/url[1]/playlist_create_url/text()" | xmllint --shell ${CHANNEL}-$$.xml | tail -2 | head -1`;

rm -f ${CHANNEL}-$$.xml


echo $stream_url

#
# ffmpeg
#
RETRYCOUNT=0
while :
do
mpv --user-agent="${USERAGENT}" \
    --http-header-fields="X-Radiko-AuthToken: ${authtoken}${CRLF}" \
    ${stream_url} \
    --stream-buffer-size=512K \
    --no-cache \

  if [ ${RETRYCOUNT} -ge 0 ]; then
    echo "MPV終了"
    exit 1;
  else
    RETRYCOUNT=`expr ${RETRYCOUNT} + 1`
  fi
done

else
stream_url="https://radiko.jp/v2/api/ts/playlist.m3u8?station_id=${CHANNEL}&l=15&ft=${START}00&to=${STOP}00"

mpv --user-agent="${USERAGENT}" \
    --cache-secs=30 \
    --stream-buffer-size=512K \
    --http-header-fields="X-Radiko-AuthToken: ${authtoken}${CRLF}" \
    ${stream_url} \

	if [ $? -ne 0 ]; then
		echo "タイムフリー終了"
		exit 1;
	fi
fi


exit 0;
