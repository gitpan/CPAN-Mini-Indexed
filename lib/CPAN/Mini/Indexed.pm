
package CPAN::Mini::Indexed ;

use strict ;
use warnings ;
use Carp ;

BEGIN 
{
use Sub::Exporter -setup => 
	{
	exports => [ qw(search check_index show_database_information) ],
	groups  => 
		{
		all  => [ qw() ],
		}
	};
	
use vars qw ($VERSION);
$VERSION     = '0.03_01';
}

#-------------------------------------------------------------------------------

use Time::HiRes 'time' ;
use File::Temp ;
use Text::Pluralize;
use File::Find::Rule ;
use IO::Zlib ;
use Archive::Tar ;
use File::Copy ;

use Search::Indexer::Incremental::MD5 qw() ;
use Search::Indexer::Incremental::MD5::Indexer qw() ;
use Search::Indexer::Incremental::MD5::Searcher qw() ;
use Search::Indexer::Incremental::MD5::Language::Perl qw() ;

use English qw( -no_match_vars ) ;

use Readonly ;
Readonly my $EMPTY_STRING => q{} ;

#-------------------------------------------------------------------------------

=head1 NAME

CPAN::Mini::Indexed - Index the content of your CPAN mini repository

=head1 SYNOPSIS


=head1 DESCRIPTION

This module implements ...

=head1 DOCUMENTATION

=head1 SUBROUTINES/METHODS

=cut

#----------------------------------------------------------------------------------------------------------

sub show_database_information
{

=head2 ( )

  some code

I<Arguments>

=over 2 

=item * $ - 

=back

I<Returns> - Nothing

I<Exceptions> - None

=cut

my ($options) = @_ ;
my $information = Search::Indexer::Incremental::MD5::show_database_information($options->{index_directory}) ;

# make sizes more readable
1 while $information->{entries} =~ s/^([-+]?\d+)(\d{3})/$1_$2/ ;
1 while $information->{size} =~ s/^([-+]?\d+)(\d{3})/$1_$2/ ;

print {*STDOUT} <<"EOI" ;
Location: $options->{index_directory}
Last updated on: $information->{update_date}
Number of indexed documents: $information->{entries}
Database size: $information->{size} bytes
EOI
}

#----------------------------------------------------------------------------------------------------------

sub search
{

=head2 ( )

  some code

I<Arguments>

=over 2 

=item * $ - 

=back

I<Returns> - Nothing

I<Exceptions> - None

=cut

my ($options) = @_ ;

my $searcher 
	= eval 
		{
		Search::Indexer::Incremental::MD5::Searcher->new
			(
			INDEX_DIRECTORY => $options->{index_directory}, 
			USE_POSITIONS => 0, 
			WORD_REGEX => qr/\w+/,
			);
		} or croak "No full text index found! $EVAL_ERROR\n" ;

my $results  = $searcher->search(SEARCH_STRING => $options->{search}) ;

my @indexes = map { $_->[0] }
				reverse
					sort { $a->[1] <=> $b->[1] }
						map { [$_, $results->[$_]{SCORE}] }
							0 .. $#$results ;

my ($displayed_matches, %displayed_module) = (0) ;

for my $index (@indexes)
	{
	last if $displayed_matches++ == $options->{lines} ;
	
	my $matching_file = $results->[$index]{PATH} ;
	
	unless($matching_file)
		{
		carp "matched id:'$results->[$index]{ID}' which was removed!\n" ;
		next ;
		}
	
	(my $matching_file_short = $matching_file) =~ s{^/tmp/[^/]+/}{} ;
	
	if($options->{modules_only})
		{
		(my $matching_module = $matching_file_short) =~ s{^([^/]+).*}{$1} ;
		$matching_module =~ s/(.*)-.*/$1/g ;
		$matching_module =~ s/-/::/g ;
		
		print {*STDOUT} "$matching_module\n" unless exists $displayed_module{$matching_module} ;
		
		$displayed_module{$matching_module} += $results->[$index]{SCORE} ;
		}
	else
		{
		if($options->{verbose})
			{
			print {*STDOUT} "'$matching_file_short' [id:'$results->[$index]{ID}', score: '$results->[$index]{SCORE}]'\n" ;
			}
		else
			{
			print {*STDOUT} "$matching_file_short\n" ;
			}
		}
	}
}

#----------------------------------------------------------------------------------------------------------

