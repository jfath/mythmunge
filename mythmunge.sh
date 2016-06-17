#!/bin/bash
#===============================================================================
# mythmunge.sh
# Uses mythcommflag and ffmpeg to manipulate MythTV recordings
# !Note: Edit defaults in DEFAULTSEDITBLOCK below as appropriate for your system!
# Dependencies: mythcommflag, mythutil, ffmpeg (>= v1.1), ssmtp(optional), curl, agrep
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
# !!!Check problem with last segment when removing commercials
#===============================================================================

#
# get command line args for later use and use in defaults
prog=$(basename $0)
prognoext=$(basename $0 .sh)
origfile="$1"
optionstr="$2"

#
#== DEFAULTSEDITBLOCK (edit these values as appropriate for your system) =======
def_cfgfile="${HOME}/${prognoext}/${prognoext}.cfg"
def_fileop="new"
def_newdir="${HOME}/${prognoext}/DVR"
def_remcom="no"
def_filetype="mkv"
def_notify="none"
def_vcodec="copy"
def_vcodecargs=""
def_acodec="copy"
def_acodecargs=""
def_email="user@emailserver.com"
def_tmpdir="${HOME}/${prognoext}/tmp"
def_logdir="${HOME}/${prognoext}/log"
def_dbpasswd="mythtv"
def_tvdblookup="yes"
def_nameformat="%T - s%se%e - %E [%Y-%m-%d %h]"
def_folderformat="/%T/season %s"
def_precmd=""
def_postcmd=""
def_tvdbtimeout="50"
def_tvdbapikey="6DF511BB2A64E0E9"
#== DEFAULTSEDITBLOCK===========================================================

# we put a little code above for ease of editing defaults
# from here on, all code is wrapped in functions and the last line of the
# file calls our main function.  this construct allows us to forward reference
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
# option parsing helper function
# usage: var=$( optionvalue "option_search_string" "default_value" )
# uses globals optionstr, cfgoptionstr
#
function optionvalue()
{
    opt_this="${2}"
    if [ -n "`echo "${optionstr}" | grep ${1}`" ]; then
        opt_this="`echo "${optionstr}" | sed -r "s/.*${1}([^,]*).*/\1/"`"
    else
        if [ -n "`echo "${cfgoptionstr}" | grep ${1}`" ]; then
            opt_this="`echo "${cfgoptionstr}" | sed -r "s/.*${1}([^,]*).*/\1/"`"
        fi
    fi
    echo "${opt_this}"
}

#-------------------------------------------------------------------------------
# parse options from optionstr and/or config file
# precedence: command line, config file, default
#
function parseoptions ()
{
    cfgoptionstr=""
    opt_cfgfile=$( optionvalue "cfgfile=" "${def_cfgfile}" )
    #look for options in config file too
    cfgoptionstr="`grep '^options=' "${opt_cfgfile}"`"
    
    opt_fileop=$( optionvalue "fileop=" "${def_fileop}" )
    opt_newdir=$( optionvalue "newdir=" "${def_newdir}" )
    opt_remcom=$( optionvalue "remcom=" "${def_remcom}" )
    opt_filetype=$( optionvalue "filetype=" "${def_filetype}" )
    opt_acodec=$( optionvalue "acodec=" "${def_acodec}" )
    opt_acodecargs=$( optionvalue "acodecargs=" "${def_acodecargs}" )
    opt_vcodec=$( optionvalue "vcodec=" "${def_vcodec}" )
    opt_vcodecargs=$( optionvalue "vcodecargs=" "${def_vcodecargs}" )
    opt_notify=$( optionvalue "notify=" "${def_notify}" )
    opt_email=$( optionvalue "email=" "${def_email}" )
    opt_tmpdir=$( optionvalue "tmpdir=" "${def_tmpdir}" )
    opt_logdir=$( optionvalue "logdir=" "${def_logdir}" )
    opt_dbpasswd=$( optionvalue "dbpasswd=" "${def_dbpasswd}" )
    opt_tvdblookup=$( optionvalue "tvdblookup=" "${def_tvdblookup}" )
    opt_nameformat=$( optionvalue "nameformat=" "${def_nameformat}" )
    opt_folderformat=$( optionvalue "folderformat=" "${def_folderformat}" )
    opt_precmd=$( optionvalue "precmd=" "${def_precmd}" )
    opt_postcmd=$( optionvalue "postcmd=" "${def_postcmd}" )
    opt_tvdbtimeout=$( optionvalue "tvdbtimeout=" "${def_tvdbtimeout}" )
    opt_tvdbapikey=$( optionvalue "tvdbapikey=" "${def_tvdbapikey}" )
}

