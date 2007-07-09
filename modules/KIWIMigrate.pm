#================
# FILE          : KIWIMigrate.pm
#----------------
# PROJECT       : OpenSUSE Build-Service
# COPYRIGHT     : (c) 2006 SUSE LINUX Products GmbH, Germany
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>
#               :
# BELONGS TO    : Operating System images
#               :
# DESCRIPTION   : This module is used to provide methods for
#               : migrating a running system into an image
#               : description
#               : 
#               : 
#               :
# STATUS        : Development
#----------------
package KIWIMigrate;
#==========================================
# Modules
#------------------------------------------
use strict;
use File::Find;
use KIWILog;

#==========================================
# Constructor
#------------------------------------------
sub new {
	# ...
	# Create a new KIWIMigrate object which is used to gather
	# information on the running system 
	# ---
	#==========================================
	# Object setup
	#------------------------------------------
	my $this  = {};
	my $class = shift;
	bless $this,$class;
	#==========================================
	# Module Parameters
	#------------------------------------------
	my $kiwi = shift;
	my $dest = shift;
	my $name = shift;
	my $excl = shift;
	my $demo = shift;
	#==========================================
	# Constructor setup
	#------------------------------------------
	if (! defined $kiwi) {
		$kiwi = new KIWILog();
	}
	if (! defined $name) {
		$kiwi -> failed ();
		$kiwi -> error  ("No image name for migration given");
		$kiwi -> failed ();
		return undef;
	}
	my $code;
	if (! defined $dest) {
		$dest = qx ( mktemp -q -d /tmp/kiwi-migrate.XXXXXX );
		$code = $? >> 8;
		if ($code != 0) {
			$kiwi -> failed ();
			$kiwi -> error  ("Couldn't create destination dir: $!");
			$kiwi -> failed ();
			return undef;
		}
		chomp $dest;
	} else {
		if (! mkdir $dest) {
			$kiwi -> failed ();
			$kiwi -> error  ("Couldn't create destination dir: $!");
			$kiwi -> failed ();
			return undef;
		}
	}
	$kiwi -> done ();
	$kiwi -> info ("Results will be written to: $dest");
	$kiwi -> done ();
	if (! $this -> getRootDevice()) {
		$kiwi -> failed ();
		$kiwi -> error ("Couldn't find system root device");
		$kiwi -> failed ();
		rmdir $dest;
		return undef;
	}
	#==========================================
	# Store object data
	#------------------------------------------
	my %OSSource;
	if (! open (FD,$main::KMigrate)) {
		$kiwi -> failed ();
		$kiwi -> error  ("Failed to open migration table");
		$kiwi -> failed ();
		return undef;
	}
	while (my $line = <FD>) {
		next if $line =~ /^#/;
		if ($line =~ /(.*)\s*=\s*(.*),(.*)/) {
			$OSSource{$1}{boot} = $2;
			$OSSource{$1}{src}  = $3;
		}
	}
	close FD;
	my @denyFiles = (
		'\.rpmnew',                  # no RPM backup files
		'\.rpmsave',                 # []
		'\.rpmorig',                 # []
		'~$',                        # no emacs backup files
		'\.swp$',                    # no vim backup files
		'\.rej$',                    # no diff reject files
		'\.lock$',                   # no lock files
		'\.tmp$',                    # no tmp files
		'\/etc\/init\.d\/rc.*\/',    # no service links
		'\/etc\/init\.d\/boot.d\/',  # no boot service links
		'\.depend',                  # no make depend targets
		'\.backup',                  # no sysconfig backup files
		'\.gz',                      # no gzip archives
		'\/usr\/src\/',              # no sources
		'\/spool',                   # no spool directories
		'^\/dev\/',                  # no device node files
		'\/usr\/X11R6\/'             # no depreciated dirs
	);
	if (defined $excl) {
		my @exclude = @{$excl};
		push @denyFiles,@exclude;
	}
	#==========================================
	# Store object data
	#------------------------------------------
	$this->{kiwi}   = $kiwi;
	$this->{deny}   = \@denyFiles;
	$this->{dest}   = $dest;
	$this->{name}   = $name;
	$this->{source} = \%OSSource;
	$this->{demo}   = $demo;
	return $this;
}

