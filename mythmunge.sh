#!/bin/bash
#===============================================================================
# mythmunge.sh
# Uses mythcommflag and ffmpeg to manipulate MythTV recordings
# !Note: Edit defaults in DefaultsEditBlock below as appropriate for your system!
#
# Jerry Fath jerryfath@gmail.com
# Based on a script by: Ian Thiele icthiele@gmail.com
# 
#Copyright (c) 2016 Jerry Fath, Ian Thiele
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this
#software and associated documentation files (the "Software"), to deal in the Software
#without restriction, including without limitation the rights to use, copy, modify,
#merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
#permit persons to whom the Software is furnished to do so, subject to the following
#conditions:
#
#The above copyright notice and this permission notice shall be included in all copies
#or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
#INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
#PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
#LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT
#OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
#DEALINGS IN THE SOFTWARE.
#
#
# Example MythTV user job:
# mythmunge.sh "%DIR%/%FILE%" "fileop=new,newdir=/mnt/VidTV/DVR"
#
# Usage: mythmunge.sh /recpath/recfile [options]
# options is a string of comma delimited list of options
#   fileop=[archive|replace|new]
#   newdir=/directory/for/new
#   remcom=[yes|no]
#   fileformat=
#   vcodec=
#   vcodecargs=
#   acodec=
#   acodecargs=
#   notify=[none|start|end|startend|error]
#   email=
#   cfgfile=
#   tmpdir=
#   logdir=
#   dbpasswd=
#   datefirst=
#   tvdblookup=
#   precmd=
#   postcmd=
#

#fileop=
#archive = move original MythTV recording into an archives directory (default)
#replace = overwrite original with new commercial-less recording
#new = don't alter the MythTV version, but write new recording to another directory

#notify=
#none|start|end|startend|error when to send job notification emails
#
#newdir= is required if fileop is 'new'
#
# Example of OPTIONS used to transcode to x264 video with mp3 audio
# acodec=libmp3lame,acodecargs=-ac 2 -ar 48000 -ab 128k,vcodec=libx264,vcodecargs=-preset ultrafast
#
# TODO:
# !!!Avoid duplicate episode numbers if lookup fails
# !!!Use last two digits of year as season and mmdd as episode if lookup fails
# !!!Check problem with last segment when removing commercials

#===============================================================================

#
# get command line args for later use and use in defaults
#
PROG=$(basename $0)
PROGNOEXT=$(basename $0 .sh)
ORIGFILE="$1"
OPTIONSTR="$2"

#DefaultsEditBlock (edit these values as appropriate for your system) ==========
DEF_CFGFILE="${HOME}/${PROGNOEXT}/${PROGNOEXT}.cfg"
DEF_FILEOP="new"
DEF_NEWDIR="${HOME}/${PROGNOEXT}/DVR"
DEF_REMCOM="no"
DEF_FILEFORMAT="mkv"
DEF_NOTIFY="none"
DEF_VCODEC="copy"
DEF_VCODECARGS=""
DEF_ACODEC="copy"
DEF_ACODECARGS=""
DEF_EMAIL="user@emailserver.com"
DEF_TMPDIR="${HOME}/${PROGNOEXT}/tmp"
DEF_LOGDIR="${HOME}/${PROGNOEXT}/log"
DEF_DBPASSWD="mythtv"
DEF_DATEFIRST="no"
DEF_TVDBLOOKUP="yes"
DEF_PRECMD=""
DEF_POSTCMD=""
#DefaultsEditBlock==============================================================


#-------------------------------------------------------------------------------
#
# Parse options from OPTIONSTR and/or config file
# Precedence: command line, config file, default
#

#
# Option parsing helper function
# Usage: var=$( optionvalue "option_search_string" "default_value" )
# Uses globals OPTIONSTR, CFGOPTIONSTR
optionvalue() {
    OPT_THIS="${2}"
    if [ -n "`echo "${OPTIONSTR}" | grep ${1}`" ]; then
        OPT_THIS="`echo "${OPTIONSTR}" | sed -r "s/.*${1}([^,]*).*/\1/"`"
    else
        if [ -n "`echo "${CFGOPTIONSTR}" | grep ${1}`" ]; then
            OPT_THIS="`echo "${CFGOPTIONSTR}" | sed -r "s/.*${1}([^,]*).*/\1/"`"
        fi
    fi
    echo "${OPT_THIS}"
}