sub check_index
{

=head2 check_index($indexer, $options)

 brings the cpan mini index database up to date

I<Arguments> - 

$indexer, $options

I<Returns> -  Nothing

I<Exceptions> - 

=cut

my ($options) = @_ ;

my $cpan_mini = $options->{cpan_mini} || $ENV{CPAN_MINI} || '/devel/cpan' ;
$cpan_mini =~ s{^\./}[] ;
$cpan_mini =~ s{/$}[] ;

croak "Invalid cpan mini repository!\n" if $cpan_mini eq $EMPTY_STRING;

printf "[CPAN mini repository in '$cpan_mini']\n" if ($options->{verbose}) ;

my $modules_details_file = "$cpan_mini/modules/02packages.details.txt.gz" ;
my $cache_details_file = "$options->{index_directory}/02packages.details.txt.gz" ;

if(index_needs_update($modules_details_file, $cache_details_file))
	{
	my @stopwords = (STOPWORDS => $options->{stopwords_file}) if $options->{stopwords_file} ;

	my $indexer = Search::Indexer::Incremental::MD5::Indexer->new
					(
					INDEX_DIRECTORY => $options->{index_directory}, 
					USE_POSITIONS => 0, 
					Search::Indexer::Incremental::MD5::Language::Perl::get_perl_word_regex_and_stopwords(),
					@stopwords,
					) ;

	my ($modules_in_repository, $modules_up_to_date, $modules_out_of_date) = scan_index($cpan_mini, $indexer) ;

	remove_out_of_date_modules($indexer, $modules_out_of_date, $options) ;

	my %new_modules = grep { ! exists $modules_up_to_date->{$_} } keys %{$modules_in_repository};

	add_new_modules($indexer, $cpan_mini, \%new_modules, $options) ;

	if(-e $modules_details_file)
		{
		copy($modules_details_file, $cache_details_file) or carp "Warning: '$cache_details_file' creation failed: $!" ;
		}
	}

return ;
}

#----------------------------------------------------------------------------------------------------------

sub index_needs_update
{

=head2 ( )

  some code

I<Arguments>

=over 2 

=item * $ - 

=back

I<Returns> - Nothing

I<Exceptions> - None

=cut

my ($modules_details_file, $cache_details_file) = @_ ;

my $index_need_update = 1 ;

if(-e $modules_details_file && -e $cache_details_file)
	{
	if
		(
		Search::Indexer::Incremental::MD5::get_file_MD5($modules_details_file) 
			eq Search::Indexer::Incremental::MD5::get_file_MD5($cache_details_file)
		)
		{
		$index_need_update = 0 ; 
		}
	}
	
return $index_need_update ;
}

#----------------------------------------------------------------------------------------------------------

sub scan_index
{

=head2 ( )

  some code

I<Arguments>

=over 2 

=item * $ - 

=back

I<Returns> - Nothing

I<Exceptions> - None

=cut

my ($cpan_mini, $indexer) = @_ ;

my %modules_in_repository
	= map {chomp($_) ; $_ => 1} 
		File::Find::Rule
			->file()
			->name('*.tar.gz')
			->in($cpan_mini);


my (%modules_up_to_date, %indexed_modules_to_remove) ;

$indexer->check_indexed_files
		(
		DONE_ONE_FILE_CALLBACK =>
			sub 
			{
			my ($file, $description, $file_info) = @_ ;			
			
			if(exists $modules_in_repository{"$cpan_mini/$description"})
				{
				# we can't delete $modules_in_repository{$cpan_mini . $description} as
				# it may contain multiple indexed files
				$modules_up_to_date{"$cpan_mini/$description"}++ ;
				}
			else
				{
				$indexed_modules_to_remove{$description}{$file} = $file_info->{ID} ;
				}
			},
		) ;
		
return (\%modules_in_repository, \%modules_up_to_date, \%indexed_modules_to_remove) ;
}

#----------------------------------------------------------------------------------------------------------

sub remove_out_of_date_modules
{

=head2 ( )

  some code

I<Arguments>

=over 2 

=item * $ - 

=back

I<Returns> - Nothing

I<Exceptions> - None

=cut

my ($indexer, $modules_out_of_date, $options) = @_ ;

my $t0_remove = time ;

my $number_of_modules = scalar(keys %{$modules_out_of_date}) ;
my $module_index = 0 ;
my $total_number_of_files = 0 ;

for my $module_to_remove(sort keys %{$modules_out_of_date})
	{
	my $t0_remove_module = time ;
	
	$module_index++ ;
	print "-$module_to_remove\n" ;
	
	my $number_of_files_in_module = 0 ;
	
	for my $module_element (sort keys %{$modules_out_of_date->{$module_to_remove}})
		{
		(my $module_element_short = $module_element) =~ s{^/tmp/[^/]+/}[] ;
		
		$total_number_of_files++ ;
		$number_of_files_in_module++ ;
		
		print "\t-$module_element_short\n" if $options->{verbose} ;
		
		$indexer->remove_document_with_id($modules_out_of_date->{$module_to_remove}{$module_element})   ;
		}
		
	if ($options->{verbose})
		{
		printf
			"\t[$module_index/$number_of_modules ($number_of_files_in_module) in %.3f s.]\n",
			(time - $t0_remove_module)  ;
		}
	}

if ($options->{verbose})
	{
	printf "[Removed $total_number_of_files files in $number_of_modules modules in %.3f s.]\n", (time - $t0_remove) ; 
	}
}

