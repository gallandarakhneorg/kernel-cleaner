#!/usr/bin/perl -W

use strict;
use Getopt::Long;
use File::Basename;
use File::Spec;
use File::Copy;
use File::Path;
use Compress::Zlib;
use Pod::Text;
use Pod::Man;

# GENERAL INSTALLATION INFORMATIONS
my $ALLOW_SYMBOLIC_LINK;
my $INSTALLDIRECTORY;
my $LOCALEDIRECTORY;
my $ICONDIRECTORY;
my $DESKTOPDIRECTORY;
my $BINDIRECTORY;
my $SBINDIRECTORY;
my $ETCDIRECTORY;
my $MANDIRECTORY;
my $SHAREDIRECTORY;
my $ROOTDIRECTORY;

sub dbg(@) {
	use Data::Dumper;
	die(Dumper(@_));
}

#------------------------------------------------------------------------------------------
# $_[0] : shell pattern
sub substShellPatterns($) {
	my $t = '';
	$t = "$_[0]" if ($_[0]);
	if ($t) {
		$_[0] =~ s/^~([a-z_0-9]+)/
			my @l = getpwnam("$1");
			if (@l>=8) {
				"$l[7]";
			}
			else {
				"~$1";
			}
			/e;
		$_[0] =~ s/^~\//$ENV{'HOME'}\//;
	}
	return $_[0];
}

#------------------------------------------------------------------------------------------
# $_[0] : filename of the file to compress
sub gzipfct($) {
	my $targetfile = shift;
	local *IN;
	my $gz = gzopen("$targetfile.gz","wb") or die("$targetfile.gz: $!");
	open(*IN, "<", "$targetfile") or die("$targetfile: $!");
	while (<IN>) {
		$gz->gzwrite($_);
	}
	close(*IN);
	$gz->gzclose();
	unlink "$targetfile";
}

#------------------------------------------------------------------------------------------
# $_[0] : file name
sub rm($) {
	my $delfile = shift;
	if (-f "$delfile") {
		print "delete $delfile\n";
		unlink "$delfile";
	}
}

#------------------------------------------------------------------------------------------
# $_[0] : directory name
# $_[1] : pattern
# $_[2..+inf] : 
sub getFilesRec($@) {
	my $directory = shift;
	my $pattern = shift;
	my @list = ();
	if (($pattern)&&(-d "$directory")) {
		# Make a pattern
		$pattern =~ s/\./\\./g;
		$pattern =~ s/\*/.*/g;

		# Get the directory content
		my @subdirs = ();
		local *DIR;
		opendir(*DIR,"$directory")
			or die("$directory: $!\n");
		while (my $d = readdir(*DIR)) {
			if (($d ne File::Spec->curdir())&&($d ne File::Spec->updir())&&
			    ($d =~ /^$pattern$/)) {
				my $full = File::Spec->catfile($directory,$d);
				if (-d "$full") {
					push @subdirs, "$full";
				}
				elsif (!@_) {
					push @list, "$full";
				}
			}
		}
		closedir(*DIR);

		# Go into sub directories
		foreach my $d (@subdirs) {
			my @l = &getFilesRec("$d",@_);
			push @list, @l;
		}
	}
	return @list;
}

#------------------------------------------------------------------------------------------
# $_[0..+inf] : directory name
sub getFiles(@) {
	my $firstpart = shift;
	if ($firstpart) {
		return getFilesRec('.',$firstpart,@_);
	}
	else {
		return getFilesRec(FileSpec->rootdir(),@_);
	}
}

#------------------------------------------------------------------------------------------
# $_[0..+inf] : directory name
sub getDirectories(@) {
	my @list;
	local *DIR;
	foreach my $d (@_) {
		if (-d "$d") {
			opendir(*DIR,"$d") or die("$d: $!\n");
			while (my $sd = readdir(*DIR)) {
				if (($sd ne File::Spec->curdir())&&($sd ne File::Spec->updir())) {
					my $full = File::Spec->catfile($d,$sd);
					if (-d "$full") {
						push @list, "$full";
					}
				}
			}			
			closedir(*DIR);
		}
	}
	return @list;
}

#------------------------------------------------------------------------------------------
# $_[0..+inf] : directory name
sub getDirectoryBasenames(@) {
	my @list;
	local *DIR;
	foreach my $d (@_) {
		if (-d "$d") {
			opendir(*DIR,"$d") or die("$d: $!\n");
			while (my $sd = readdir(*DIR)) {
				if (($sd ne File::Spec->curdir())&&($sd ne File::Spec->updir())) {
					my $full = File::Spec->catfile($d,$sd);
					if (-d "$full") {
						push @list, "$sd";
					}
				}
			}			
			closedir(*DIR);
		}
	}
	return @list;
}