CFGOPTIONSTR=""
OPT_CFGFILE=$( optionvalue "cfgfile=" "${DEF_CFGFILE}" )
#Look for options in config file too
CFGOPTIONSTR="`grep '^options=' "${OPT_CFGFILE}"`"

OPT_FILEOP=$( optionvalue "fileop=" "${DEF_FILEOP}" )
OPT_NEWDIR=$( optionvalue "newdir=" "${DEF_NEWDIR}" )
OPT_REMCOM=$( optionvalue "remcom=" "${DEF_REMCOM}" )
OPT_FILEFORMAT=$( optionvalue "fileformat=" "${DEF_FILEFORMAT}" )
OPT_ACODEC=$( optionvalue "acodec=" "${DEF_ACODEC}" )
OPT_ACODECARGS=$( optionvalue "acodecargs=" "${DEF_ACODECARGS}" )
OPT_VCODEC=$( optionvalue "vcodec=" "${DEF_VCODEC}" )
OPT_VCODECARGS=$( optionvalue "vcodecargs=" "${DEF_VCODECARGS}" )
OPT_NOTIFY=$( optionvalue "notify=" "${DEF_NOTIFY}" )
OPT_EMAIL=$( optionvalue "email=" "${DEF_EMAIL}" )
OPT_TMPDIR=$( optionvalue "tmpdir=" "${DEF_TMPDIR}" )
OPT_LOGDIR=$( optionvalue "logdir=" "${DEF_LOGDIR}" )
OPT_DBPASSWD=$( optionvalue "dbpasswd=" "${DEF_DBPASSWD}" )
OPT_DATEFIRST=$( optionvalue "datefirst=" "${DEF_DATEFIRST}" )
OPT_TVDBLOOKUP=$( optionvalue "tvdblookup=" "${DEF_TVDBLOOKUP}" )
OPT_PRECMD=$( optionvalue "precmd=" "${DEF_PRECMD}" )
OPT_POSTCMD=$( optionvalue "postcmd=" "${DEF_POSTCMD}" )

#-------------------------------------------------------------------------------
#Email notifications functions using ssmpt
#
donotify() {
    if [ -n "${OPT_EMAIL}" ]; then
        echo -e "$1" | ssmtp "$OPT_EMAIL"
    fi
}

MAILTEXTERREARLY="Subject:${PROGNOEXT} Fail\n\n${PROGNOEXT} error processing ${ORIGFILE}\n"
quiterrorearly() {
  if [ "$OPT_NOTIFY" == "startend" ] || [ "$OPT_NOTIFY" == "end" ] || [ "$OPT_NOTIFY" == "error" ]; then
    donotify "$MAILTEXTERREARLY" 
  fi
  exit 1
}

quiterror() {
  if [ "$OPT_NOTIFY" == "startend" ] || [ "$OPT_NOTIFY" == "end" ] || [ "$OPT_NOTIFY" == "error" ]; then
    donotify "$MAILTEXTERR"
  fi
  exit 1
}

quitsuccess() {
  if [ "$OPT_NOTIFY" == "startend" ] || [ "$OPT_NOTIFY" == "end" ]; then
    donotify "$MAILTEXT"
  fi
  exit 0
}

#-------------------------------------------------------------------------------
#Check usage
#
if [ ! -f "$ORIGFILE" ]; then
    echo "Usage: $PROG /recpath/recfile" [OPTIONSTR]
    echo "OPTIONSTR is a comma delimited list of options"
    echo "fileop=[archive|replace|new]"
    echo "newdir="
    echo "remcom=[yes|no]"
    echo "vcodec=[copy|ffmpeg codec]"
    echo "vcodecargs="
    echo "acodec=[copy|ffmpeg codec]"
    echo "acodecargs="
    echo "notify=[none|start|end|startend|error]"
    echo "email="
    echo "cfgfile="
    echo "tmpdir="
    echo "logdir="
    echo "dbpasswd="
    echo "datefirst="
    echo "tvdblookup="
    echo "precmd"
    echo "postcmd="
    echo ""
    echo "$PROG: file doesn't exist, aborting."
    quiterrorearly
fi

#-------------------------------------------------------------------------------
#split directory and filename
#
#!!!Get this from original filename
ORIGSUFFIX=".ts"

