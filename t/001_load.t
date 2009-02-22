
use strict ;
use warnings ;

use Test::NoWarnings ;

use Test::More qw(no_plan);
use Test::Exception ;
#use Test::UniqueTestNames ;

BEGIN { use_ok( 'CPAN::Mini::Indexed' ) or BAIL_OUT("Can't load module"); } ;

my $object = new CPAN::Mini::Indexed ;

is(defined $object, 1, 'default constructor') ;
isa_ok($object, 'CPAN::Mini::Indexed');

my $new_config = $object->new() ;
is(defined $new_config, 1, 'constructed from object') ;
isa_ok($new_config , 'CPAN::Mini::Indexed');

dies_ok
	{
	CPAN::Mini::Indexed::new () ;
	} "invalid constructor" ;
