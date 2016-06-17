# mythmunge
MythTV user job bash script to remove commercials / transcode / copy / etc. recordings  
  
Jerry Fath jerryfath@gmail.com  
Based on an original script by: Ian Thiele icthiele@gmail.com  

 **Installation:**  
    Edit defaults in DefaultsEditBlock as appropriate for your system  
    Create config file if needed  
    Add as a user job in MythTV  
 **Requires:**  
    mythcommflag, ffmpeg (greater than v1.1), ssmtp(optional)  
  
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
  
  
 Options can be set in mythmunch.sh, config file, or passed on command line  
 Precedence: command line, config file, default  
 
 Example MythTV user job to remove commercials and place new recording in DVR directory:  
   mythmunge.sh "%DIR%/%FILE%" "fileop=new,remcom=yes,newdir=/mnt/VidTV/DVR"  
  
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
 The user may elect to create a file in the TitleSub2SE/ working folder which will then translate any recorded
 show name into the desired show name.  This is useful for adding a year to distinguish between a new series
 and an older series and/or typos in your guide data.  By default it should be called "showtranslations" and
 by default it will be in your home/username/titlesub2se folder.  showtranslations is not needed by most users
 and the file should only be created if it is needed. Under most circumstances, the integrated fuzzy logic 
 will be sufficient to translate the guide name to the TvDb name, however showtranslations is available to 
 improve accuracy to 100%. The format of showtranslations is as follows:

#############################################################
My Guide Show Title = www.TheTvDb.com Show Title            #
Battlestar Gallactica = Battlestar Gallactica (2003)        # 
Millionaire = Who Wants To Be A Millionaire                 #
Aqua teen Hungerforce = Aqua Teen Hunger Force              #
#############################################################
  
#Release notes  
  
Modified 2012/6/27 jfath  
 Additional code used to archive original recording, or produce new file in proper Title - SxxExx format stored in a user  
 specified directory  
  
 Modified 2014/7/6 jfath  
 Added email notification using ssmtp  
  
 Modified 2016/6/8 jfath  
 Changed to optionstr arguement format to allow additional command  
 line options  