#==========================================
# setTemplate
#------------------------------------------
sub setTemplate {
	# ...
	# create basic image description structure and files
	# ---
	my $this = shift;
	my $dest = $this->{dest};
	my $name = $this->{name};
	my $kiwi = $this->{kiwi};
	#==========================================
	# get operating system version
	#------------------------------------------
	my $spec = $this -> getOperatingSystemVersion();
	my @pacs = $this -> getPackageList();
	my $boot = $this -> {source} -> {$spec} -> {boot};
	my $src  = $this -> {source} -> {$spec} -> {src};
	if (! defined $spec) {
		$kiwi -> error  ("Couldn't find system version information");
		$kiwi -> failed ();
		return undef;
	}
	if (! @pacs) {
		$kiwi -> error  ("Couldn't find installed packages");
		$kiwi -> failed ();
		return undef;
	}
	if (! defined $boot) {
		$kiwi -> warning ("Couldn't find OS version: $spec in source list");
		$kiwi -> skipped ();
		$boot = "***UNKNOWN-PLEASE-SELECT***";
		$src  = "***UNKNOWN-PLEASE-SELECT***";
	}
	#==========================================
	# create root directory
	#------------------------------------------
	mkdir "$dest/root";
	#==========================================
	# create config.xml
	#------------------------------------------
	if (! open (FD,">$dest/config.xml")) {
		return undef;
	}
	#==========================================
    # <description>
    #------------------------------------------
	print FD '<image name="'.$name.'">'."\n";
	print FD "\t".'<description type="system">'."\n";
	print FD "\t\t".'<author>***AUTHOR***</author>'."\n";
	print FD "\t\t".'<contact>***MAIL***</contact>'."\n";
	print FD "\t\t".'<specification>'.$spec.'</specification>'."\n";
	print FD "\t".'</description>'."\n";
	#==========================================
	# <preferences>
	#------------------------------------------
	print FD "\t".'<preferences>'."\n";
	print FD "\t\t".'<type primary="true" boot="isoboot/'.$boot.'"';
	print FD ' flags="unified">iso</type>'."\n";
	print FD "\t\t".'<type boot="vmxboot/'.$boot.'" filesystem="ext3"';
	print FD ' format="vmdk">vmx</type>'."\n";
	print FD "\t\t".'<type boot="xenboot/'.$boot.'"';
	print FD ' filesystem="ext3">xen</type>'."\n";
	print FD "\t\t".'<type boot="netboot/'.$boot.'"';
	print FD ' filesystem="ext3">pxe</type>'."\n";
	print FD "\t\t".'<version>1.1.2</version>'."\n";
	print FD "\t\t".'<packagemanager>smart</packagemanager>'."\n";
	print FD "\t".'</preferences>'."\n";
	#==========================================
	# <repository>
	#------------------------------------------
	print FD "\t".'<repository type="yast2">'."\n";
	print FD "\t\t".'<source path="'.$src.'"/>'."\n";
	print FD "\t".'</repository>'."\n";
	#==========================================
	# <packages>
	#------------------------------------------
	print FD "\t".'<packages type="image" patternType="plusRecommended">'."\n";
	foreach my $pac (@pacs) {
		print FD "\t\t".'<package name="'.$pac.'"/>'."\n";
	}
	print FD "\t".'</packages>'."\n";
	print FD "\t".'<packages type="xen" memory="512" disk="/dev/sda">'."\n";
	print FD "\t\t".'<package name="kernel-xen"/>'."\n";
	print FD "\t\t".'<package name="xen"/>'."\n";
	print FD "\t".'</packages>'."\n";
	print FD "\t".'<packages type="boot">'."\n";
	print FD "\t\t".'<package name="filesystem"/>'."\n";
	print FD "\t\t".'<package name="glibc-locale"/>'."\n";
	print FD "\t\t".'<package name="devs"/>'."\n";
	print FD "\t".'</packages>'."\n";
	print FD '</image>'."\n";
	close FD;
	return $this;
}

