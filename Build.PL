
use strict ;
use warnings ;

use Module::Build;

my %all_modules ;
my @split_modules ;

my @pm_files = qw(
lib/CPAN/Mini//Indexed.pm
);

for(@pm_files)
	{
	$all_modules{$_} = $_ ;
	push @split_modules, $_ ;
	}

sub GetVersionAndRevisionFrom
{
my ($file) = @_ ;

my $version_from = File::Spec->catfile( split '/', $file );
my $version      = Module::Build->version_from_file($version_from);

if($ENV{'CPAN_Mini_Indexed_USE_GIT_VERSION_FOR_DIST'})
	{
	my $number_of_commits = `git log | grep -E 'commit [0-9a-f]{40}' | wc -l` ;
	chomp $number_of_commits ;
	
	if($number_of_commits)
		{
		#~ print "number of git revision $number_of_commits.\n" ;
		return("${version}.${number_of_commits}") ;
		}
	else
		{
		print "Couldn't get git revision, using version from '$file'!\n" ;
		return($version) ;
		}
	}
else
	{
	return($version) ;
	}
}

my $code = <<'EOC'

use strict ;
use warnings ;

sub GetVersionAndRevisionFrom
{
my ($file) = @_ ;

my $version_from = File::Spec->catfile( split '/', $file );
my $version      = Module::Build->version_from_file($version_from);

if($ENV{'CPAN_Mini_Indexed_USE_GIT_VERSION_FOR_DIST'})
	{
	my $number_of_commits = `git log | grep -E 'commit [0-9a-f]{40}' | wc -l` ;
	chomp $number_of_commits ;
	
	if($number_of_commits)
		{
		#~ print "number of git revision $number_of_commits.\n" ;
		return("${version}.${number_of_commits}") ;
		}
	else
		{
		print "Couldn't get git revision, using version from '$file'!\n" ;
		return($version) ;
		}
	}
else
	{
	return($version) ;
	}
}

sub ACTION_author_test
{
my $self = shift;
local $self->{properties}{test_files} = 'xt/author/*.t' ;
$self->SUPER::ACTION_test();
}

sub ACTION_dist
{
my $self = shift;

if($ENV{'CPAN_Mini_Indexed_USE_GIT_VERSION_FOR_DIST'})
	{
	my $have_git = $self->do_system('git --version');
	
	if($have_git)
		{
		print `git status -a`;
		
		if($self->do_system('git log  --decorate > git_Changes'))
			{
			use File::Copy;
			move('git_Changes', 'Changes') ;
			}
		else
			{
			print "Couldn't get git log, 'Changes' will not be generated from git log!\n" ;
			}
		}
	else
		{
		print "git not found, 'Changes' will not be generated from git log!\n" ;
		}
	}

$self->SUPER::ACTION_test() ;
#~ $self->ACTION_author_test() ;

$self->SUPER::ACTION_dist();
};

EOC
;

my $class = Module::Build->subclass(class => 'CPAN::Mini::Indexed', code => $code) ;

my $build = $class->new
	(
	module_name => 'CPAN::Mini::Indexed',
	
	dist_version => GetVersionAndRevisionFrom('lib/CPAN/Mini/Indexed.pm'),
	
	license => 'perl',
	build_requires => 
		{
		'Text::Diff' => 0,
		'Test::Block' => 0,
		'Test::Exception' => 0,
		'Test::NoWarnings' => 0,
		'Test::Warn' => 0,
		},
		
	requires => 
		{
		'Readonly'         => 0,
		'Sub::Exporter'     => 0,
		'File::Temp' => 0.21,
		'Getopt::Long' => 0 ,
		'Time::HiRes'     => 0,
		'Search::Indexer' => 0.75,
		'Term::Bash::Completion::Generator' => 0,
		'Text::Pluralize' => 0,
		'File::Find::Rule' => 0,
		'IO::Zlib' => 0,
		'Archive::Tar' => 0,
		'File::Copy' => 0,
		},
		
	pm_files     => \%all_modules,
	#~ autosplit    => \@split_modules,
	
	script_files => 'scripts/mci',
	dist_author  => 'Nadim ibn hamouda el Khemir. <nkh@cpan.org>',
	dist_abstract => 'Index the content of your CPAN mini repository',
	);
	
$build->create_build_script;
  
