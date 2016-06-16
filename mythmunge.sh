#!/bin/bash
#===============================================================================
# mythmunge.sh
# Uses mythcommflag and ffmpeg to manipulate MythTV recordings
# !Note: Edit defaults in DefaultsEditBlock below as appropriate for your system!
# Dependencies: mythcommflag, mythutil, ffmpeg (>= v1.1), ssmtp(optional), curl and agrep
#
# Jerry Fath jerryfath at gmail dot com
# Based on a script by: Ian Thiele icthiele at gmail dot com
# TheTVDB lookup code base on MythSExx by Adam Outler outleradam at hotmail dot com
# 
#Copyright (c) 2016 Jerry Fath, Ian Thiele, Adam Outler
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
# Usage: mythmunge.sh /recpath/recfile [options]
# options is a string of comma delimited key=value pairs
# see README.md for usage and option descriptions
#
# Example MythTV user job:
# mythmunge.sh "%DIR%/%FILE%" "fileop=new,newdir=/mnt/VidTV/DVR"
#
#
# TODO:
# !!!Implement nameformat and folderformat
# !!!Check problem with last segment when removing commercials

#===============================================================================

#
# get command line args for later use and use in defaults
PROG=$(basename $0)
PROGNOEXT=$(basename $0 .sh)
ORIGFILE="$1"
OPTIONSTR="$2"

#
#== DefaultsEditBlock (edit these values as appropriate for your system) =======
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
DEF_EPDATEFIRST="no"
DEF_TVDBLOOKUP="yes"
DEF_NAMEFORMAT="yyyy-mm-dd"
DEF_FOLDERFORMAT="/t/s"
DEF_PRECMD=""
DEF_POSTCMD=""
DEF_TVDBTIMEOUT="50"
DEF_TVDBAPIKEY="6DF511BB2A64E0E9"
#== DefaultsEditBlock===========================================================

# We put a little code above for ease of editing defaults
# from here on, all code is wrapped in functions and the last line of the
# file calls our main function.  This construct allows us to forward reference
# worker functions and keeps the code much more readable
#
function main ()
{
    parseoptions
    init
    checkusage
    querydb
    initp2
    transcodecut
    updatedb
    archivedelete
    namemovenew
    cleanup
    quitsuccess
}

