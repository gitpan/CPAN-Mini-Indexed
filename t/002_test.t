# test

use strict ;
use warnings ;

use Test::Exception ;
use Test::Warn;
use Test::NoWarnings qw(had_no_warnings);

use Test::More 'no_plan';
#use Test::UniqueTestNames ;

use Test::Block qw($Plan);

use CPAN::Mini::Indexed ;

{
local $Plan = {'' => 1} ;


throws_ok
	{
	}
	qr//, 'failed' ;
}

#~ create a mini cpan
#~ index files
#~ change file
#~ re index
#~ remove file
#~ re index
#~ add file
#~ re index
