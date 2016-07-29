application backupmon

access control rules{
  rule page root(){
    true
  }
  rule template monitor(){
    principal() != null
  }
  rule page init(){
    true
  }
  rule page signin(){
  	true
  }
  rule page fileLog( f : BackupFile ){
  	principal() != null
  }
}

section pages

page root(){
  h1{ "Monitor page" }
  
  monitor()
  if(principal() == null){
    navigate signin(){ "Log in" }
  } else { submitlink action{ securityContext.principal := null; }{ "Log out" } }
}

page fileLog(f : BackupFile){
	navigate root(){ "Go Back" }
	h1{ "Log for file " code{ output(f.key) } }
	table{
		theader{ row{
			th{ "Time stamp" }
			th{ "Name" }
			th{ "Size" }
			th{ "Diff" }
			th{ "Message" }
		}}
		for(log in f.log order by log.created desc){
			row{
				column{ output( log.created ) }
				logColumns(log)
			}
		}
	} 
}

section templates

htmlwrapper{
  theader thead
  th th
  small small
}

template monitor(){
  var newLoc := BackupLocation{}
  action delete(loc : BackupLocation){
  	loc.ownFile := null;
    for(f in loc.files){
      for(l in f.log){
      	l.previous := null;
        l.delete();
      }
      
      f.delete();
    }
    loc.delete();
  }
  
  for(loc : BackupLocation){
    fieldset("Monitored Location: " + loc.path){  
    	small{ submitlink action{ loc.updateLog(); }{"Scan Now"} } br
    
	    table{
	      theader{ row{
	        th{ "File" } th{ "Current Size" } th{ "Diff" } th{ "Message" } th{ "Detailed Log" }
	      } }
	      for(f in loc.files order by f.latestSize desc){
	        row{ logColumns( f.latest ) column{ navigate fileLog(f){ output(f.numMsgs) " message" if(f.numMsgs > 1){"s"} } } }
	      }
	    }
	    h5{ "Edit Settings" }
	    small{ submitlink delete(loc){ "delete location monitor" } }
	    edit(loc)
	}
  }
  
  h4{ "Add New Backup Location" }
  edit(newLoc)
}
template edit(loc : BackupLocation){
  form{
  	"Note: Only the files within the directory will be checked, no subdirectories"
    inputset("Path to Check"){ input(loc.path) }
    inputset("Notification email"){ input(loc.notifyEmail) }
    inputset("Max % decrease of filesize"){ input(loc.allowedFileSizeChangePerc) }
    inputset("Max free space decrease in bytes"){ input(loc.freeSpaceMaxDecr) }
    inputset("Min free space in bytes"){ input(loc.freeSpaceMinB) }
    inputset(""){ submit save(){ "Save" }}
  }
  
  action save(){
  	if(loc.version < 1){
    	loc.save();
    }
  }
}

template inputset(label : String){
	div{ span[class="inputlabel"]{ output(label) } elements }
}
template logColumns( log : FileLog){
  // var log := f.latest
  var islocationlog := log.file.location.ownFile == log.file
  var diffLast := if(log!=null && log.previous != null) log.byteSize-log.previous.byteSize else 0
  if(log != null){
      column{ if(islocationlog){ "Free Disk Space" } else { pre{ output(log.file.name) } } }
      column{ output( log.hsize) if(islocationlog){ " left" } }
      column{
      	if(log.previous != null){
      		success(diffLast > -1){
	      		if(diffLast > 0){ "+" }
	      		output( humanReadableSize(diffLast) ) 
	      	}
      	}
      }
      column{ output(log.message)   }
  }
}


template success(success : Bool){
	var cl := if(success) "success" else "fail"
	span[class=cl, all attributes]{ elements }
}

define email fileNotification(l : FileLog){
    to(l.file.location.notifyEmail)
    from("webdsl.org")
    subject("Something seems wrong with " + l.file.location.path + " / " + l.file.name)
    par{ "A warning was given for the file " output(l.file.name) ":" }
    par{ output(l.message) }
    par{ "Please have a look at the " navigate root(){ "monitor page"} "."}
}

section data