#-------------------------------------------------------------------------------
# Option parsing helper function
# Usage: var=$( optionvalue "option_search_string" "default_value" )
# Uses globals OPTIONSTR, CFGOPTIONSTR
#
function optionvalue()
{
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

#-------------------------------------------------------------------------------
# Parse options from OPTIONSTR and/or config file
# Precedence: command line, config file, default
#
function parseoptions ()
{
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
    OPT_EPDATEFIRST=$( optionvalue "epdatefirst=" "${DEF_EPDATEFIRST}" )
    OPT_TVDBLOOKUP=$( optionvalue "tvdblookup=" "${DEF_TVDBLOOKUP}" )
    OPT_NAMEFORMAT=$( optionvalue "nameformat=" "${DEF_NAMEFORMAT}" )
    OPT_FOLDERFORMAT=$( optionvalue "folderformat=" "${DEF_FOLDERFORMAT}" )
    OPT_PRECMD=$( optionvalue "precmd=" "${DEF_PRECMD}" )
    OPT_POSTCMD=$( optionvalue "postcmd=" "${DEF_POSTCMD}" )
    OPT_TVDBTIMEOUT=$( optionvalue "tvdbtimeout=" "${DEF_TVDBTIMEOUT}" )
    OPT_TVDBAPIKEY=$( optionvalue "tvdbapikey=" "${DEF_TVDBAPIKEY}" )
}

#-------------------------------------------------------------------------------
#Email notification functions using ssmpt
#
function donotify()
{
    if [ -n "${OPT_EMAIL}" ]; then
        echo -e "$1" | ssmtp "$OPT_EMAIL"
    fi
}

function startnotify ()
{
  MAILTEXTSTART="Subject:${PROGNOEXT} Start\n\n${PROGNOEXT} started processing ${dbtitle} ${dbtitleep} ${dbstarttime} ${dbchanid}\n"
  if [ "$OPT_NOTIFY" == "startend" ] || [ "$OPT_NOTIFY" == "start" ]; then
    donotify "$MAILTEXTSTART" 
  fi
}

function quiterrorearly ()
{
  MAILTEXTERREARLY="Subject:${PROGNOEXT} Fail\n\n${PROGNOEXT} error processing ${ORIGFILE}\n"
  if [ "$OPT_NOTIFY" == "startend" ] || [ "$OPT_NOTIFY" == "end" ] || [ "$OPT_NOTIFY" == "error" ]; then
    donotify "$MAILTEXTERREARLY" 
  fi
  exit 1
}

function quiterror ()
{
  MAILTEXTERR="Subject:${PROGNOEXT} Fail\n\n${PROGNOEXT} error processing ${dbtitle} ${dbtitleep} ${dbstarttime} ${dbchanid}\n"
  if [ "$OPT_NOTIFY" == "startend" ] || [ "$OPT_NOTIFY" == "end" ] || [ "$OPT_NOTIFY" == "error" ]; then
    donotify "$MAILTEXTERR"
  fi
  exit 1
}

function quitsuccess ()
{
  MAILTEXT="Subject:${PROGNOEXT} Success\n\n${PROGNOEXT} successfully processed ${dbtitle} ${dbtitleep} ${dbstarttime} ${dbchanid}\n"
  if [ "$OPT_NOTIFY" == "startend" ] || [ "$OPT_NOTIFY" == "end" ]; then
    donotify "$MAILTEXT"
  fi
  exit 0
}

#-------------------------------------------------------------------------------
#Check command line usage
#
function checkusage ()
{
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
        echo "epdatefirst="
        echo "tvdblookup="
        echo "precmd"
        echo "postcmd="
        echo ""
        echo "$PROG: file doesn't exist, aborting."
        quiterrorearly
    fi
}

#-------------------------------------------------------------------------------
# Init some variables, open the logfile
# run before values pulled from db
#
function init ()
{
    #-------------------------------------------------------------------------------
    #split directory and filename
    #
    RECDIR=`dirname $ORIGFILE`
    BASENAME=`basename $ORIGFILE`
    BASENOEXT=${BASENAME%.*}
    ARCHIVEDIR="$RECDIR/archive"
    
    #
    #one log file for each recording
    #
    logfile="${OPT_LOGDIR}/${BASENAME}.log"
    >${logfile}
    
    #start log file with date header
    echo "$PROG: Starting `date`" >>${logfile}
    

    # make sure we have a sane environment
    if [ -z "`which ffmpeg`" ]; then
        echo "$PROG: FFMpeg not present in the path. Adjust environment or install ffmpeg" >>${logfile}
        quiterrorearly
    fi
    
}

#-------------------------------------------------------------------------------
# Notify start do precmd
# run after values pulled from db
#

function initp2 ()
{

    #
    #Send start notification if requested
    startnotify

    #
    # Execute precmd if specified
    # Note, this could be dangerous depending on script context
    # We should be running as user mythtv with limited permissions
    if [ -n "${OPT_PRECMD}" ]; then
        EVALSTR=`echo ${OPT_PRECMD} | sed 's/%{/${/g'`
        eval ${EVALSTR}
    fi
}

#-------------------------------------------------------------------------------
# get required info from mythconverg db
#
function querydb ()
{
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
    dbtitleep=`echo "select subtitle from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
    
    echo "chanid: ${dbchanid}   dbstarttime: ${dbstarttime}"  >>${logfile}
    echo "dbtitle: ${dbtitle}   dbtitleep: ${dbtitleep}"  >>${logfile}
    
    
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
    
}

    
#-------------------------------------------------------------------------------
# Transcode or remux the video file possibly removing commercials
#
function transcodecut ()
{
    #tmp clip directory
    if [ -z "`ls "${OPT_TMPDIR}"/clips 2>/dev/null`" ]; then
        mkdir -p "${OPT_TMPDIR}"/clips
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
    echo "$PROG: ffmpeg -i ${RECDIR}/${BASENAME} -acodec ${OPT_ACODEC} ${OPT_ACODECARGS} -vcodec ${OPT_VCODEC} ${OPT_VCODECARGS} -f matroska -ss STARTFRAME -t DURATION ${OPT_TMPDIR}/clips/${BASENOEXT}_clip#.mkv" >>${logfile}
    
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
        ffmpeg -i ${RECDIR}/${BASENAME} -acodec ${OPT_ACODEC} ${OPT_ACODECARGS} -vcodec ${OPT_VCODEC} ${OPT_VCODECARGS} -f matroska -ss $start -t $duration ${OPT_TMPDIR}/clips/${BASENOEXT}_${clipstr}.mkv &>>${logfile}
        elif [ -z "$end" ]; then
        clipcount=$((++clipcount))
            printf -v clipstr "%03d" ${clipcount}
            ffmpeg -i ${RECDIR}/${BASENAME} -acodec ${OPT_ACODEC} ${OPT_ACODECARGS} -vcodec ${OPT_VCODEC} ${OPT_VCODECARGS} -f matroska -ss ${start} ${OPT_TMPDIR}/clips/${BASENOEXT}_${clipstr}.mkv &>>${logfile}
        fi
    
    done
    
    echo "#start of list: ${OPT_TMPDIR}/clips/${BASENOEXT}_###" >"${OPT_TMPDIR}/clips/${BASENOEXT}.lst"
    for i in `ls ${OPT_TMPDIR}/clips/${BASENOEXT}_* | sort`
    do
        echo "file '$i'" >>"${OPT_TMPDIR}/clips/${BASENOEXT}.lst"
    done
    echo "#end of list" >>"${OPT_TMPDIR}/clips/${BASENOEXT}.lst"
    
    if [ -f ${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT} ]; then
        rm -f ${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT}
    fi
    
    ffmpeg -f concat -i "${OPT_TMPDIR}/clips/${BASENOEXT}.lst" -c copy ${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT} &>>${logfile}
    
    #cleanup OPT_TMPDIR/clips
    rm -f -r "${OPT_TMPDIR}/clips"
}

#-------------------------------------------------------------------------------
# If we are replacing or archiving the MythTV file.  We need to update the DB
#
function updatedb ()
{
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
    
    fi
}

#-------------------------------------------------------------------------------
# archive or delete the original file if not 'new'
#
function archivedelete ()
{
    # Archive original if requested
    if [ "${OPT_FILEOP}" == "replace" ]; then
        echo "$PROG: removing original file ${RECDIR}/${BASENAME}" >>${logfile}
        rm -f "${RECDIR}/${BASENAME}"
        ERROR=$?
        if [ $ERROR -ne 0 ]; then
                echo "$PROG: failed to remove ${RECDIR}/${BASENAME}" >>${logfile}
        fi
    elif [ "${OPT_FILEOP}" == "archive" ]; then
        if [ -z "`ls "${ARCHIVEDIR}"`" ]; then
            mkdir -p "${ARCHIVEDIR}"
        fi
        echo "$PROG: moving original file to ${ARCHIVEDIR}/${BASENAME}" >>${logfile}
        mv -f "${RECDIR}/${BASENAME}" "${ARCHIVEDIR}/${BASENAME}"
    fi
}

#-------------------------------------------------------------------------------
#Code from MythSExx
#Usage: lookupsenum "show name" "episode name"
#Output: set globals SEASONNUM EPISODENUM (00 if not found)
#Dependencies: curl, agrep
#
function lookupsenum ()
{
    local ARGSHOWNAME=$1
    local ARGEPISODENAME=$2
    
    echo "TheTVDB SEARCH INITIATED AT `date`">>${logfile} 
    
    #tmp working directory
    if [ -z "`ls "${OPT_TMPDIR}"/tvdb 2>/dev/null`" ]; then
        mkdir -p "${OPT_TMPDIR}"/tvdb
    fi

    #Set episode name, dir, extension, and showname from the input parameters.
    local ShowName=$ARGSHOWNAME
    local epn=`echo $ARGEPISODENAME|sed 's/;.*//'|tr -d [:punct:]`
    
    #Check for show translations relating to the show in question.
    #!!!Read these from our config file
    if [ -f $OPT_TMPDIR/showtranslations ]; then 
        local showtranslation=`grep "$ShowName = " "$OPT_TMPDIR/showtranslations"|replace "$ShowName = " ""|replace "$OPT_TMPDIR/showtranslations" ""`		 
        if [ "$showtranslation" != "$null" ];then 
            ShowName=$showtranslation
            echo "USER TRANSLATION: $ARGSHOWNAME = $ShowName">>${logfile}
        elif [ "$showtranslation" = "$null" ];then
            $showtranslation = "Inactive"
        fi
    fi
    
     
    #####SEARCH FOR SHOW NAME#####
    echo "SEARCHING: www.TheTvDb.com SHOW NAME: $ShowName EPISODE: $epn">>${logfile}
    #download series info for show, parse into temporary text db- sid.txt shn.txt
    local tvdbshowname=`echo $ShowName|replace " " "%20"`
    
    curl -s -m"$OPT_TVDBTIMEOUT" www.thetvdb.com/api/GetSeries.php?seriesname=$tvdbshowname>${OPT_TMPDIR}/tvdb/working.xml
    cat ${OPT_TMPDIR}/tvdb/working.xml | grep "<seriesid>"|replace "<seriesid>" ""|replace "</seriesid>" "">${OPT_TMPDIR}/tvdb/sid.txt
    cat ${OPT_TMPDIR}/tvdb/working.xml | grep "<SeriesName>"|replace "<SeriesName>" ""|replace "</SeriesName>" "">${OPT_TMPDIR}/tvdb/shn.txt
    
    #Use fuzzy logic to make the best match of the show name
    local serieslinenumber=`agrep -1 -n "${showname:0:29}" ${OPT_TMPDIR}/tvdb/shn.txt|sed 's/:.*//'|grep -m1 ^`
    
    #Get the seriesid based on the showname
    local seriesid=`sed -n $serieslinenumber'p' ${OPT_TMPDIR}/tvdb/sid.txt|grep -m1 ^`
    local NewShowName=`sed -n $serieslinenumber'p' ${OPT_TMPDIR}/tvdb/shn.txt|grep -m1 ^`
    
    #Create folder for database if it does not exist
    if [ ! -d "${OPT_TMPDIR}/tvdb/$NewShowName" ]; then
        mkdir ${OPT_TMPDIR}/tvdb/"$NewShowName"
        echo "creating home OPT_TMPDIR and log file">>${logfile}
    fi
    echo "SEARCH FOUND:""$NewShowName" "ID#:" $seriesid >>${logfile}
    
    #If series ID is obtained, then get show information.
    if [ "$seriesid" != "" ]; then
        
        #####GET SHOW INFORMATION#####
        #Strip XML tags
        seriesid=`echo $seriesid|tr -d "<seriesid>"|tr -d "</seriesid>"`
        
        #download series info for series id
        curl -s -m"${OPT_TVDBTIMEOUT}" "http://www.thetvdb.com/api/${OPT_TVDBAPIKEY}/series/$seriesid/all/en.xml">${OPT_TMPDIR}/tvdb"/$NewShowName/$NewShowName.xml"
        
        #create a folder/file "database" Strip XML tags.  Series, Exx and Sxx are separated into different files
        if [ -f "${OPT_TMPDIR}/tvdb/$NewShowName/$NewShowName.xml" ]; then 
            cat "${OPT_TMPDIR}/tvdb/$NewShowName/$NewShowName.xml" | grep "<EpisodeName>"|replace "  <EpisodeName>" ""|replace "</EpisodeName>" ""|tr -d [:punct:]>${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".Ename.txt
            cat ${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".xml | grep "<SeasonNumber>"|replace "<SeasonNumber>" ""|replace "</SeasonNumber>" ""|replace " " "">${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".S.txt
            cat ${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".xml | grep "<EpisodeNumber>"|replace "<EpisodeNumber>" ""|replace "</EpisodeNumber>" ""|replace " " "">${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".E.txt
        elif [ ! -f "${OPT_TMPDIR}/tvdb/$NewShowName/$NewShowName.xml" ]; then
            echo "***FAILURE: curl -s -m$OPT_TVDBTIMEOUT http://www.thetvdb.com/api/$OPT_TVDBAPIKEY/series/$seriesid/all/en.xml">>${logfile}
        fi
        
        #check if files were created and generate message
        if [ -f ${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".Ename.txt ]; then
            echo "LOCAL DATABASE UPDATED:${OPT_TMPDIR}/tvdb/$NewShowName">>${logfile}
        elif [ ! -f "${OPT_TMPDIR}/tvdb/$NewShowName/$NewShowName.Ename.txt" ]; then
            echo "*** PERMISSION ERROR ${OPT_TMPDIR}/tvdb/$NewShowName/">>${logfile}
        fi
        
        
        #####PROCESS SHOW INFORMATION#####
        #grep use fuzzy logic to find the closest show name from the locally created database and return absolute episode number
        local absolouteEpisodeNumber=`agrep -1 -n "${epn:0:29}" "${OPT_TMPDIR}/tvdb""/""$NewShowName""/""$NewShowName"".Ename.txt"|grep -m1 ^|sed 's/:.*//'`
        echo DEFINED ABSOLOUTE EPISODE NUMBER: $absolouteEpisodeNumber>>${logfile}
        
        #if line match is obtained, then gather Sxx and Exx
        if [ "$absolouteEpisodeNumber" !=  ""  ]; then
            epn=`sed -n $absolouteEpisodeNumber'p' ${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".Ename.txt|sed 's/;.*//'`
        
            #gather series and episode names from files created earlier.
            local exx=`sed -n $absolouteEpisodeNumber'p' ${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".E.txt`
            local sxx=`sed -n $absolouteEpisodeNumber'p' ${OPT_TMPDIR}/tvdb/"$NewShowName"/"$NewShowName".S.txt`
        
            # Single digit episode and show names are not allowed Ex and Sx replaced with Exx Sxx
            if [ "$exx" -lt 10 ]; then 
                exx=`echo 0$exx`
            elif [ "$exx" -gt 9 ]; then 
                exx=`echo $exx`
            fi
            if [ "$sxx" -lt 10 ]; then 
                sxx=`echo 0$sxx`
            elif [ "$sxx" -gt 9 ]; then 
                sxx=`echo $sxx`
            fi
        fi
        echo "EPISODE:$epn NUMBER:$absolouteEpisodeNumber $sxx$exx">>${logfile}
        #if series id is not obtained
    elif [ "$seriesid" == "" ]; then 
        echo "series was not found the tvdb may be down try renaming $ARGSHOWNAME">>${logfile}
    fi
    
    #cleanup OPT_TMPDIR/tvdb
    rm -f -r "${OPT_TMPDIR}/tvdb"

    #Set global season and episode number strings.  00 is used to indicate 'not found'
    if [ "$exx" = "" ]; then
            SEASONNUM="00"
            EPISODENUM="00"
    else
            SEASONNUM="$sxx"
            EPISODENUM="$exx"
    fi
}


#-------------------------------------------------------------------------------
# Function to look up TV season and episode information
# Used to help rename when we are keeping the original MythTV file
#
function tv_lookup ()
{
    #
    # Uses globals:  SHOWFIELD EPFIELD
    # Sets globals: SEASONNUM EPISODENUM
    # Uses config file: OPT_CFGFILE
    #
    #
    
    # Default values if lookup fails
    SEASONNUM="00"
    EPISODENUM="00"

    # nolookup=showtitle in config file
    # nolookup will prevent season/episode lookup for a show or globally if * wildcard is specified.
    local NOLOOKUPG 
    local NOLOOKUPL
    
    #Get global settings from command line or config
    if [ "${OPT_TVDBLOOKUP}" = "no" ]; then
        NOLOOKUPG="*"
    else
        NOLOOKUPG=$(cat "$OPT_CFGFILE" | grep "^nolookup=\*$") 
    fi
    #grep a config file to see if we should do a lookup for this show 
    NOLOOKUPL=$(cat "$OPT_CFGFILE" | grep "^nolookup=$SHOWFIELD$") 

    if [ -z "$NOLOOKUPL" ] && [ -z "$NOLOOKUPG" ]; then 
        #Get Season and Episode string
        #titlesub2se sets globals SEASONNUM and EPISODENUM
        lookupsenum "$SHOWFIELD" "$EPFIELD"
    fi 
}

#-------------------------------------------------------------------------------
# Build OUTNAME and OUTDIR according to nameformat and folderformat
#
function getnewname ()
{

    local EPDATEFIRSTG 
    local EPDATEFIRSTL 
    
    # Config file format episodedatefirst=showtitle 
    # episodedatefirst will prepend @RecDate to the episode name in order to force sorting by date if S00E00
    # The * wildcard can be used to force all 

    #Get global settings from command line or config
    if [ "${OPT_EPDATEFIRST}" = "yes" ]; then
        EPDATEFIRSTG="*"
    else
        EPDATEFIRSTG=$(cat "$OPT_CFGFILE" | grep "^episodedatefirst=\*$")
    fi
    EPDATEFIRSTL=$(cat "$OPT_CFGFILE" | grep "^episodedatefirst=$SHOWFIELD$") 

    #Add record date to episode in various ways 
    if [ -z "$EPDATEFIRSTG" ] && [ -z "$EPDATEFIRSTL" ]; then 
        #Blank episodes don't sort well in WMC so use @recorddate as apname 
        if [ -z "$EPFIELD" ]; then 
            epfrag="@$RECFIELD" 
        else 
            epfrag="$EPFIELD - [$RECFIELD]" 
        fi 
    else 
        #Add the record date to the front of the episode name so shows will 
        #sort alphabetically by date if season and episode don't look up 
        if [ -z "$EPFIELD" ]; then 
            epfrag="@$RECFIELD" 
        else 
            epfrag="@$RECFIELD $EPFIELD" 
        fi
    fi 

    #!!!create all the fields used to build directory and name
    #!!!TITLEFIELD,SEASONFIELD,EPFIELD,DATEFIELD,year2d,month2d,day2d

    #use sed to replace /t, /s, /e, and /d in OPT_FOLDERFORMAT
    dirfrag="${OPT_FOLDERFORMAT}"
    dirfrag=`echo ${dirfrag} | sed 's:/t:/${TITLEFIELD}:g'`
    dirfrag=`echo ${dirfrag} | sed 's:/s:/${SEASONFIELD}:g'`
    dirfrag=`echo ${dirfrag} | sed 's:/e:/${EPFIELD}:g'`
    dirfrag=`echo ${dirfrag} | sed 's:/d:/${DATEFIELD}:g'`
    OUTDIR=${OPT_NEWDIR}/${dirfrag}
    
    #between title and se
    sep1frag=" - "
    #between se and episode
    sep2frag=" - "

    titlefrag="${SHOWFIELD}"
    
    case $OPT_NAMEFORMAT in
        s00e00)
            sefrag="s00e00"
            ;;
        s00e##)
            #!!!build name and check loop until $OUTDIR/${titlefrag}${sep1frag}${sefrag}${sep2frag}${epfrag} doesn't exist
            ;;
        syyemmdd)
            sefrag="s${year2d}e${month2d}{day2d})"
            ;;
        yyyy-mm-dd)
            sefrag=${DATEFIELD}
            ;;
        *)
            # default to s##e## from lookup
            sefrag="s${SEASONNUM}e${EPISODENUM}"
            ;;
    esac


    #Build output name from fragments
    OUTNAME="${titlefrag}${sep1frag}${sefrag}${sep2frag}${epfrag}"
}