#----------------------------------------------------------------------------------------------------------

sub add_new_modules
{

=head2 ( )

  some code

I<Arguments>

=over 2 

=item * $ - 

=back

I<Returns> - Nothing

I<Exceptions> - None

=cut

my ($indexer, $cpan_mini, $new_modules, $options) = @_ ;

my $module_index = 0 ;
my $total_number_of_files = 0 ;
my $number_of_modules = scalar(keys %{$new_modules}) ;

my $one_warning = 0 ;
local $SIG{__WARN__} = get_sig_warn_sub(\$one_warning) ;

my $t0_add_modules = time;

for my $module (sort keys %{$new_modules})
	{
	my $t0_module = time ;
	
	$one_warning = 0 ;
	$module_index++ ;
	
	(my $module_to_add_short = $module) =~ s{^$cpan_mini/}[] ;
	print "+$module_to_add_short\n" ;

	my $directory = File::Temp->newdir() ;
	my $extraction_directory = $directory->dirname;

	my $next_archive_item = Archive::Tar->iter($module, 1);

	while(my $item = $next_archive_item->()) 
		{
		my $item_name = $item->name() ;
		$item->extract("$extraction_directory/$item_name") 
			or carp "Error: failed Extracting '$item_name' from '$module'!\n";
		}	
	
	my @files = File::Find::Rule->file()->name( '*.pod', '*.pl', '*.pm')->in($extraction_directory);

	my $number_of_files_in_module = scalar(@files) ;
	$total_number_of_files += $number_of_files_in_module ;
	
	my $t0_index = time ;
	
	for my $file (@files)
		{
		(my $file_short = $file) =~ s{^/tmp/[^/]+/}{} ;
		print "\t+$file_short\n" if ($options->{verbose}) ;
			
		$indexer->add_files
			(
			FILES => [map { {NAME => $_, DESCRIPTION => $module_to_add_short} } $file],
			MAXIMUM_DOCUMENT_SIZE => $options->{maximum_document_size},
			) ;
		}
		
	if ($options->{verbose})
		{
		printf
			"\t[$module_index/$number_of_modules ($number_of_files_in_module) in "
			. "%.3f s. (indexing: %.3f s.)]\n",
			(time - $t0_module), (time - $t0_index)  ;
		}
	}
	
if ($options->{verbose})
	{
	print {*STDOUT} 
		pluralize("[Re-indexed $total_number_of_files file(s) in ", $total_number_of_files),
		pluralize("$number_of_modules module(s) in ", $number_of_modules),
		sprintf("%.3f s.]\n", (time - $t0_add_modules)) ;
	}
}

#----------------------------------------------------------------------------------------------------------

sub get_sig_warn_sub
{

=head2 ( )

  some code

I<Arguments>

=over 2 

=item * $ - 

=back

I<Returns> - Nothing

I<Exceptions> - None

=cut

my ($one_warning) = @_ ;

return 
	sub
		{
		my ($warning) = @_ ;
		
		if
			(
			$warning =~ /^Invalid header block at offset unknown/
			|| $warning =~ /^Couldn't read chunk/
			|| $warning =~ /checksum error/
			)
			{
			if(! $$one_warning)
				{
				print "\tInvalid Archive!\n" ;
				$$one_warning++ ;
				}
			else
				{
				# ignore
				}
			}
		else
			{
			if($warning =~ m~'/tmp/.+?/(.+)' is bigger than .+ bytes, skipping!~)
				{
				print "\tSkipping '$1', too big!\n" ;
				}
			else
				{
				warn $warning ;
				}
			}
		} ;
}

#-------------------------------------------------------------------------------

1 ;

=head1 BUGS AND LIMITATIONS

None so far.

=head1 AUTHOR

	Nadim ibn hamouda el Khemir
	CPAN ID: NKH
	mailto: nadim@cpan.org

=head1 LICENSE AND COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CPAN::Mini::Indexed

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CPAN-Mini-Indexed>

=item * RT: CPAN's request tracker

Please report any bugs or feature requests to  L <bug-cpan-mini-indexed@rt.cpan.org>.

We will be notified, and then you'll automatically be notified of progress on
your bug as we make changes.

=item * Search CPAN

L<http://search.cpan.org/dist/CPAN-Mini-Indexed>

=back

=head1 SEE ALSO


=cut
