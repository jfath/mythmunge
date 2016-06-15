# mythmunge
MythTV user job bash script to remove commercials / transcode / copy / etc. recordings  
  
Jerry Fath jerryfath@gmail.com  
Based on an original script by: Ian Thiele icthiele@gmail.com  

 **Installation:**  
    Edit defaults in DefaultsEditBlock as appropriate for your system  
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
  
  nameformat=[s99e99|syyemmdd|yyyy-mm-dd]
   the naming format used for a new file  
  
  epdatefirst=[yes|no]
   specifies whether to pu the date at the front or end the episode title  
  
  precmd=bash command to execute before munge
   a string which will be executed in a bash shell before processing begins  
  
  postcmd=bash command to execute after munge
   a string which will be executed in a bash shell after processing begins  
   the new file can be referred to as %{NEWFILE} within the command string  
  
  
 Example MythTV user job to remove commercials and place new recording in DVR directory:  
   mythmunge.sh "%DIR%/%FILE%" "fileop=new,remcom=yes,newdir=/mnt/VidTV/DVR"  
  
 Example of OPTION used to transcode to x264 video with mp3 audio  
   acodec=libmp3lame,acodecargs=-ac 2 -ar 48000 -ab 128k,vcodec=libx264,vcodecargs=-preset ultrafast
   
 Example of OPTION used to log a message including the new file name as a postcmd
   "fileop=new,newdir=/my/vids,postcmd=echo \"finished %{NEWFILE}\" >/home/mongo/mythmunge/post.log"  
  
  
#Config file format  
  
nolookup=showtitle  
episodedatefirst=showtitle  
options=  
  
multiple lines of nolookup= and episodedatefirst= are allowed  
episodedatefirst=* and nolookup=* are also allowed to force all  
  
episodedatefirst=someshowname  
episodedatefirst=someothershowname  
  
nolookup=showtitlea  
nolookup=showtitleb  
nolookup=showtitlec  
  
options="fileop=new,newdir=\my\vids,remcom=no"  
  
  
#Release notes  
  
Modified 2012/6/27 jfath  
 Additional code used to archive original recording, or produce new file in proper Title - SxxExx format stored in a user  
 specified directory  
  
 Modified 2014/7/6 jfath  
 Added email notification using ssmtp  
  
 Modified 2016/6/8 jfath  
 Changed to optionstr arguement format to allow additional command  
 line options  