#-------------------------------------------------------------------------------
#email notification functions using ssmpt
#
function donotify()
{
    if [ -n "${opt_email}" ]; then
        echo -e "$1" | ssmtp "$opt_email"
    fi
}

function startnotify ()
{
  mailtextstart="Subject:${prognoext} start\n\n${prognoext} started processing ${dbtitle} ${dbtitleep} ${dbstarttime} ${dbchanid}\n"
  if [ "$opt_notify" == "startend" ] || [ "$opt_notify" == "start" ]; then
    donotify "$mailtextstart" 
  fi
}

function quiterrorearly ()
{
  mailtexterrearly="Subject:${prognoext} fail\n\n${prognoext} error processing ${origfile}\n"
  if [ "$opt_notify" == "startend" ] || [ "$opt_notify" == "end" ] || [ "$opt_notify" == "error" ]; then
    donotify "$mailtexterrearly" 
  fi
  exit 1
}

function quiterror ()
{
  mailtexterr="Subject:${prognoext} fail\n\n${prognoext} error processing ${dbtitle} ${dbtitleep} ${dbstarttime} ${dbchanid}\n"
  if [ "$opt_notify" == "startend" ] || [ "$opt_notify" == "end" ] || [ "$opt_notify" == "error" ]; then
    donotify "$mailtexterr"
  fi
  exit 1
}

function quitsuccess ()
{
  if [ "${opt_fileop}" == "new" ]; then
    mailtext="Subject:${prognoext} success\n\n${prognoext} successfully processed ${origfile} to ${newfile}\n"
  else
    mailtext="Subject:${prognoext} success\n\n${prognoext} successfully processed ${dbtitle} ${dbtitleep} ${dbstarttime} ${dbchanid}\n"
  fi
  if [ "$opt_notify" == "startend" ] || [ "$opt_notify" == "end" ]; then
    donotify "$mailtext"
  fi
  exit 0
}

#-------------------------------------------------------------------------------
#check command line usage
#
function checkusage ()
{
    if [ ! -f "$origfile" ]; then
        echo "usage: $prog /recpath/recfile" [optionstr]
        echo "optionstr is a comma delimited list of options"
        echo "fileop=[archive|replace|new]"
        echo "newdir=/myvids/dir"
        echo "remcom=[yes|no]"
        echo "filetype=[mkv|mp4|...]"
        echo "vcodec=[copy|ffmpeg codec]"
        echo "vcodecargs=ffmpeg_vcodec_parameters"
        echo "acodec=[copy|ffmpeg codec]"
        echo "acodecargs=ffmpeg_vcodec_parameters"
        echo "notify=[none|start|end|startend|error]"
        echo "email=user@mailserver.com"
        echo "cfgfile=/path/to/file.cfg"
        echo "tmpdir=/path/to/tempdir"
        echo "logdir=/path/to/logdir"
        echo "dbpasswd=mythtv_user_password"
        echo "tvdblookup=[yes|no]"
        echo "nameformat=%T - s%se%e - %E [%Y-%m-%d %h]"
        echo "folderformat=/%T/season %s"
        echo "precmd=bash_command_string"
        echo "postcmd=bash_command_string"
        echo ""
        echo "$prog: file doesn't exist, aborting."
        quiterrorearly
    fi
}

#-------------------------------------------------------------------------------
# init some variables, open the logfile
# run before values pulled from db
#
function init ()
{
    #-------------------------------------------------------------------------------
    #split directory and filename
    #
    recdir=`dirname $origfile`
    basename=`basename $origfile`
    basenoext=${basename%.*}
    archivedir="$recdir/archive"
    
    #
    #one log file for each recording
    #
    logfile="${opt_logdir}/${basename}.log"
    >${logfile}
    
    #start log file with date header
    echo "$prog: starting `date`" >>${logfile}
    

    # make sure we have a sane environment
    if [ -z "`which ffmpeg`" ]; then
        echo "$prog: ffmpeg not present in the path. adjust environment or install ffmpeg" >>${logfile}
        quiterrorearly
    fi
    
}