#------------------------------------------------------------------------------------------
# $_[0..+inf] : directory name
sub mkdirrec(@) {
	foreach my $dir (@_) {
		my @parts = File::Spec->splitdir($dir);
		my @np = ();
		foreach my $d (@parts) {
			if ($d) {
				my $rep = @np ? File::Spec->catdir(@np,$d) : $d;
				unless (-d "$rep") {
					mkdir("$rep") or die("$rep: $!\n");
					chmod 0755, "$rep";
				}
			}
			push @np, $d;
		}		
	}
}

#------------------------------------------------------------------------------------------
# $_[0] : source filename
# $_[1] : target directory
# $_[2] : new basename for the target file
sub install($$;$) {
	my $sourcefile = shift;
	my $targetdir = shift;
	my $newbasename = shift || basename("$sourcefile");
	mkdirrec($targetdir);
	print "installing $sourcefile into $targetdir\n";
	my $fullname = File::Spec->catfile($targetdir,$newbasename);
	copy("$sourcefile","$fullname")
		or die("$sourcefile: $!\n");
	chmod 0644, "$fullname";	
	return $fullname;
}

#------------------------------------------------------------------------------------------
# $_[0] : directory name
sub touchDir($) {
	my $targetdir = shift;
	print "installing $targetdir directory\n";
	my $fullname = File::Spec->catfile($ROOTDIRECTORY,$targetdir);
	mkdirrec("$fullname");
	return "$fullname";
}

