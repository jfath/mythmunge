# mythmunge
MythTV user job bash script to remove commercials / transcode / copy / etc. recordings  

Based on an original script by: Ian Thiele icthiele@gmail.com  

 **Installation:**  
    Edit defaults in DefaultsEditBlock as appropriate for your system  
    Add as a user job in MythTV  
 **Requires:**  
    mythcommflag, ffmpeg, mkvmerge, ssmtp(optional)  
  
 **Usage: mythmunge.sh /recpath/recfile [optionstr]**  
 optionstr is a comma delimited list of options  
   fileop=[archive|replace|new]  
   newdir=/directory/fornewfile  
   remcom=[yes|no]  
   vcodec=  
   vcodecargs=  
   acodec=  
   acodecargs=  
   notify=[none|start|end|startend|error]  
   email=  
   cfgfile=  
   tmpdir=  
   logdir=  
   dbpasswd=  
  
 fileop=  
   archive = move original MythTV recording into an archives directory  
   replace = overwrite original with new commercial-less recording  
   new = don't alter the MythTV version, but write new recording to another directory  
  
 notify=  
   none|start|end|startend|error when to send job notification emails  
  
 Example MythTV user job to remove commercials and place new recording in DVR directory:  
   mythmunge.sh "%DIR%/%FILE%" "fileop=new,remcom=yes,newdir=/mnt/VidTV/DVR"  
  
 Example of OPTIONSTR used to transcode to x264 video with mp3 audio  
   acodec=libmp3lame,acodecargs=-ac 2 -ar 48000 -ab 128k,vcodec=libx264,vcodecargs=-preset ultrafast  
  
  
#Release notes  
  
Modified 2012/6/27 jfath  
 Additional code used to archive original recording, or produce new file in proper Title - SxxExx format stored in a user  
 specified directory  
  
 Modified 2014/7/6 jfath  
 Added email notification using ssmtp  
  
 Modified 2016/6/8 jfath  
 Changed to optionstr arguement format to allow additional command  
 line options  