entity BackupLocation{
  path : Text
  files : {BackupFile}
  notifyEmail : Email
  freeSpaceMinB : Long (default=20L*1024L*1024L*1024L)
  freeSpaceMaxDecr : Long (default=1L*1024L*1024L*1024L)
  allowedFileSizeChangePerc : Int (default=1)
  ownFile : BackupFile
  
  function updateLog(){
  	log("Update log for location : " + path);
    for(file in FileUtils.files(path)){
      var backupFile := getUniqueBackupFile(path + file.getName());
      if(backupFile.location == null){
      	if(ownFile == null && file.isDirectory()){
      		ownFile := backupFile;
      	}
        backupFile.location := this;
        backupFile.filename := file.getName();
      }
      if(file.isDirectory()){
      	backupFile.updateFreeSpace(file);
      } else {
      	backupFile.updateLog(file);
      }
    }
  }
}

entity BackupFile{
  location : BackupLocation (inverse=files)
  key : Text (id)
  filename : Text (name)
  log : {FileLog}
  latest : FileLog
  numMsgs: Int
  latestSize : Long := if(latest != null) latest.byteSize else 0L
  
  function updateLog(file : JavaFile){
  	var fl := FileLog{
        byteSize := file.length()
        file := this
    };
    if(latest != null){
      fl.previous := latest;
      var sizeDiff := fl.byteSize - latest.byteSize;
      if(100 * sizeDiff / latest.byteSize < (-1*location.allowedFileSizeChangePerc) ){
        fl.message := "File size decreased more than " + location.allowedFileSizeChangePerc + "%" + sinceStr();
      } else{
        if(100 * sizeDiff / latest.byteSize > (location.allowedFileSizeChangePerc) ){
          fl.message := "File size grew more than " + location.allowedFileSizeChangePerc + "%" + sinceStr();
        }
      }
      
    }
    latest := fl;    
  }
  
  function updateFreeSpace(file : JavaFile){
  	var fl := FileLog{
        byteSize := file.getUsableSpace()
        file := this
    };
    if(latest != null){
      fl.previous := latest;
      var sizeDiff := fl.byteSize - latest.byteSize;
      if(fl.byteSize < location.freeSpaceMinB){
        fl.message := "Free space for " + location.path + " below " + humanReadableSize(location.freeSpaceMinB);
      } else{
        if(sizeDiff < -1*location.freeSpaceMaxDecr){
          fl.message := "Free space for " + location.path + " decreased with " + humanReadableSize(sizeDiff) + sinceStr();
        }
      }
      
    }
    latest := fl; 
  }
  function sinceStr() : String{
  	return " since last check (" + latest.created + ")";
  }
}

entity FileLog{
  file     : BackupFile (inverse=log)
  message  : String
  byteSize : Long
  hsize    : String := humanReadableSize(byteSize)
  previous : FileLog
  
  extend function setMessage(msg : String){
  	if(msg != ""){
  		if(file.numMsgs == null){ file.numMsgs := 0; }
  		file.numMsgs := file.numMsgs + 1;
  		
  		if(file.location != null && file.location.notifyEmail.trim() != ""){
  			email fileNotification(this);
  		}
  	}
  }
}

function humanReadableSize(byteSize : Long) : String{
  var abs := if(byteSize < 0) byteSize*-1 else byteSize;
  var sign := if(byteSize < 0) "-" else "";
  if(abs >= 1024){
  	var k := abs/1024;
    if(k >= 1024){
      var m := k/1024;
      if(m >= 1024){
      	var g := m/1024;
      	return sign + g + "." + (m-g*1024)*100 / 1024  + "G";
      }
      return sign + m + "." + (k-m*1024)*100 / 1024  + "M";
    } else{
      return sign + k + "K";
    }
  } else{
    return byteSize + " bytes";
  }
}

invoke updateLog() every 24 hours

function updateLog(){
  for(l : BackupLocation){
    l.updateLog();
  }
}

native class org.webdsl.backupmon.FileUtils as FileUtils{
  static files(String) : List<JavaFile>
}
native class java.io.File as JavaFile{
  getName() : String
  length() : Long
  isDirectory() : Bool
  getUsableSpace() : Long
}

section ac

entity User{
  name : String
  pass : Secret
}
principal is User with credentials name, pass

function principal() : User{
  return securityContext.principal;
}

page signin(){
  init{
    if( ( from User ).length < 1 ) { return init(); }
  }
  authentication()
}

page init(){
  var name : String := "admin"
  var pass : Secret
  if( ( from User ).length > 0 ){
    output( "The one and only user already exists, your bank account will now be plundered" )
  } else{
    form{
      
      label( "Username:" ) { input( name ) }
      label( "Password:" ) { input( pass ) }
      
      submit save() { "save" }
    }
  }
  action save(){
    User{
      name := name
      pass := pass.digest()
    } .save();
    return root();
  }
}