#-------------------------------------------------------------------------------
# notify start do precmd
# run after values pulled from db
#

function initp2 ()
{

    #
    #send start notification if requested
    startnotify

    #
    # execute precmd if specified
    # note, this could be dangerous depending on script context
    # we should be running as user mythtv with limited permissions
    if [ -n "${opt_precmd}" ]; then
        evalstr=`echo ${opt_precmd} | sed 's/%{/${/g'`
        eval ${evalstr}
    fi
}

#-------------------------------------------------------------------------------
# get required info from mythconverg db
#
function querydb ()
{
    dbhostname="localhost"
    dbusername="mythtv"
    dbpassword="$opt_dbpasswd"
    dbname="mythconverg"
    #connect to db
    mysqlconnect="mysql -N -h$dbhostname -u$dbusername -p$dbpassword $dbname"
    export mysqlconnect
    
    #determine chanid and starttime from recorded table
    dbchanid=`echo "select chanid from recorded where basename=\"$basename\";" | $mysqlconnect`
    dbstarttime=`echo "select starttime from recorded where basename=\"$basename\";" | $mysqlconnect`
    #get title and subtitle recorded table
    dbtitle=`echo "select title from recorded where basename=\"$basename\";" | $mysqlconnect`
    dbtitleep=`echo "select subtitle from recorded where basename=\"$basename\";" | $mysqlconnect`
    
    echo "chanid: ${dbchanid}   dbstarttime: ${dbstarttime}"  >>${logfile}
    echo "dbtitle: ${dbtitle}   dbtitleep: ${dbtitleep}"  >>${logfile}
    
    
    if [ -z "$dbchanid" ] || [ -z "$dbstarttime" ]
    then
        echo "$prog: recording not found in mythtv database, script aborted." >>${logfile}
        quiterrorearly
    fi
    
    #determine fps (frames per second) from db, which is used to determine the seek time to extract video clips
    fps=$(echo "scale=10;`echo "select data from recordedmarkup where chanid=$dbchanid and starttime='$dbstarttime' AND type=32" | $mysqlconnect` / 1000.0" | bc)
    
    if [ -z "$fps" ]
    then
        echo "$prog: frames per second value not found in mythtv database, script aborted." >>${logfile}
        quiterrorearly
    fi
    
}

    
#-------------------------------------------------------------------------------
# transcode or remux the video file possibly removing commercials
#
function transcodecut ()
{
    #tmp clip directory
    if [ -z "`ls "${opt_tmpdir}"/clips 2>/dev/null`" ]; then
        mkdir -p "${opt_tmpdir}"/clips
    fi
    
    
    #debug
    #uncomment to force commercial flagging
    #mythutil --chanid $dbchanid --starttime "$dbstarttime" --clearskiplist 
    
    cutlist="`mythutil --chanid $dbchanid --starttime "$dbstarttime" --getskiplist | grep "Commercial Skip List" | sed 's/Commercial Skip List: $//'`"
    
    if [ ${#cutlist} -le 1 ]; then
        echo "$prog: no skiplist found....generating new skiplist" >>${logfile}
        mythcommflag --chanid $dbchanid --starttime "$dbstarttime" 
        cutlist="`mythutil --chanid $dbchanid --starttime "$dbstarttime" --getskiplist | grep "Commercial Skip List" | sed 's/Commercial Skip List: $//'`"
    else
        echo "$prog: using existing skiplist" >>${logfile}
    fi
    
    echo "$prog: skiplist:$cutlist length:${#cutlist}" >>${logfile}
    
    
    #if opt_remcom is no make cutlist one entry that spans entire video
    #
    if [ "$opt_remcom" == "no" ]; then
        cutlist="0-2600000"
    else
        #cutlist provides a list of frames in the format start-end,[start1-end1,....] to cut 
        #we swap this list so that it provides the ranges of video we want in the format
        #  start-end start1:end1 ....
        cutlist=`mythutil --chanid $dbchanid --starttime "$dbstarttime" --getskiplist | grep "Commercial Skip List" | sed 's/Commercial Skip List: //' | \
        sed 's/-/ /g' | sed 's/^\|$/-/g' | sed 's/,/-/g'`
    fi
    
    #!!!always use matroska for clip containers or use specified file format??
    echo "$prog: ffmpeg -i ${recdir}/${basename} -acodec ${opt_acodec} ${opt_acodecargs} -vcodec ${opt_vcodec} ${opt_vcodecargs} -f matroska -ss startframe -t duration ${opt_tmpdir}/clips/${basenoext}_clip#.mkv" >>${logfile}
    
    clipcount=0
    for i in ${cutlist}
    do
        start=`echo $i | sed 's/ //g' | sed 's/^\(.*\)-.*$/\1/'`
        end=`echo $i | sed 's/ //g' | sed 's/^.*-\(.*\)$/\1/'`
    
        echo "$prog: clip:$clipcount  start:$start  end:$end" >>${logfile}
    
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
        ffmpeg -i ${recdir}/${basename} -acodec ${opt_acodec} ${opt_acodecargs} -vcodec ${opt_vcodec} ${opt_vcodecargs} -f matroska -ss $start -t $duration ${opt_tmpdir}/clips/${basenoext}_${clipstr}.mkv &>>${logfile}
        elif [ -z "$end" ]; then
        clipcount=$((++clipcount))
            printf -v clipstr "%03d" ${clipcount}
            ffmpeg -i ${recdir}/${basename} -acodec ${opt_acodec} ${opt_acodecargs} -vcodec ${opt_vcodec} ${opt_vcodecargs} -f matroska -ss ${start} ${opt_tmpdir}/clips/${basenoext}_${clipstr}.mkv &>>${logfile}
        fi
    
    done
    
    echo "#start of list: ${opt_tmpdir}/clips/${basenoext}_###" >"${opt_tmpdir}/clips/${basenoext}.lst"
    for i in `ls ${opt_tmpdir}/clips/${basenoext}_* | sort`
    do
        echo "file '$i'" >>"${opt_tmpdir}/clips/${basenoext}.lst"
    done
    echo "#end of list" >>"${opt_tmpdir}/clips/${basenoext}.lst"
    
    if [ -f ${recdir}/${basenoext}.${opt_filetype} ]; then
        rm -f ${recdir}/${basenoext}.${opt_filetype}
    fi
    
    ffmpeg -f concat -i "${opt_tmpdir}/clips/${basenoext}.lst" -c copy ${recdir}/${basenoext}.${opt_filetype} &>>${logfile}
    
    #cleanup opt_tmpdir/clips
    rm -f -r "${opt_tmpdir}/clips"
}

#-------------------------------------------------------------------------------
# if we are replacing or archiving the mythtv file.  we need to update the db
#
function updatedb ()
{
    if [ "$opt_fileop" != "new" ]; then
    
        #clear out the old cutlist
        mythutil --chanid $dbchanid --starttime "$dbstarttime" --clearcutlist &>>${logfile}
    
        #we'll need a new filesize to update the db with
        filesize=$(du ${recdir}/${basenoext}.${opt_filetype} | awk '{print $1}') 
    
        #update db with new filesize and filename
        cat <<EOF | $mysqlconnect
UPDATE
    recorded
SET
    cutlist = 0,
    filesize = ${filesize},
    basename = "${basenoext}.${opt_filetype}"
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
    # archive original if requested
    if [ "${opt_fileop}" == "replace" ]; then
        echo "$prog: removing original file ${recdir}/${basename}" >>${logfile}
        rm -f "${recdir}/${basename}"
        error=$?
        if [ $error -ne 0 ]; then
                echo "$prog: failed to remove ${recdir}/${basename}" >>${logfile}
        fi
    elif [ "${opt_fileop}" == "archive" ]; then
        if [ -z "`ls "${archivedir}"`" ]; then
            mkdir -p "${archivedir}"
        fi
        echo "$prog: moving original file to ${archivedir}/${basename}" >>${logfile}
        mv -f "${recdir}/${basename}" "${archivedir}/${basename}"
    fi
}

#-------------------------------------------------------------------------------
#code from mythsexx
#usage: lookupsenum "show name" "episode name"
#output: set globals seasonnum episodenum (00 if not found)
#dependencies: curl, agrep
#
function lookupsenum ()
{
    local argshowname=$1
    local argepisodename=$2
    
    echo "thetvdb search initiated at `date`">>${logfile} 
    
    #tmp working directory
    if [ -z "`ls "${opt_tmpdir}"/tvdb 2>/dev/null`" ]; then
        mkdir -p "${opt_tmpdir}"/tvdb
    fi

    #set episode name, dir, extension, and showname from the input parameters.
    local showname=$argshowname
    local epn=`echo $argepisodename|sed 's/;.*//'|tr -d [:punct:]`
    
    #check for show translations relating to the show in question.
    #!!!read these from our config file
    if [ -f $opt_tmpdir/showtranslations ]; then 
        local showtranslation=`grep "$showname = " "$opt_tmpdir/showtranslations"|replace "$showname = " ""|replace "$opt_tmpdir/showtranslations" ""`		 
        if [ "$showtranslation" != "$null" ];then 
            showname=$showtranslation
            echo "user translation: $argshowname = $showname">>${logfile}
        elif [ "$showtranslation" = "$null" ];then
            $showtranslation = "inactive"
        fi
    fi
    
     
    #####search for show name#####
    echo "searching: www.thetvdb.com show name: $showname episode: $epn">>${logfile}
    #download series info for show, parse into temporary text db- sid.txt shn.txt
    local tvdbshowname=`echo $showname|replace " " "%20"`
    
    curl -s -m"$opt_tvdbtimeout" www.thetvdb.com/api/GetSeries.php?seriesname=$tvdbshowname>${opt_tmpdir}/tvdb/working.xml
    cat ${opt_tmpdir}/tvdb/working.xml | grep "<seriesid>"|replace "<seriesid>" ""|replace "</seriesid>" "">${opt_tmpdir}/tvdb/sid.txt
    cat ${opt_tmpdir}/tvdb/working.xml | grep "<SeriesName>"|replace "<SeriesName>" ""|replace "</SeriesName>" "">${opt_tmpdir}/tvdb/shn.txt
    
    #use fuzzy logic to make the best match of the show name
    local serieslinenumber=`agrep -1 -n "${showname:0:29}" ${opt_tmpdir}/tvdb/shn.txt|sed 's/:.*//'|grep -m1 ^`
    
    #get the seriesid based on the showname
    local seriesid=`sed -n $serieslinenumber'p' ${opt_tmpdir}/tvdb/sid.txt|grep -m1 ^`
    local newshowname=`sed -n $serieslinenumber'p' ${opt_tmpdir}/tvdb/shn.txt|grep -m1 ^`
    
    #create folder for database if it does not exist
    if [ ! -d "${opt_tmpdir}/tvdb/$newshowname" ]; then
        mkdir ${opt_tmpdir}/tvdb/"$newshowname"
        echo "creating home opt_tmpdir and log file">>${logfile}
    fi
    echo "search found:""$newshowname" "id#:" $seriesid >>${logfile}
    
    #if series id is obtained, then get show information.
    if [ "$seriesid" != "" ]; then
        
        #####get show information#####
        #strip xml tags
        seriesid=`echo $seriesid|tr -d "<seriesid>"|tr -d "</seriesid>"`
        
        #download series info for series id
        curl -s -m"${opt_tvdbtimeout}" "http://www.thetvdb.com/api/${opt_tvdbapikey}/series/$seriesid/all/en.xml">${opt_tmpdir}/tvdb"/$newshowname/$newshowname.xml"
        
        #create a folder/file "database" strip xml tags.  series, exx and sxx are separated into different files
        if [ -f "${opt_tmpdir}/tvdb/$newshowname/$newshowname.xml" ]; then 
            cat "${opt_tmpdir}/tvdb/$newshowname/$newshowname.xml" | grep "<EpisodeName>"|replace "  <EpisodeName>" ""|replace "</EpisodeName>" ""|tr -d [:punct:]>${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".ename.txt
            cat ${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".xml | grep "<SeasonNumber>"|replace "<SeasonNumber>" ""|replace "</SeasonNumber>" ""|replace " " "">${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".s.txt
            cat ${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".xml | grep "<EpisodeNumber>"|replace "<EpisodeNumber>" ""|replace "</EpisodeNumber>" ""|replace " " "">${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".e.txt
        elif [ ! -f "${opt_tmpdir}/tvdb/$newshowname/$newshowname.xml" ]; then
            echo "***failure: curl -s -m$opt_tvdbtimeout http://www.thetvdb.com/api/$opt_tvdbapikey/series/$seriesid/all/en.xml">>${logfile}
        fi
        
        #check if files were created and generate message
        if [ -f ${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".ename.txt ]; then
            echo "local database updated:${opt_tmpdir}/tvdb/$newshowname">>${logfile}
        elif [ ! -f "${opt_tmpdir}/tvdb/$newshowname/$newshowname.ename.txt" ]; then
            echo "*** permission error ${opt_tmpdir}/tvdb/$newshowname/">>${logfile}
        fi
        
        
        #####process show information#####
        #grep use fuzzy logic to find the closest show name from the locally created database and return absolute episode number
        local absolouteepisodenumber=`agrep -1 -n "${epn:0:29}" "${opt_tmpdir}/tvdb""/""$newshowname""/""$newshowname"".ename.txt"|grep -m1 ^|sed 's/:.*//'`
        echo defined absoloute episode number: $absolouteepisodenumber>>${logfile}
        
        #if line match is obtained, then gather sxx and exx
        if [ "$absolouteepisodenumber" !=  ""  ]; then
            epn=`sed -n $absolouteepisodenumber'p' ${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".ename.txt|sed 's/;.*//'`
        
            #gather series and episode names from files created earlier.
            local exx=`sed -n $absolouteepisodenumber'p' ${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".e.txt`
            local sxx=`sed -n $absolouteepisodenumber'p' ${opt_tmpdir}/tvdb/"$newshowname"/"$newshowname".s.txt`
        
            # single digit episode and show names are not allowed ex and sx replaced with exx sxx
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
        echo "episode:$epn number:$absolouteepisodenumber $sxx$exx">>${logfile}
        #if series id is not obtained
    elif [ "$seriesid" == "" ]; then 
        echo "series was not found the tvdb may be down try renaming $argshowname">>${logfile}
    fi
    
    #cleanup opt_tmpdir/tvdb
    rm -f -r "${opt_tmpdir}/tvdb"

    #set global season and episode number strings.  00 is used to indicate 'not found'
    if [ "$exx" = "" ]; then
            seasonnum="00"
            episodenum="00"
    else
            seasonnum="$sxx"
            episodenum="$exx"
    fi
}


#-------------------------------------------------------------------------------
# function to look up tv season and episode information
# used to help rename when we are keeping the original mythtv file
#
function tv_lookup ()
{
    #
    # uses globals:  showfield epfield
    # sets globals: seasonnum episodenum
    # uses config file: opt_cfgfile
    #
    #
    
    # default values if lookup fails
    seasonnum="00"
    episodenum="00"

    # nolookup=showtitle in config file
    # nolookup will prevent season/episode lookup for a show or globally if * wildcard is specified.
    local nolookupg 
    local nolookupl
    
    #get global settings from command line or config
    if [ "${opt_tvdblookup}" = "no" ]; then
        nolookupg="*"
    else
        nolookupg=$(cat "$opt_cfgfile" | grep "^nolookup=\*$") 
    fi
    #grep a config file to see if we should do a lookup for this show 
    nolookupl=$(cat "$opt_cfgfile" | grep "^nolookup=$showfield$") 

    if [ -z "$nolookupl" ] && [ -z "$nolookupg" ]; then 
        #get season and episode string
        #titlesub2se sets globals seasonnum and episodenum
        lookupsenum "$showfield" "$epfield"
    fi 
}

#
#
function replacetemplate ()
{
    local newstr="${1}"

    #%T is show title  
    #%E is show episode text  
    #%s two digit season number from tvdb  
    #%e two digit episode number from tvdb  
    #%y two digit year  
    #%m two digit month  
    #%d two digit day  
    #%Y four digit year
    #%h hour_min_sec
    #%u unique episode number

    #parse recdatefield to get date related fields
    IFS='-' read -a datefields <<< "${recdatefield}"
    year4d="${datefields[0]}"
    year2d=${year4d:(-2)}
    month2d="${datefields[1]}"
    IFS=' ' read -a dayfields <<< "${datefields[2]}"
    day2d="${dayfields[0]}"
    rectime="${dayfields[1]}"

    #log name components
    echo "$prog formatstr: ${newstr}" >>${logfile}
    echo "$prog showinfo: ${showfield} ; ${epfield} ; ${seasonnum} ; ${episodenum}" >>${logfile}
    echo "$prog recdate: ${recdatefield}" >>${logfile}
    echo "$prog datefields: ${year4d} ; ${year2d} ; ${month2d} ; ${day2d} ; ${rectime}" >>${logfile}

    newstr=`echo "${newstr}" | sed "s/%T/${showfield}/g; s/%E/${epfield}/g; s/%s/${seasonnum}/g; s/%e/${episodenum}/g"`
    newstr=`echo "${newstr}" | sed "s/%y/${year2d}/g; s/%m/${month2d}/g; s/%d/${day2d}/g; s/%Y/${year4d}/g; s/%h/${rectime}/g"`
    echo "${newstr}"
 
    #log the replaced template   
    echo "$prog replacedstr: ${newstr}" >>${logfile}
}

#-------------------------------------------------------------------------------
# build outname and outdir according to nameformat and folderformat
#
function getnewname ()
{

    dirfrag=$( replacetemplate "${opt_folderformat}" )
    outdir="${opt_newdir}/${dirfrag}"

    namefrag=$( replacetemplate "${opt_nameformat}" )
    #if format contains %u, replace with unique episode number
    if [ -n "`echo "${namefrag}" | grep "%u"`" ]; then
        indx=1
        while [ $indx -lt 99 ]
        do
            #check for e## pattern in outdir
            chkstr="`printf "e%02d" ${indx}`"
            if [ -z "`ls "${outdir}" | grep -i ${chkstr}`" ]; then
                break
            fi
            ((indx++))
        done
        chkstr="`echo "${namefrag}" | sed 's/%u/%02d/'`"
        namefrag="`printf "${chkstr}" ${indx}`"
    fi

    outname="${namefrag}"
}

#-------------------------------------------------------------------------------
# if we are keeping the original mythtv file, we want to rename the 
# file based on the nameformat and folderformat, then move the file to a new directory
# a mythtv user job handles this by calling like:
# mythmunge.sh "%dir%/%file%" "fileop=new,newdir=/mnt/vidtv/dvr"
#
function namemovenew ()
{
    if [ "$opt_fileop" == "new" ]; then
         #replace all bad filename characters
         showfield=$(echo ${dbtitle} | sed -e "s:[/?<>\\:*|\"\^]:_:g") 
         epfield=$(echo ${dbtitleep} | sed -e "s:[/?<>\\:*|\"\^]:_:g") 
         recdatefield=$(echo ${dbstarttime} | sed -e "s:[/?<>\\:*|\"\^]:_:g") 

        #move new file to new directory rather than replacing myth file and db
        echo "$prog: fileop is 'new', keeping original file" >>${logfile}

        #set seasonnum and episodenum
        tv_lookup

        #set outname and outdir
        getnewname

        #move the new file to its final location
        echo "$prog: moving new file to $outdir/$outname.${opt_filetype}" >>${logfile}
        if [ -z "`ls "${outdir}" 2>/dev/null`" ]; then
            mkdir -p "${outdir}"
        fi
        newfile="$outdir/$outname.${opt_filetype}"
        mv -f "${recdir}/${basenoext}.${opt_filetype}" "${newfile}"
    fi
}


#-------------------------------------------------------------------------------
# close out log and prepare for quitting
#
function cleanup ()
{
    # execute postcmd if specified
    # note, this could be dangerous depending on script context
    # we should be running as user mythtv with limited permissions
    # !!!should this be sed 's/%{/${_/g' to limit access to certain vars??
    if [ -n "${opt_postcmd}" ]; then
        evalstr=`echo ${opt_postcmd} | sed 's/%{/${/g'`
        eval ${evalstr}
    fi
    
    #-------------------------------------------------------------------------------
    echo "$prog: completed successfully `date`" >>${logfile}
}

#
#this construct lets us have a main function that can forward reference other functions
main "$@"