#==========================================
# getOperatingSystemVersion
#------------------------------------------
sub getOperatingSystemVersion {
	# ...
	# Find the version information of this system an create
	# a config.xml comment in order to allow to choose the correct
	# installation source
	# ---
	my $this = shift;
	if (! open (FD,"/etc/SuSE-release")) {
		return undef;
	}
	my $name = <FD>; chomp $name;
	my $vers = <FD>; chomp $vers;
	my $plvl = <FD>; chomp $plvl;
	$name =~ s/\s+/-/g;
	$name =~ s/\-\(.*\)//g;
	if ((defined $plvl) && ($plvl =~ /PATCHLEVEL = (.*)/)) {
		$plvl = $1;
		$name = $name."-SP".$plvl;
	}
	close FD;
	return $name;
}

#==========================================
# setServiceList
#------------------------------------------
sub setServiceList {
	# ...
	# Find all services enabled on the system and create
	# an appropriate config.sh file
	# ---
	my $this = shift;
	my $dest = $this->{dest};
	my @serviceBoot = glob ("/etc/init.d/boot.d/S*");
	my @serviceList = glob ("/etc/init.d/rc5.d/S*");
	my @service = (@serviceBoot,@serviceList);
	my @result;
	foreach my $service (@service) {
		my $name = readlink $service;
		if (defined $name) {
			$name =~ s/\.+\/+//g;
			push @result,$name;
		}
	}
	#==========================================
	# create config.xml
	#------------------------------------------
	if (! open (FD,">$dest/config.sh")) {
		return undef;
	}
	print FD '#!/bin/bash'."\n";
	print FD 'test -f /.kconfig && . /.kconfig'."\n";
	print FD 'test -f /.profile && . /.profile'."\n";
	print FD 'echo "Configure image: [$name]..."'."\n";
	foreach my $service (@result) {
		print FD 'suseInsertService '.$service."\n";
	}
	print FD 'suseConfig'."\n";
	print FD 'baseCleanMount'."\n";
	print FD 'exit 0'."\n";
	close FD;
	chmod 0755, "$dest/config.sh";
	return $this;
}

#==========================================
# getPackageList
#------------------------------------------
sub getPackageList {
	# ...
	# Find all packages installed on the system. This method
	# assume an RPM based system to build the package list for
	# the later image
	# ---
	my $this = shift;
	my @list = qx (rpm -qa --qf '%{NAME}\n'); chomp @list;
	return sort @list;
}

#==========================================
# getRootDevice
#------------------------------------------
sub getRootDevice {
	# ...
	# Find the root device of the operating system. Only those
	# data are inspected. We don't handle sub-mounted systems
	# within the root tree
	# ---
	my $this = shift;
	my $rootdev;
	if (! open (FD,"/etc/fstab")) {
		return undef;
	}
	my @fstab = <FD>; close FD;
	foreach my $mount (@fstab) {
		if ($mount =~ /\s+\/\s+/) {
			my @attribs = split (/\s+/,$mount);
			if ( -e $attribs[0]) {
				$rootdev = $attribs[0]; last;
			}
		}
	}
	if (! $rootdev) {
		return undef;
	}
	my $data = qx(df $rootdev | tail -n1);
	my $code = $? >> 8;
	if ($code != 0) {
		return undef;
	}
	if ($data =~ /$rootdev\s+\d+\s\s(\d+)\s\s/) {
		$data = $1;
		$data = int ( $data / 1024 );
	}	
	$this->{rdev}  = $rootdev;
	$this->{rsize} = $data;
	return $this;
}

