#!/bin/sh

LOG_SIZE="1000" #Log size in kilobytes
DOMAIN="home.lan"
checkpid='unknown'
unamestr=$(uname)

# Determine platform; set pid function; set base location
if test "$unamestr" = 'Linux' || test "$unamestr" = 'Darwin'; then
   checkpid='pid=$(pidof unbound)'
   LD_BASE="/etc/unbound"
elif test "$unamestr" = 'FreeBSD'; then
   checkpid='pid=$(pgrep unbound)'
   LD_BASE="/var/unbound"
fi

LD_ZONE="$LD_BASE/zones"

usage()
{
  echo "Usage: $(basename "$0") -c file -- read zones from configuration file"
  echo "Usage: $(basename "$0") -f filename -- create local empty rpz file."
  echo "Usage: $(basename "$0") -f filename -url location -- create local rpz file and downloads data from url location"
  exit 2
}

# Program Exit code.
trap 'rm -f $LD_ZONE/*.tmp ' EXIT INT

log() {
  echo "($(basename $0)):" $1
  echo $(date) "($(basename $0)):" $1 >> $LD_ZONE/zone.log
}

rotate_log() {
  if test -f "$LD_ZONE/zone.log"; then
     [ $(du -k $LD_ZONE/zone.log | cut -f1) -gt "$LOG_SIZE" ] && rm -f $LD_ZONE/zone-1.log && mv $LD_ZONE/zone.log $LD_ZONE/zone-1.log
  fi
}


reload_zone() {
#arg 1: Zone name

eval $checkpid
if test -n "$pid"; then
   unbound-control -c "$LD_BASE/unbound.conf" auth_zone_reload $1
   log "RELOADED zone $1."
else
   log "Unbound not running. Unable to reload zone $1"
fi
}

validFormat(){
# arg 1: filename

HOSTS_COUNT=$(grep -c -E '^0\.0\.0\.0|^127\.0\.0\.1' "$1")

if test "$HOSTS_COUNT" -gt "5"; then
  return 0
else
  return 1
fi
}