#-------------------------------------------------------------------------------
# If we are keeping the original MythTV file, we want to rename the 
# file based on the nameformat and folderformat, then move the file to a new directory
# A MythTV user job handles this by calling like:
# mythmunge.sh "%DIR%/%FILE%" "fileop=new,newdir=/mnt/VidTV/DVR"
#
function namemovenew ()
{
    if [ "$OPT_FILEOP" == "new" ]; then
         #Replace all bad filename characters
         SHOWFIELD=$(echo ${dbtitle} | sed -e "s:[/?<>\\:*|\"\^]:_:g") 
         EPFIELD=$(echo ${dbtitleep} | sed -e "s:[/?<>\\:*|\"\^]:_:g") 
         RECFIELD=$(echo ${dbstarttime} | sed -e "s:[/?<>\\:*|\"\^]:_:g") 

        #Move new file to new directory rather than replacing Myth file and DB
        echo "$PROG: fileop is 'new', keeping original file" >>${logfile}

        #Set SEASONNUM and EPISODENUM
        tv_lookup

        #Set OUTNAME and OUTDIR
        getnewname

        #Move the new file to its final location
        echo "$PROG: moving new file to $OUTDIR/$OUTNAME.${OPT_FILEFORMAT}" >>${logfile}
        if [ -z "`ls "${OUTDIR}" 2>/dev/null`" ]; then
            mkdir -p "${OUTDIR}"
        fi
        NEWFILE="$OUTDIR/$OUTNAME.${OPT_FILEFORMAT}"
        mv -f "${RECDIR}/${BASENOEXT}.${OPT_FILEFORMAT}" "${NEWFILE}"
    fi
}


#-------------------------------------------------------------------------------
# Close out log and prepare for quitting
#
function cleanup ()
{
    # Execute postcmd if specified
    # Note, this could be dangerous depending on script context
    # We should be running as user mythtv with limited permissions
    # !!!Should this be sed 's/%{/${_/g' to limit access to certain vars??
    if [ -n "${OPT_POSTCMD}" ]; then
        EVALSTR=`echo ${OPT_POSTCMD} | sed 's/%{/${/g'`
        eval ${EVALSTR}
    fi
    
    #-------------------------------------------------------------------------------
    echo "$PROG: Completed successfully `date`" >>${logfile}
}

#
#This construct lets us have a main function that can forward reference other functions
main "$@"