RECDIR=`dirname $ORIGFILE`
BASENAME=`basename $ORIGFILE`
BASENOEXT=`basename $BASENAME ${ORIGSUFFIX}`
ARCHIVEDIR="$RECDIR/archive"

#
#one log file for each recording
#
logfile="${OPT_LOGDIR}/${BASENAME}.log"
>${logfile}

#start log file with date header
echo "$PROG: Starting `date`" >>${logfile}

#-------------------------------------------------------------------------------
# get required info from mythconverg db
#
DBHostName="localhost"
DBUserName="mythtv"
DBPassword="$OPT_DBPASSWD"
DBName="mythconverg"
#connect to DB
mysqlconnect="mysql -N -h$DBHostName -u$DBUserName -p$DBPassword $DBName"
export mysqlconnect

#determine chanid and starttime from recorded table
dbchanid=`echo "select chanid from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
dbstarttime=`echo "select starttime from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
#get title and subtitle recorded table
dbtitle=`echo "select title from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
dbtitlesub=`echo "select subtitle from recorded where basename=\"$BASENAME\";" | $mysqlconnect`

echo "chanid: ${dbchanid}   dbstarttime: ${dbstarttime}"  >>${logfile}
echo "dbtitle: ${dbtitle}   dbtitlesub: ${dbtitlesub}"  >>${logfile}


if [ -z "$dbchanid" ] || [ -z "$dbstarttime" ]
then
    echo "$PROG: Recording not found in MythTV database, script aborted." >>${logfile}
    quiterrorearly
fi

#determine FPS (frames per second) from db, which is used to determine the seek time to extract video clips
fps=$(echo "scale=10;`echo "select data from recordedmarkup where chanid=$dbchanid AND starttime='$dbstarttime' and type=32" | $mysqlconnect` / 1000.0" | bc)

if [ -z "$fps" ]
then
    echo "$PROG: Frames per second value not found in MythTV database, script aborted." >>${logfile}
    quiterrorearly
fi


#Keep title, titlesub, and start time in one variable for legacy purposes
#Avoid re-writing code that expects that format
#!!!Fix
OUTNAME="${dbtitle}~${dbtitlesub}~${dbstarttime}"

#
#Set email notifications text
#
MAILTEXTSTART="Subject:${PROGNOEXT} Start\n\n${PROGNOEXT} started processing ${dbtitle} ${dbtitlesub} ${dbstarttime} ${dbchanid}\n"
MAILTEXT="Subject:${PROGNOEXT} Success\n\n${PROGNOEXT} successfully processed ${dbtitle} ${dbtitlesub} ${dbstarttime} ${dbchanid}\n"
MAILTEXTERR="Subject:${PROGNOEXT} Fail\n\n${PROGNOEXT} error processing ${dbtitle} ${dbtitlesub} ${dbstarttime} ${dbchanid}\n"

#
#Send start notification if requested
#
if [ "$OPT_NOTIFY" == "startend" ] || [ "$OPT_NOTIFY" == "start" ]; then
  donotify "$MAILTEXTSTART"
fi

# make sure we have a sane environment
if [ -z "`which ffmpeg`" ]; then
    echo "$PROG: FFMpeg not present in the path. Adjust environment or install ffmpeg" >>${logfile}
    quiterror
fi

#
# Execute precmd if specified
# Note, this could be dangerous depending on script context
# We should be running as user mythtv with limit permissions
if [ -n "${OPT_PRECMD}" ]; then
    eval ${OPT_PRECMD}
fi
    
#-------------------------------------------------------------------------------

#tmp clip directory
if [ -z "`ls "${OPT_TMPDIR}"`" ]; then
    mkdir -p "${OPT_TMPDIR}"
fi


#DEBUG
#Uncomment to force commercial flagging
#mythutil --chanid $dbchanid --starttime "$dbstarttime" --clearskiplist 

CUTLIST="`mythutil --chanid $dbchanid --starttime "$dbstarttime" --getskiplist | grep "Commercial Skip List" | sed 's/Commercial Skip List: $//'`"

if [ ${#CUTLIST} -le 1 ]; then
    echo "$PROG: no skiplist found....generating new skiplist" >>${logfile}
    mythcommflag --chanid $dbchanid --starttime "$dbstarttime" 
    CUTLIST="`mythutil --chanid $dbchanid --starttime "$dbstarttime" --getskiplist | grep "Commercial Skip List" | sed 's/Commercial Skip List: $//'`"
else
    echo "$PROG: using existing skiplist" >>${logfile}
fi

echo "$PROG: Skiplist:$CUTLIST Length:${#CUTLIST}" >>${logfile}


#If OPT_REMCOM is no make cutlist one entry that spans entire video
#
if [ "$OPT_REMCOM" == "no" ]; then
    CUTLIST="0-2600000"
else
    #cutlist provides a list of frames in the format start-end,[start1-end1,....] to cut 
    #we swap this list so that it provides the ranges of video we want in the format
    #  start-end start1:end1 ....
    CUTLIST=`mythutil --chanid $dbchanid --starttime "$dbstarttime" --getskiplist | grep "Commercial Skip List" | sed 's/Commercial Skip List: //' | \
    sed 's/-/ /g' | sed 's/^\|$/-/g' | sed 's/,/-/g'`
fi

#!!!Always use matroska for clip containers or use specified file format??
echo "$PROG: ffmpeg -i ${RECDIR}/${BASENAME} -acodec ${OPT_ACODEC} ${OPT_ACODECARGS} -vcodec ${OPT_VCODEC} ${OPT_VCODECARGS} -f matroska -ss STARTFRAME -t DURATION ${OPT_TMPDIR}/${BASENOEXT}_clip#.mkv" >>${logfile}

clipcount=0
for i in ${CUTLIST}
do
    start=`echo $i | sed 's/ //g' | sed 's/^\(.*\)-.*$/\1/'`
    end=`echo $i | sed 's/ //g' | sed 's/^.*-\(.*\)$/\1/'`

    echo "$PROG: Clip:$clipcount  Start:$start  End:$end" >>${logfile}

    #if $start is empty, deal with it
    if [ -z $start ]; then
	#set start to 0
	start=0
	if [ -z $end ]; then
	    end=0
	fi
	if [ "$start" -eq "$end" ]; then
	    continue
	fi
    fi
    #convert start into time in seconds (divide frames by frames per second)    
    start=$(echo "scale=8; $start / $fps" | bc -l)
    #if $end is not null, we can do things
    if [ -n "$end" ]; then
	clipcount=$((++clipcount))
	end=$(echo "scale=8; $end / $fps" | bc -l)
	duration=`echo "$end - $start" | bc -l`	
        printf -v clipstr "%03d" ${clipcount}
	ffmpeg -i ${RECDIR}/${BASENAME} -acodec ${OPT_ACODEC} ${OPT_ACODECARGS} -vcodec ${OPT_VCODEC} ${OPT_VCODECARGS} -f matroska -ss $start -t $duration ${OPT_TMPDIR}/${BASENOEXT}_${clipstr}.mkv &>>${logfile}
    elif [ -z "$end" ]; then
	clipcount=$((++clipcount))
        printf -v clipstr "%03d" ${clipcount}
        ffmpeg -i ${RECDIR}/${BASENAME} -acodec ${OPT_ACODEC} ${OPT_ACODECARGS} -vcodec ${OPT_VCODEC} ${OPT_VCODECARGS} -f matroska -ss ${start} ${OPT_TMPDIR}/${BASENOEXT}_${clipstr}.mkv &>>${logfile}
    fi

done

echo "#start of list: ${OPT_TMPDIR}/${BASENOEXT}_###" >"${OPT_TMPDIR}/${BASENOEXT}.lst"
for i in `ls ${OPT_TMPDIR}/${BASENOEXT}_* | sort`
do
    echo "file '$i'" >>"${OPT_TMPDIR}/${BASENOEXT}.lst"
done
echo "#end of list" >>"${OPT_TMPDIR}/${BASENOEXT}.lst"

if [ -f ${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT} ]; then
    rm -f ${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT}
fi

ffmpeg -f concat -i "${OPT_TMPDIR}/${BASENOEXT}.lst" -c copy ${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT}

#cleanup OPT_TMPDIR
rm -f ${OPT_TMPDIR}/*.mkv
rm -f ${OPT_TMPDIR}/*.lst

#-------------------------------------------------------------------------------
#
# If we are replacing or archiving the MythTV file.  We need to update the DB
#
if [ "$OPT_FILEOP" != "new" ]; then

    #clear out the old cutlist
    mythutil --chanid $dbchanid --starttime "$dbstarttime" --clearcutlist &>>${logfile}

    #we'll need a new filesize to update the db with
    filesize=$(du ${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT} | awk '{print $1}') 

    #update db with new filesize and filename
    cat <<EOF | $mysqlconnect
UPDATE
	recorded
SET
	cutlist = 0,
	filesize = ${filesize},
	basename = "${BASENOEXT}.${OPT_FILEFORMAT}"
WHERE
	chanid = ${dbchanid} AND
	starttime = "${dbstarttime}";
EOF

    #delete the old commercial skip info
    cat <<EOF | $mysqlconnect
DELETE FROM
	recordedmarkup
WHERE	
	chanid = ${dbchanid} AND
	starttime = "${dbstarttime}" AND
	(type = 4 OR type = 5);
EOF
 
    cat <<EOF | $mysqlconnect
DELETE FROM
	recordedseek
WHERE
	chanid = ${dbchanid} AND
	starttime = "${dbstarttime}";

EOF

    # Archive original if requested
    if [ "${OPT_FILEOP}" == "replace" ]; then
        echo "$PROG: removing original file ${RECDIR}/${BASENAME}" >>${logfile}
        rm -f "${RECDIR}/${BASENAME}"
        ERROR=$?
        if [ $ERROR -ne 0 ]; then
                echo "$PROG: failed to remove ${RECDIR}/${BASENAME}" >>${logfile}
        fi
    else
        #archive is the default action
        if [ -z "`ls "${ARCHIVEDIR}"`" ]; then
            mkdir -p "${ARCHIVEDIR}"
        fi
        echo "$PROG: moving original file to ${ARCHIVEDIR}/${BASENAME}" >>${logfile}
        mv -f "${RECDIR}/${BASENAME}" "${ARCHIVEDIR}/${BASENAME}"
    fi
fi

#-------------------------------------------------------------------------------

#
# Function to look up TV season and episode information
# Used to help rename when we are keeping the original MythTV file
#
tv_lookup ()
{
#
# Uses globals:  OUTNAME, OUTDIR, PROGNOEXT
# Sets globals: OUTNAME, OUTDIR
# Uses config file: OPT_CFGFILE
#
#

#Default are only used if global OUTDIR and/or OUTNAME are not set before calling
local DEFOUTDIR="$OPT_NEWDIR"
local DEFOUTNAME="${PROGNOEXT}-output.${OPT_FILEFORMAT}"

# Config file format 
# nolookup=showtitle 
# episodedatefirst=showtitle 
# 
# nolookup will prevent season/episode lookup for a show or globally if * wildcard is specified.  S99E99 will be used in file name 
# episodedatefirst will prepend @RecDate to the episode name in order to force sorting by date if S99E99.  The * wildcard can be used to force all 
local CONFIGFILE="$OPT_CFGFILE"

local EPDATEFIRSTG 
local EPDATEFIRSTL 
local NOLOOKUPG 
local NOLOOKUPL

#Get global settings from command line or config
if [ "${OPT_DATEFIRST}" = "yes" ]; then
    EPDATEFIRSTG="*"
else
    EPDATEFIRSTG=$(cat "$CONFIGFILE" | grep "^episodedatefirst=\*$")
fi

if [ "${OPT_TVDBLOOKUP}" = "no" ]; then
    NOLOOKUPG="*"
else
    NOLOOKUPG=$(cat "$CONFIGFILE" | grep "^nolookup=\*$") 
fi
 
#If output dir isn't specified, use default dir 
if [ -z "$OUTDIR" ]; then 
    OUTDIR="$DEFOUTDIR" 
fi 
   
#Generate ouput file and directory names 
local SHOWFIELD="" 
local EPFIELD="" 
local RECFIELD="" 
local SXXEXX="" 
local SEASONFIELD="" 
local CHKFORM=$(echo "$OUTNAME" | grep "\~") 
if [ -z "$OUTNAME" ]; then 
    #If outname not specified use default
    OUTNAME="$DEFOUTNAME"
else 
    #Replace all bad filename characters 
    OUTNAME=$(echo $OUTNAME | sed -e "s:[/?<>\\:*|\"\^]:_:g") 
    #OUTNAME=$(echo $OUTNAME | sed -e 's:[^a-zA-Z0-9~ -]:_:g') 
    #If no ~ delimeters use output name as passed 
    if [ ! -z "$CHKFORM" ]; then 
        #Split OUTNAME into components 
        SHOWFIELD=$(echo $OUTNAME | gawk 'BEGIN { FS = "~" } {print $1}') 
        EPFIELD=$(echo $OUTNAME | gawk 'BEGIN { FS = "~" } {print $2}') 
        RECFIELD=$(echo $OUTNAME | gawk 'BEGIN { FS = "~" } {print $3}') 
 
        #grep a config file to see if we should do a lookup for this show 
        NOLOOKUPL=$(cat "$CONFIGFILE" | grep "^nolookup=$SHOWFIELD$") 
        if [ -z "$NOLOOKUPL" ] && [ -z "$NOLOOKUPG" ]; then 
            #Get Season and Episode string 
            SXXEXX=$(titlesub2se.sh "$SHOWFIELD" "$EPFIELD") 
            SEASONFIELD=$(echo $SXXEXX | sed -e 's:S\([0-9]*\)E[0-9]*:\1:') 
        else 
            SXXEXX="S99E99" 
            SEASONFIELD="99" 
        fi 
 
 
        #Add record date to episode in various ways 
        EPDATEFIRSTL=$(cat "$CONFIGFILE" | grep "^episodedatefirst=$SHOWFIELD$") 
        if [ -z "$EPDATEFIRSTG" ] && [ -z "$EPDATEFIRSTL" ]; then 
            #Blank episodes don't sort well in WMC so use @recorddate as apname 
            if [ -z "$EPFIELD" ]; then 
                EPFIELD="@$RECFIELD" 
            else 
                EPFIELD="$EPFIELD - [$RECFIELD]" 
            fi 
        else 
            #Add the record date to the front of the episode name so shows will 
            #sort alphabetically by date if season and episode don't look up 
            if [ -z "$EPFIELD" ]; then 
                EPFIELD="@$RECFIELD" 
            else 
                EPFIELD="@$RECFIELD $EPFIELD" 
            fi 
        fi 
 
        #Build output name from components 
        OUTNAME="$SHOWFIELD - $SXXEXX - $EPFIELD" 
        OUTDIR="$OUTDIR/$SHOWFIELD/Season $SEASONFIELD" 
    fi 
fi

}

#-------------------------------------------------------------------------------
#
# If we are keeping the original MythTV file, we want to rename th commercial-less
# file based on the show title and episode, then move the file to a new directory
# A MythTV user job handles this by calling like:
# mythmunge.sh "%DIR%/%FILE%" "fileop=new,newdir=/mnt/VidTV/DVR,title=%TITLE%,titlesub=%SUBTITLE%,starttime=%STARTTIME%"
#
if [ "$OPT_FILEOP" == "new" ]; then
    # If requested, move new file to new directory rather than replacing Myth file and DB
    echo "$PROG: Keeping original file" >>${logfile}
    if [ -z "${OUTDIR}" ]; then
        OUTDIR="$OPT_NEWDIR"
    fi
    if [ -z "$OUTNAME" ]; then 
        OUTNAME="${BASENOEXT}.${OPT_FILEFORMAT}"
    fi
    tv_lookup
    echo "$PROG: moving new file to $OUTDIR/$OUTNAME.${OPT_FILEFORMAT}" >>${logfile}
    if [ -z "`ls "${OUTDIR}"`" ]; then
        mkdir -p "${OUTDIR}"
    fi
    EXTVAR_NEWFILE="$OUTDIR/$OUTNAME.${OPT_FILEFORMAT}"
    mv -f "${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT}" "${EXTVAR_NEWFILE}"
fi

#-------------------------------------------------------------------------------

#
# Execute postcmd if specified
# Note, this could be dangerous depending on script context
# We should be running as user mythtv with limit permissions
#!!!Need to make EXTVAR_NEWFILE available to postcmd
if [ -n "${OPT_POSTCMD}" ]; then
    eval ${OPT_POSTCMD}
fi

#-------------------------------------------------------------------------------
echo "$PROG: Completed successfully `date`" >>${logfile}

quitsuccess