#==========================================
# setSystemConfiguration
#------------------------------------------
sub setSystemConfiguration {
	# ...
	# 1) Find all files not owned by any package
	# 2) Find all files changed according to the package manager
	# ---
	my $this = shift;
	my $demo = $this->{demo};
	my $dest = $this->{dest};
	my $kiwi = $this->{kiwi};
	my $rdev = $this->{rdev};
	my @deny = @{$this->{deny}};
	my %result;
	#==========================================
	# mount root system
	#------------------------------------------
	my $data = qx(mount $rdev /mnt 2>&1);
	my $code = $? >> 8;
	if ($code != 0) {
		$kiwi -> error  ("Failed to mount root system: $data");
		$kiwi -> failed ();
		return undef;
	}
	$this->{mounted} = $code;
	#==========================================
	# generate File::Find closure
	#------------------------------------------
	sub generateWanted {
		my $filehash = shift;
		return sub {
			if (-f $File::Find::name) {
				$filehash->{$File::Find::name} = $File::Find::dir;
			}
		}
	};
	#==========================================
	# Find files not packaged
	#------------------------------------------
	my @dirs = (
		"/etc","/lib","/lib64","/bin",
		"/sbin","/opt","/srv","/usr"
	);
	my $wref = generateWanted (\%result);
	$kiwi -> info ("Inspecting root file system...");
	find ($wref, @dirs);
	$this -> cleanMount();
	$kiwi -> done ();
	$kiwi -> info ("Inspecting RPM database [installed files]...");
	my @rpmlist = qx(rpm -qal);
	my @curlist = keys %result;
	my $cursize = @curlist;
	my $rpmsize = @rpmlist;
	my $spart = 100 / $cursize;
	my $count = 0;
	my $done;
	my $done_old;
	$kiwi -> cursorOFF();
	foreach my $managed (@rpmlist) {
		chomp $managed; delete $result{$managed};
		$done = int ($count * $spart);
		if ($done != $done_old) {
			$kiwi -> step ($done);
		}
		$done_old = $done;
		$count++;
	}
	foreach my $file (sort keys %result) {
		foreach my $exp (@deny) {
			if ($file =~ /$exp/) {
				delete $result{$file}; last;
			}
		}
		$done = int ($count * $spart);
		if ($done != $done_old) {
			$kiwi -> step ($done);
		}
		$done_old = $done;
		$count++;
	}
	$kiwi -> note ("\n");
	$kiwi -> doNorm ();
	$kiwi -> cursorON();
	#==========================================
	# Find files packaged but changed
	#------------------------------------------
	$kiwi -> info ("Inspecting RPM database [verify]...");
	my @rpmcheck = qx(rpm -Va); chomp @rpmcheck;
	$rpmsize = @rpmcheck;
	$spart = 100 / $rpmsize;
	$count = 1;
	$kiwi -> cursorOFF();
	foreach my $check (@rpmcheck) {
		if ($check =~ /^missing/) {
			$count++; next;
		}
		if ($check =~ /(\/.*)/) {
			my $file = $1;
			my $dir  = qx (dirname $file); chomp $dir;
			my $ok   = 1;
			foreach my $exp (@deny) {
				if ($file =~ /$exp/) {
					$ok = 0; last;
				}
			}
			if ($ok) {
				$result{$file} = $dir;
			}
		}
		$done = int ($count * $spart);
		if ($done != $done_old) {
			$kiwi -> step ($done);
		}
		$done_old = $done;
		$count++;
	}
	$kiwi -> note ("\n");
	$kiwi -> doNorm ();
	$kiwi -> cursorON();
	#==========================================
	# Create report or custom root tree
	#------------------------------------------
	@rpmcheck = sort keys %result;
	if (defined $demo) {
		$kiwi -> info ("Creating report for root tree: $dest/report");
		my $data = qx(du -ch --time @rpmcheck > $dest/report 2>&1);
		my $code = $? >> 8;
		if ($code != 0) {
			$kiwi -> failed ();
			$kiwi -> error  ("Couldn't create report file: $data");
			$kiwi -> failed ();
			return undef;
		}
		$kiwi -> done ();
	} else {
		$kiwi -> info ("Setting up custom root tree...");
		$kiwi -> cursorOFF();
		$rpmsize  = @rpmcheck;
		$spart = 100 / $rpmsize;
		$count = 1;
		foreach my $file (@rpmcheck) {
			if (-e $file) {
				my $dir = $result{$file};
				if (! -d "$dest/root/$dir") {
					qx(mkdir -p $dest/root/$dir);
				}
				qx(cp -a $file $dest/root/$file);
			}
			$done = int ($count * $spart);
			if ($done != $done_old) {
				$kiwi -> step ($done);
			}
			$done_old = $done;
			$count++;
		}
		$kiwi -> note ("\n");
		$kiwi -> doNorm ();
		$kiwi -> cursorON();
	}
	return %result;
}

#==========================================
# cleanMount
#------------------------------------------
sub cleanMount {
	my $this = shift;
	if (defined $this->{mounted}) {
		qx(umount /mnt); undef $this->{mounted};
	}
	return $this;
}

1;