#------------------------------------------------------------------------------------------
# $_[0] : file name
sub touchFile($) {
	my $targetfile = shift;
	print "installing $targetfile empty file\n";
	my $fullname = File::Spec->catfile($ROOTDIRECTORY,$targetfile);
	mkdirrec(dirname("$fullname"));
	local *FILE;
	open(*FILE, ">> $fullname") or die("$fullname: $!\n");
	close(*FILE);
	return "$fullname";
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : target directory
# $_[2] : new basename of the target file
sub installLink($$;$) {
	return '' unless ($ALLOW_SYMBOLIC_LINK);
	my $sourcefile = File::Spec->rel2abs(shift);
	my $targetdir = File::Spec->rel2abs(shift);
	my $newbasename = shift || basename("$sourcefile");
	mkdirrec($targetdir);
	print "installing link $sourcefile into $targetdir\n";
	my $fullname = File::Spec->catfile($targetdir,$newbasename);
	my $linkname = File::Spec->abs2rel("$sourcefile","$targetdir");
	unlink("$fullname") if (-e "$fullname");
	symlink("$linkname","$fullname")
		or die("$sourcefile: $!\n");
	return $fullname;
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : target directory
# $_[2] : new basename of the target file
sub installExec($$;$) {
	my $fullname = install($_[0],$_[1],$_[2]);
	chmod 0755, "$fullname";	
	return $fullname;
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : new basename of the target file
sub installCfg($;$) {
	return install($_[0],$ETCDIRECTORY,$_[1]);
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : new basename of the target file
# $_[2] : rc.d run level
sub installInitD($$$) {
	my $initdDir = File::Spec->catfile($ETCDIRECTORY,"init.d");
	my $fullname = install($_[0],$initdDir,$_[1]);
	chmod 0755, "$fullname";

	my $level = $_[2];
	my @levels = ('2');

	foreach my $l (@levels) {
		my $rcDir = File::Spec->catfile($ETCDIRECTORY, "rc$l.d");
		if (! -d "$rcDir") {
			mkpath("$rcDir") or die("$rcDir: $!\n");
		}
		symlink("/etc/init.d/$_[1]", File::Spec->catfile("$rcDir", "S99kernel-cleaner"))
		or die(File::Spec->catfile("$rcDir", "S99kernel-cleaner").": $!\n");
	}

	return $fullname;
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : new basename of the target file
sub installBin($;$) {
	return installExec($_[0],$BINDIRECTORY,$_[1]);
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : new basename of the target file
sub installSBin($;$) {
	return installExec($_[0],$SBINDIRECTORY,$_[1]);
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : target directory when to copy the exec file
# $_[2] : the basename of the symbolic link in /usr/bin
sub installLinkedBin($$;$) {
	my $fullname = installExec($_[0],$_[1]);
	my $linkname = installLink($fullname,$BINDIRECTORY,$_[2]);
	return ($fullname,$linkname);
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : target directory when to copy the exec file
# $_[2] : the basename of the symbolic link in /usr/sbin
sub installLinkedSBin($$;$) {
	my $fullname = installExec($_[0],$_[1]);
	my $linkname = installLink($fullname,$SBINDIRECTORY,$_[2]);
	return ($fullname,$linkname);
}

#------------------------------------------------------------------------------------------
# $_[0] : source file
# $_[1] : subdirectory in the share directory
# $_[2] : the basename of the symbolic link in /usr/sbin
sub installSharedFile($$;$) {
	my $targetdir = File::Spec->catfile($SHAREDIRECTORY, $_[1]);
	my $fullname = install($_[0],$targetdir,$_[2]);
	return $fullname;
}

#------------------------------------------------------------------------------------------
# $_[0..+inf] : names of the files for the manual pages
sub installMan(@) {
	my @result = ();
	my %mandirectories = ();
	foreach my $man (@_) {
		my @parts = File::Spec->splitdir($man);
		my @files = getFiles(@parts);
		die("$man: no manual file found\n") unless (@files);
		foreach my $f (@files) {
			my $base = basename($f);
			if ($base =~ /^(.*?)\.([a-z_]+)\.([0-9]+\.gz)$/) {
				my $lang = "$2";
				my $name = "$1.$3";
				unless ($mandirectories{"$lang"}) {
					my @l = File::Spec->splitdir($MANDIRECTORY);
					my $last = pop @l;
					push @l, $lang;
					push @l, $last;
					$mandirectories{"$lang"} = File::Spec->catfile(@l);
				}
				install($f,$mandirectories{"$lang"},$name);
			}
			else {
				push @result, install($f,$MANDIRECTORY);
			}
		}
	}
	return @result;
}

#------------------------------------------------------------------------------------------
# $_[0] : target directory when to copy the exec file
# $_[1..+inf] : file to copy
sub installInto($@) {
	my $target = shift;
	my @result = ();
	foreach my $fileToInstall (@_) {
		push @result, install($fileToInstall, $target);
	}
	return @result;
}

#------------------------------------------------------------------------------------------
# $_[0] : target directory when to copy the exec file
# $_[1..+inf] : file to copy
sub installExecInto($@) {
	my $target = shift;
	my @files = installInto($target,@_);
	foreach my $file (@files) {
		chmod 0755, "$file";
	}
	return @files;
}

#------------------------------------------------------------------------------------------
sub DO_compile(\%) {
	print "DO KERNEL-CLEANER COMPILATION...\n";

	local *DIR;
	local *DIR2;
	my $directory = File::Spec->catdir($_[0]->{'directory'},'po');
	opendir(*DIR,"$directory") or die("$directory: $!\n");
	while (my $topdir = readdir(*DIR)) {
		if (($topdir ne File::Spec->curdir())&&($topdir ne File::Spec->updir())) {
			my $subdirectory = File::Spec->catdir($directory,$topdir,'LC_MESSAGES');
			opendir(*DIR2,"$subdirectory") or next;
			while (my $pofile = readdir(*DIR2)) {
				if ($pofile =~ /\.po$/i) {
					print "Generating '$topdir' translations for $pofile...\n";
					my $mofile = $pofile;
					$mofile =~ s/\.po/.mo/i;
					system('msgfmt','-v','-o',
						File::Spec->catfile("$subdirectory","$mofile"),
						File::Spec->catfile("$subdirectory","$pofile"));
				}
			}
			closedir(*DIR2);
		}
	}
	closedir(*DIR);
}

#------------------------------------------------------------------------------------------
sub DO_install(\%) {
	print "DO KERNEL-CLEANER INSTALLATION...\n";

	installSBin('src/kernel-cleaner', 'kernel-cleaner');
	installSBin('src/gkernel-cleaner', 'gkernel-cleaner');

	installLink(
		File::Spec->catfile($SBINDIRECTORY,'gkernel-cleaner'),
		File::Spec->catfile($SHAREDIRECTORY,'gnome','autostart'));

	install('src/kernelcleaner_yes.png', $ICONDIRECTORY);
	install('src/kernelcleaner_no.png', $ICONDIRECTORY);
	install('src/kernelcleaner_rm.png', $ICONDIRECTORY);

	my @directories = getDirectoryBasenames('po');
	foreach my $lang (@directories) {
		installInto(
			File::Spec->catfile($LOCALEDIRECTORY,"$lang",'LC_MESSAGES'),
			getFiles('po',"$lang",'LC_MESSAGES','*.mo'));
	}

}

#------------------------------------------------------------------------------------------
sub DO_clean(\%) {
	print "DO KERNEL-CLEANER CLEANING...\n";

	local *DIR;
	local *DIR2;
	my $directory = File::Spec->catdir($_[0]->{'directory'},'po');
	opendir(*DIR,"$directory") or die("$directory: $!\n");
	while (my $topdir = readdir(*DIR)) {
		if (($topdir ne File::Spec->curdir())&&($topdir ne File::Spec->updir())) {
			my $subdirectory = File::Spec->catdir($directory,$topdir,'LC_MESSAGES');
			opendir(*DIR2,"$subdirectory") or next;
			while (my $mofile = readdir(*DIR2)) {
				if ($mofile =~ /\.mo$/i) {
					rm(File::Spec->catfile("$subdirectory","$mofile"));
				}
			}
			closedir(*DIR2);
		}
	}
	closedir(*DIR);

	rm(File::Spec->catfile($_[0]->{'directory'},'Makefile'));
}

#------------------------------------------------------------------------------------------
sub DO_createMakefile(\%) {
	print "CREATING MAKEFILE...\n";
	local *OUT;

	my @options = ();
	if ($_[0]->{'version'}) {
		push @options, '"--version='.$_[0]->{'version'}.'"';
	}
	if ($_[0]->{'prefix'}) {
		push @options, '"--prefix='.$_[0]->{'prefix'}.'"';
	}
	if ($_[0]->{'man-prefix'}) {
		push @options, '"--manprefix='.$_[0]->{'man-prefix'}.'"';
	}
	if ($_[0]->{'locale-prefix'}) {
		push @options, '"--localeprefix='.$_[0]->{'locale-prefix'}.'"';
	}
	if ($_[0]->{'etc-prefix'}) {
		push @options, '"--etcprefix='.$_[0]->{'etc-prefix'}.'"';
	}
	if ($_[0]->{'icon-prefix'}) {
		push @options, '"--iconprefix='.$_[0]->{'icon-prefix'}.'"';
	}
	if ($_[0]->{'desktop-prefix'}) {
		push @options, '"--desktopprefix='.$_[0]->{'desktop-prefix'}.'"';
	}
	if ($_[0]->{'create-links'}) {
		push @options, '"--link"';
	}
	else {
		push @options, '"--nolink"';
	}
	if ($_[0]->{'create-etc-links'}) {
		push @options, '"--etclink"';
	}
	else {
		push @options, '"--noetclink"';
	}
	if ($_[0]->{'create-bin-links'}) {
		push @options, '"--binlink"';
	}
	else {
		push @options, '"--nobinlink"';
	}

	my $options = join(' ',@options);

	my $filename = File::Spec->catfile($_[0]->{'directory'},"Makefile");
	open(*OUT, "> $filename") or die("$filename: $!\n");
	print OUT "all:\n";
	print OUT "\t@ perl ".__FILE__." $options compile\n\n";
	print OUT "install:\n";
	print OUT "\t@ perl ".__FILE__." $options install\n\n";
	print OUT "clean:\n";
	print OUT "\t@ perl ".__FILE__." $options clean\n\n";
	close(*OUT);
}

#------------------------------------------------------------------------------------------
my %options = ();
$options{'directory'} = File::Spec->rel2abs(dirname(__FILE__));
$options{'create-links'} = 1;
$options{'create-bin-links'} = 1;
$options{'create-etc-links'} = 1;

# Detect the version number
local *FILE;
open(*FILE,"<".File::Spec->catfile($options{'directory'},'VERSION'))
	or die(File::Spec->catfile($options{'directory'},'VERSION').":$!\n");
while (my $line = <FILE>) {
	if ($line =~ /^\s*kernel-cleaner\s*([0-9\-a-z\.]+)\s*$/i) {
		$options{'version'} = "$1";
	}
}
close(*FILE);

# Read command line
if (!GetOptions(
		'etcprefix=s' => \$options{'etc-prefix'},
		'manprefix=s' => \$options{'man-prefix'},
		'shareprefix=s' => \$options{'share-prefix'},
		'localeprefix=s' => \$options{'locale-prefix'},
		'iconprefix=s' => \$options{'icon-prefix'},
		'desktopprefix=s' => \$options{'desktop-prefix'},
		'prefix=s' => \$options{'prefix'},
		'version=s' => \$options{'version'},
		'link!' => \$options{'create-links'},
		'binlink!' => \$options{'create-bin-links'},
		'etclink!' => \$options{'create-etc-links'},
		)) {
	exit(1);
}

# Detect action
$options{'action'} = 'unknow';
foreach my $act (@ARGV) {
	if ($act eq 'compile') {
		$options{'action'} = 'compile';
	}
	elsif ($act eq 'install') {
		$options{'action'} = 'install';
	}
	elsif ($act eq 'clean') {
		$options{'action'} = 'clean';
	}
}

# Set the paths
if (("$^O" eq 'MSWin32')||
    ("$^O" eq 'NetWare')||
    ("$^O" eq 'symbian')) {
	# Win32 compatible platform
	$ALLOW_SYMBOLIC_LINK = 0;

	my $ROOTDIRECTORY = 'C:';
	my $PREFIX = substShellPatterns($options{'prefix'}) || File::Spec->catfile('C:','Program Files');
	my $ETCPREFIX = "$PREFIX";
	my $SHAREPREFIX = substShellPatterns($options{'share-prefix'}) || File::Spec->catfile('C:','Documents and Settings','All Users','Application Data');
	my $MANPREFIX = substShellPatterns($options{'man-prefix'}) || File::Spec->catfile('C:','Documents and Settings','All Users','Application Data');
	my $LOCALEPREFIX = substShellPatterns($options{'locale-prefix'}) || File::Spec->catfile('C:','Documents and Settings','All Users','Application Data');
	my $ICONPREFIX = substShellPatterns($options{'icon-prefix'}) || File::Spec->catfile('C:','Documents and Settings','All Users','Application Data');
	my $DESKTOPPREFIX = substShellPatterns($options{'desktop-prefix'}) || File::Spec->catfile('C:','Documents and Settings','All Users','Bureau');
	$INSTALLDIRECTORY = File::Spec->catfile("$PREFIX",'kernel-cleaner');
	$BINDIRECTORY = File::Spec->catfile("$PREFIX",'kernel-cleaner');
	$SBINDIRECTORY = File::Spec->catfile("$PREFIX",'kernel-cleaner');
	$LOCALEDIRECTORY = File::Spec->catfile("$LOCALEPREFIX",'locale');
	$ICONDIRECTORY = File::Spec->catfile("$ICONPREFIX",'kernel-cleaner');
	$DESKTOPDIRECTORY = File::Spec->catfile("$DESKTOPPREFIX",'kernel-cleaner');
	$ETCDIRECTORY = "$ETCPREFIX";
	$MANDIRECTORY = File::Spec->catfile("$MANPREFIX",'kernel-cleaner','man','english');
	$SHAREDIRECTORY = "$SHAREPREFIX";
}
else {
	# Unix compatible platform
	$ALLOW_SYMBOLIC_LINK = 1;

	my $PREFIX = substShellPatterns($options{'prefix'}) || File::Spec->catfile('','usr','local');
	my $end = File::Spec->catfile('usr','local');
	if ($PREFIX =~ /\Q$end\E$/) {
		$end = File::Spec->catfile("$PREFIX",'..','..','etc');
	}
	else {
		$end = File::Spec->catfile("$PREFIX",'..','etc');
	}
	my $ETCPREFIX = substShellPatterns($options{'etc-prefix'}) || $end;
	my $SHAREPREFIX = substShellPatterns($options{'share-prefix'}) || File::Spec->catfile($PREFIX,'share');
	my $MANPREFIX = substShellPatterns($options{'man-prefix'}) || File::Spec->catfile($PREFIX,'man');
	my $LOCALEPREFIX = substShellPatterns($options{'locale-prefix'}) || $PREFIX;
	my $ICONPREFIX = substShellPatterns($options{'icon-prefix'}) || $PREFIX;
	my $DESKTOPPREFIX = substShellPatterns($options{'desktop-prefix'}) || $PREFIX;

	$ROOTDIRECTORY = File::Spec->canonpath(File::Spec->catfile("$PREFIX",'..'));
	$INSTALLDIRECTORY = File::Spec->catfile("$PREFIX",'lib','kernel-cleaner');
	$BINDIRECTORY = File::Spec->catfile("$PREFIX",'bin');
	$SBINDIRECTORY = File::Spec->catfile("$PREFIX",'sbin');
	$LOCALEDIRECTORY = File::Spec->catfile("$LOCALEPREFIX",'share','locale');
	$ICONDIRECTORY = File::Spec->catfile("$ICONPREFIX",'share','icons');
	$DESKTOPDIRECTORY = File::Spec->catfile("$DESKTOPPREFIX",'share','applications');
	$ETCDIRECTORY = "$ETCPREFIX";
	$MANDIRECTORY = File::Spec->catfile("$MANPREFIX",'man1');
	$SHAREDIRECTORY = "$SHAREPREFIX";
}

# Run the action
if ($options{'action'} ne 'unknow') {
	eval("DO_".$options{'action'}.'(%options);');
	die"$@\n" if ($@);
}
else {
	DO_createMakefile(%options);
}

exit(0);

__END__