# Procedure to create RPZ standard file header.
create_rpz_header(){
# arg1: filename
# arg2: zone name
# return filename.tmp

local SN=$(awk -v min=1000 -v max=9999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
{
  # Following TTL and SOA parameters do not matter but need to be present.
  echo "\$TTL 1H"
  echo "@ SOA ${2}. master.${2}.${DOMAIN}. ($SN 1h 15m 1w 2h)"
  echo " NS  localhost."
  if test -n "$URL"; then
     echo "; RPZ created from url -> $URL"
  fi
  echo ";"
} >> $1.tmp
}

create_rpz_file() {
# arg1: filename
# arg2: zone name
# return status 0/1

local RDATA="CNAME ."
local SN=$(awk -v min=1000 -v max=9999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
ret_value=0

if validFormat "$1.in"; then
  create_rpz_header $1 $2
  cat $1.in | sed -e 's/^0\.0\.0\.0 //' -e '/^127\.0\.0\.1/d' \
          -e '/^255\.255/d' -e '/::/d' -e 's/^#/;/' -e 's/#.*$//' -e 's/^ *//' -e '/^$/d'\
          -e '/^0\.0\.0\.0/d' -e '/^;/ ! s/$/ '"$RDATA"'/' >> $1.tmp

  if test "$?" -eq 0; then
      cp $1.tmp $1
  else
      rm -f $1.tmp
      log "ERROR converting the file $1"
      ret_value=1
  fi
else
  log "Possible invalid file format."
  ret_value=1
fi

return $ret_value
}

# Read configuration file, identify all zones.
# For each zone store URL and Filename. Then, call to download each file.
# Build RPZ file if necessary.
# Main program when calling zone-load.sh -c zone.conf
read_config() {

  test ! -f "$CONFIG" && log "File $CONFIG does not exist. Existing program. " $$ exit 2
  # Read config file and process each zone
  # Only rpz zones with #url field will be processed.
  log "Attempting zone refresh from $LD_ZONE/$CONFIG."
  while read line; do
    if echo $line | grep -q "^rpz:"; then
      # Read next 3 Lines
      read ZNAME && read ZURL && read ZFILE

      # Extract field values
      if (echo $ZNAME | grep -qw "name:") && (echo $ZURL | grep -wq "#url:") && (echo $ZFILE | grep -wq "zonefile"); then
        LZONE=$(echo $ZNAME | awk '{print $2}')
        LURL=$(echo $ZURL | awk '{print $2}')
        LFILE=$(echo $ZFILE | awk '{print $2}')

        # Download file
        if load_file $LZONE $LURL $LFILE; then
            # Build RPZ file. Convert if necessary.
            if grep -q "^\$TTL" "$LFILE.in" && grep -q -w "SOA" "$LFILE.in"; then
              mv "$LFILE.in" "$LFILE"
              log "File $LFILE is RPZ format. Moved file."
            else # Process host files. Start converting.
              if create_rpz_file $LFILE $LZONE; then
                log "CONVERTED file $LFILE to RPZ."
              else
                log "File $LFILE failed conversion."
              fi
            fi
          reload_zone $LZONE
        fi
        test -f "$LFILE.in" && rm -f "$LFILE.in"
      fi
    fi
  done < $CONFIG
}

# Download file from URL and test using etag.
load_file() {
# arg1: zone name
# arg2: url
# arg3: file name
#
#     return status
# 0 - success
# 1 - unmodified file http_code 304
# 2 - error

local ZONE="$1"
local URL="$2"
local FNAME="$3"

HTTP_RESPONSE=$(curl -s -S -f --connect-timeout 5 --etag-compare $ZONE.etag --etag-save $ZONE.etag $URL -o $FNAME.in -w "%{http_code}" 2>>$LD_ZONE/zone.log)
CURL_EXIT=$?

if test ! -f "$FNAME"; then
   log "ERROR: File "$FNAME.in" does not exist."
   STATUS=2
   rm -f "$ZONE.etag"
else

  if test "$HTTP_RESPONSE" -eq 200; then
      log "File $FNAME has new version."
      STATUS=0
  elif test "$HTTP_RESPONSE" -eq 304; then
      log "File $FNAME did not change."
      STATUS=1
  else
      STATUS=2
      error="Error processing $FNAME with url $URL. http_code is $HTTP_RESPONSE. Exit curl exit status $CURL_EXIT."
      test "$HTTP_RESPONSE" -eq 301 && error+=" Missing Etag."
      log "$error"
      rm -f "$ZONE.etag"
  fi
fi  
return $STATUS
}

# Function to add or create new zone file
# 1. From a local file eg. zone-load.sh -f myzone -url file:///users/var/myhosts.txt
# 2. From URL (zone is not auto registred in zone.conf) eg. zone-load.sh -f demo.rpz -url https://github/host.txt
# 3. Create blank rpz file eg. zone-load.sh -f myzone
create_zone(){

if test -z "$URL"; then
  # Create RPZ local file if it does not exist
  URL="localhost"
  test ! -f "$FILE" && create_rpz_header $FILE $FILE && mv $LD_ZONE/$FILE.tmp $FILE
elif test $(echo $URL | grep "^file"); then
    log "Processing local file. $URL"
    if curl -s -S $URL -o $FILE.in; then
       create_rpz_file $FILE $FILE && rm $FILE.in
    else
       log "File $URL does not exists."
    fi
else
  # Create rpz file and download data
  test ! -f "$FILE" && create_rpz_header $FILE $FILE && mv $LD_ZONE/$FILE.tmp $FILE

  if load_file $FILE $URL $FILE; then
     if create_rpz_file $FILE $ZONE; then
        log "CONVERTED file $FILE."
        rm -f $FILE.in && rm -f $FILE.etag
     else
        log "File $FILE failed conversion."
     fi
  fi
fi
}

# Main program starts here.
unset FILE CONFIG URL
test ! -d "$LD_ZONE" && LD_ZONE=$PWD
cd $LD_ZONE

rotate_log
log "Platform is $unamestr."

while [ $# -gt 0 ]; do
  case "$1" in
    -c) CONFIG="$2" ;;
    -f) FILE="$2" ;;
    -url) URL="$2" ;;
    -h|-?) usage ;;
    *) usage ;;
  esac
  shift
  shift
done

if test -n "$CONFIG"; then
    read_config
elif test -n "$FILE"; then
    create_zone $FILE
else
  usage
fi
exit 0
