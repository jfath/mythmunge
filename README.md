# mythmunge
MythTV user job bash script to remove commercials / transcode / copy / etc. recordings  
  
Jerry Fath jerryfath at gmail dot com  
Based on an original script by: Ian Thiele icthiele at gmail dot com
TheTVDB lookup code based on MythSExx by Adam Outler outleradam at hotmail dot com
  
 **Features**  
   Transcode or remux into any compression type or container supported by ffmpeg  
   Optionally remove commercials from a recording  
   Modify the MythTV recording, or produce a new file leaving the original recording unaltered  
   Look up recording season/episode numbers on TheTVDB  
   Copy a modified recording into any directory/file structure you choose  
     (ideal for moving recodings into Kodi or Plex media libraries)  
   Receive notification emails on job start/complete  
   Run pre and post commands for WOL, scp to remote machines, etc.  
   
 **Installation:**  
    Edit defaults in DefaultsEditBlock as appropriate for your system  
    Create config file if needed  
    Add as a user job in MythTV  
 **Requires:**  
    mythcommflag, ffmpeg (greater than v1.1), ssmtp(optional), curl, agrep  
  
 **Usage: mythmunge.sh /recpath/recfile [options]**  
   options is a string of comma delimited key=value pairs  
  
  fileop=[archive|replace|new]  
   archive = move original MythTV recording into an archives directory  
   replace = overwrite original with new commercial-less recording  
   new = don't alter the MythTV version, but write new recording to another directory  
  
  newdir=/directory/fornewfile
   target directory required when fileop is 'new'  
  
  remcom=[yes|no]
   remove or leave commercials
   
  filetype=[mkv|mp4|..]  
   file container type of output file  
  
  vcodec=[copy|ffmpeg vcodec]
   ffmpeg video codec name or copy to remux original 
  
  vcodecargs=ffmpg vcodec parameters
   video codec parameters to send to ffmpeg  
  
  acodec=[copy|ffmpeg acodec]
    ffmpeg audio codec name or copy to remux original  
  
  acodecargs=ffmpeg acodec parameters  
   audio codec parameters to send to ffmpeg  
  
  notify=[none|start|end|startend|error]  
   when to send job notification emails  
  
  email=user@mailserver.com  
   email address for notifications.  ssmpt must be installed and configured  
  
  cfgfile=/dir/filename.cfg  
   configuration file - see below for format  
  
  tmpdir=/dir/sometmpdir  
   working directory for temporary files  
  
  logdir=/dir/alogdir  
   log directory contains one log file for each video file processed  
  
  dbpasswd=mysql_user_mythtv_password  
   mysql or mariadb password for the mythtv user  
  
  tvdblookup=[yes|no]  
   specifies whether to attempt a tvdb lookup when naming a new file  
  
  nameformat=format string  
   %T is show title  
   %E is show episode text  
   %s two digit season number from tvdb  
   %e two digit episode number from tvdb  
   %y two digit year  
   %m two digit month  
   %d two digit date  
   %Y four digit year
   %h hour_min_sec
   %u unique episode number  
  
   the naming format used for a new file  
   %T - s%se%e - %E [%Y-%m-%d] will name show as Title - s##e## - EpisodeText [yyyy-mm-dd]  
   
  folderformat=format string  
   the folder structure used for a new file
   using the same template variables as nameformat  
   folderformat=/%T/Season %s would store a new file in the standard Title/Season ## structure  
  
  precmd=bash command to execute before munge  
   a string which will be executed in a bash shell before processing begins  
  
  postcmd=bash command to execute after munge  
   a string which will be executed in a bash shell after processing begins  
   the new file can be referred to as %{NEWFILE} within the command string  
  
**Notes**
  
 Options can be set in mythmunge.sh, config file, or passed on command line  
 Precedence: command line, config file, defaults from mythmunge  
 
 Example MythTV user job to remove commercials and place new recording in DVR directory:  
   mythmunge.sh "%DIR%/%FILE%" "fileop=new,remcom=yes,newdir=/mnt/myvids/DVR"  
  
 Example of OPTION used to transcode to x264 video with mp3 audio  
   acodec=libmp3lame,acodecargs=-ac 2 -ar 48000 -ab 128k,vcodec=libx264,vcodecargs=-preset ultrafast  
   
 Example of OPTION used to log a message including the new file name as a postcmd  
   "fileop=new,newdir=/my/vids,postcmd=echo \"finished %{NEWFILE}\" >/home/mongo/mythmunge/post.log"
   
 Example of OPTION used to add unique episode number to a new file than doesn't look up in TheTVDB
   "tvdblookup=no,nameformat=%T - s00e%u - %E"  
    
  
#Config file format  
  
nolookup=showtitle  
options=  
  
multiple lines of nolookup= are allowed and nolookup=* is also allowed to force no lookup for any show  
  
nolookup=showtitlea  
nolookup=showtitleb  
nolookup=showtitlec  
  
options="fileop=new,newdir=\my\vids,remcom=no"  
  
TheTVDB Show Name Translation  
  todo: re-implement within config file and document  
  
#Release notes  
  
Modified 2012/6/27 jfath  
 Additional code used to archive original recording, or produce new file in proper Title - SxxExx format stored in a user  
 specified directory  
  
 Modified 2014/7/6 jfath  
 Added email notification using ssmtp  
  
 Modified 2016/6/17 jfath  
 Changed to optionstr arguement format to allow additional command  
 line options  

