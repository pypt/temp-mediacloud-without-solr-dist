package MediaWords::Job::ExtractAndVector;

#
# Extract and vector a download
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/ExtractAndVector.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/mjm_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories::ExtractorArguments;

# Extract, vector, and process the download or story; LOGDIE() and / or return
# false on error.
#
# Arguments:
# * stories_id OR downloads_id -- story ID or download ID to extract
# * (optional) extractor_method -- extractor method to use (e.g. "PythonReadability")
# * (optional) disable_story_triggers -- disable triggers on "stories" table
#              (probably skips updating db_row_last_updated?)
# * (optional) skip_bitly_processing -- don't add extracted story to the Bit.ly
#              processing queue
# * (optional) skip_corenlp_annotation -- don't add extracted story to the
#              CoreNLP annotation queue
sub run($$)
{
    my ( $self, $args ) = @_;

    unless ( $args->{ downloads_id } xor $args->{ stories_id } )    # "xor", not "or"
    {
        LOGDIE "Either 'downloads_id' or 'stories_id' should be set (but not both).";
    }

    my $db = MediaWords::DB::connect_to_db();
    $db->dbh->{ AutoCommit } = 0;

    if ( exists $args->{ disable_story_triggers } and $args->{ disable_story_triggers } )
    {
        $db->query( "SELECT disable_story_triggers(); " );
        MediaWords::DB::disable_story_triggers();
    }
    else
    {
        $db->query( "SELECT enable_story_triggers(); " );
        MediaWords::DB::enable_story_triggers();
    }

    my $extractor_args = MediaWords::DBI::Stories::ExtractorArguments->new(
        {
            # If unset, will fallback to default extractor method set in configuration
            extractor_method => $args->{ extractor_method },

            skip_bitly_processing   => $args->{ skip_bitly_processing },
            skip_corenlp_annotation => $args->{ skip_corenlp_annotation },
        }
    );

    eval {

        if ( $args->{ downloads_id } )
        {
            my $downloads_id = $args->{ downloads_id };
            unless ( defined $downloads_id )
            {
                LOGDIE "'downloads_id' is undefined.";
            }

            my $download = $db->find_by_id( 'downloads', $downloads_id );
            unless ( $download->{ downloads_id } )
            {
                LOGDIE "Download with ID $downloads_id was not found.";
            }

            MediaWords::DBI::Downloads::process_download_for_extractor_and_record_error( $db, $download, $extractor_args );
        }
        elsif ( $args->{ stories_id } )
        {
            my $stories_id = $args->{ stories_id };
            unless ( defined $stories_id )
            {
                LOGDIE "'stories_id' is undefined.";
            }

            my $story = $db->find_by_id( 'stories', $stories_id );
            unless ( $story->{ stories_id } )
            {
                LOGDIE "Download with ID $stories_id was not found.";
            }

            MediaWords::DBI::Stories::extract_and_process_story( $db, $story, $extractor_args );
        }

        # Enable story triggers in case the connection is reused due to connection pooling
        $db->query( "SELECT enable_story_triggers(); " );
    };

    my $error_message = "$@";

    if ( $error_message )
    {
        # Probably the download was not found
        LOGDIE "Extractor died: $error_message; job args: " . Dumper( $args );
    }

    return 1;
}

# run extraction for the crawler. run in process of mediawords.extract_in_process is configured.
# keep retrying on error.
sub extract_for_crawler($$$)
{
    my ( $self, $db, $args ) = @_;

    if ( MediaWords::Util::Config::get_config->{ mediawords }->{ extract_in_process } )
    {
        DEBUG "extracting in process...";
        MediaWords::Job::ExtractAndVector->run( $args );
    }
    else
    {
        while ( 1 )
        {
            eval { MediaWords::Job::ExtractAndVector->add_to_queue( $args ); };

            if ( $@ )
            {
                warn( "extractor job queue failed.  sleeping and trying again in 5 seconds: $@" );
                sleep 5;
            }
            else
            {
                last;
            }
        }
        DEBUG "queued extraction";
    }
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
