use Test::Strict;
$Test::Strict::TEST_SKIP  = [ 'lib/MediaWords/CommonLibs.pm' ];

all_perl_files_ok( 'lib', 'script' );    # Syntax ok and use strict;
