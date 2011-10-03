package MediaWords::StoryVectors;

# methods to generate the story_sentences and story_sentence_words and associated aggregated tables

use strict;
use Encode;
use Encode::HanConvert;
use Perl6::Say;
use Lingua::ZH::WordSegmenter;
use Data::Dumper;

use Lingua::EN::Sentence::MediaWords;
use Lingua::ZH::MediaWords;
use MediaWords::DBI::Stories;
use MediaWords::Util::SQL;
use MediaWords::Util::Stemmer;
use MediaWords::Util::StopWords;
use MediaWords::Util::Countries;

use Date::Format;
use Date::Parse;
use utf8;

# minimum length of words in story_sentence_words
use constant MIN_STEM_LENGTH => 3;

# if story is a ref, return itself, otherwise treat it as a stories_id and query for the story ref
sub _get_story
{
    my ( $db, $story ) = @_;

    if ( ref( $story ) )
    {
        return $story;
    }
    else
    {
        return $db->query( "select stories_id, publish_date, media_id from stories where stories_id = ?", $story )->hash;
    }
}

# given a hash of word counts by sentence, insert the words into the db
sub _insert_story_sentence_words
{
    my ( $db, $story, $word_counts ) = @_;

    while ( my ( $sentence_num, $sentence_counts ) = each( %{ $word_counts } ) )
    {
        eval {
            $db->dbh->do(
"copy story_sentence_words (stories_id, stem_count, sentence_number, stem, term, publish_day, media_id) from STDIN"
            );
            while ( my ( $stem, $hash ) = each( %{ $sentence_counts } ) )
            {

#print STDERR $story->{ stories_id }.$hash->{ count }.$sentence_num.encode_utf8( $stem ).encode_utf8( lc( $hash->{ word } ) ).$story->{ publish_date }.$story->{ media_id };
#print STDERR "\n";

                eval {

                    $db->dbh->pg_putcopydata(
                        $story->{ stories_id } . "\t" . $hash->{ count } . "\t" . $sentence_num . "\t" .
                          encode_utf8( $stem ) . "\t" . encode_utf8( lc( $hash->{ word } ) ) . "\t" .
                          $story->{ publish_date } . "\t" . $story->{ media_id } . "\n" );

                };
                if ( $@ )
                {
                    print STDERR "Error inserting into story_sentence_words\n";
                    die $@;
                }
            }
            $db->dbh->pg_putcopyend();
        };

        if ( $@ )
        {
            print STDERR "Error inserting into story_sentence_words\n";
            die $@;
        }

    }
}

# return 1 if the stem passes various tests
sub _valid_stem
{
    my ( $stem, $word, $stop_stems ) = @_;

    return ( $stem
          && ( length( $stem ) >= MIN_STEM_LENGTH )
          && ( !$stop_stems->{ $stem } )
          && ( $word !~ /[^[:print:]]/ )
          && ( $word =~ /[^[:digit:][:punct:]]/ ) );
}

# insert the story sentence into the db
sub _insert_story_sentence
{
    my ( $db, $story, $sentence_num, $sentence ) = @_;

    $db->query(
        "insert into story_sentences (stories_id, sentence_number, sentence, publish_date, media_id) " .
          "  values (?,?,?,?,?)",
        $story->{ stories_id },
        $sentence_num, $sentence,
        $story->{ publish_date },
        $story->{ media_id }
    );
}

# simple tokenizer
sub _tokenize
{
    my ( $s ) = @_;

    my $tokens = [];
    while ( $s->[ 0 ] =~ m~(\w[\w']*)~g )
    {
        push( @{ $tokens }, lc( $1 ) );
    }

    return $tokens;
}

#Chinese tokenizer, returns an array of Chinese words
sub _tokenize_ZH
{
    my $s         = shift;
    my $segmenter = shift;
    my $i;
    $s = encode( "utf8", $s );
    my $segs = $segmenter->seg( $s, "utf8" );
    my $tokens;
    @$tokens = split( / /, $segs );
    my $token;

    foreach $token ( @$tokens )
    {
        $token =~ s/[\W\d_\s]+//g;
    }

    for ( $i = 0 ; $i < $#$tokens ; $i++ )
    {
        if ( $tokens->[ $i ] eq "" )
        {
            splice @$tokens, $i, 1;
            $i--;
        }
    }

    #foreach $token ( @$tokens )
    #{
    #    print $token. "\n";
    #}
    return $tokens;
}

# if the length of the string is greater than the given length, cut to that length
sub limit_string_length
{

    # my ( $s, $l ) = @_;

    if ( length( $_[ 0 ] ) > $_[ 1 ] )
    {
        substr( $_[ 0 ], $_[ 1 ] ) = '';
    }
}

# return the number of sentences of this sentence within the same media source and calendar week.
# also adds the sentence to the story_sentence_counts table and/or increments the count in that table
# for the sentence.
#
# NOTE: you must wrap a 'lock story_sentence_counts in row exclusive mode' around all calls to this within the
# same transaction to avoid deadlocks
#
# NOTE ALSO: There is a known concurrency issue if this function is called by multiple threads see #1599
# However, we have determined that the issue is rare enough in practice that it is not of particular concern.
# So we have decided to simply leave things in place as they are rather than risk the performance and code complexity issues
# of ensuring atomic updates.
#
sub count_duplicate_sentences
{
    my ( $db, $sentence, $sentence_number, $story ) = @_;

    my $dup_sentence = $db->query(
        "select * from story_sentence_counts " .
          "  where sentence_md5 = md5( ? ) and media_id = ? and publish_week = date_trunc( 'week', ?::date )" .
          "  order by story_sentence_counts_id limit 1",
        $sentence,
        $story->{ media_id },
        $story->{ publish_date }
    )->hash;

    if ( $dup_sentence )
    {
        $db->query(
            "update story_sentence_counts set sentence_count = sentence_count + 1 " . "  where story_sentence_counts_id = ?",
            $dup_sentence->{ story_sentence_counts_id }
        );
        return $dup_sentence->{ sentence_count };
    }
    else
    {
        $db->query(
            "insert into story_sentence_counts( sentence_md5, media_id, publish_week, " .
              "    first_stories_id, first_sentence_number, sentence_count ) " .
              "  values ( md5( ? ), ?, date_trunc( 'week', ?::date ), ?, ?, 1 )",
            $sentence,
            $story->{ media_id },
            $story->{ publish_date },
            $story->{ stories_id },
            $sentence_number
        );
        return 0;
    }
}

# given a story and a list of sentences, return all of the stories that are not duplicates as defined by
# count_duplicate_sentences()
sub dedup_sentences
{
    my ( $db, $story, $sentences ) = @_;

    if ( !$db->dbh->{ AutoCommit } )
    {
        $db->query( "lock table story_sentence_counts in row exclusive mode" );
    }

    my $deduped_sentences = [];
    for my $sentence ( @{ $sentences } )
    {
        my $num_dups = count_duplicate_sentences( $db, $sentence, scalar( @{ $deduped_sentences } ), $story );

        if ( $num_dups == 0 )
        {
            push( @{ $deduped_sentences }, $sentence );
        }
        else
        {

            # print STDERR "ignoring duplicate sentence: '$sentence'\n";
        }
    }

    $db->commit;

    if ( @{ $sentences } && !@{ $deduped_sentences } )
    {

        # FIXME - should do something here to find out if this is just a duplicate story and
        # try to merge the given story with the existing one
        print STDERR "all sentences deduped for stories_id $story->{ stories_id }\n";
    }

    return $deduped_sentences;
}

sub _story_within_media_source_story_words_data_range
{
    my ( $db, $story ) = @_;

    return 1;
}

# update story vectors for the given story, updating story_sentences and story_sentence_words
# if no_delete is true, do not try to delete existing entries in the above table before creating new ones (useful for optimization
# if you are very sure no story vectors exist for this story).
sub update_story_sentence_words
{
    my ( $db, $story_ref, $no_delete ) = @_;
    my $sentence_word_counts;
    my $story = _get_story( $db, $story_ref );

    unless ( $no_delete )
    {
        $db->query( "delete from story_sentence_words where stories_id = ?",        $story->{ stories_id } );
        $db->query( "delete from story_sentences where stories_id = ?",             $story->{ stories_id } );
        $db->query( "delete from story_sentence_counts where first_stories_id = ?", $story->{ stories_id } );
    }

    return if ( ! _story_within_media_source_story_words_data_range ( $db, $story ) );

    my $story_text = MediaWords::DBI::Stories::get_text_for_word_counts( $db, $story );

    my $enable_chinese_support = MediaWords::Util::Config::get_config->{ mediawords }->{ enable_chinese_language_support }
      || 'no';

    my $is_Chinese = 0;

    if ( $enable_chinese_support eq 'yes' && Lingua::ZH::MediaWords::text_is_Chinese( $story_text ) )
    {
        $is_Chinese = 1;
    }

    #if the text is in Chinese
    if ( $is_Chinese )
    {

        my $base_dir;

        BEGIN
        {
            use File::Basename ();
            use Cwd            ();

            my $relative_path = '../..';    # Path to base of project relative to the current file
            $base_dir = Cwd::realpath( File::Basename::dirname( __FILE__ ) . '/' . $relative_path );
        }

        my %par = ();
        $par{ "dic_encoding" } = "utf8";
        $par{ "dic" }          = "$base_dir/lib/Lingua/ZH/dict.txt";
        my $segmenter = Lingua::ZH::WordSegmenter->new( %par );

        #convert traditional characters into simplified characters
        $story_text = trad_to_simp( $story_text );

        my $sentences = Lingua::ZH::MediaWords::get_sentences( $story_text );
        $sentences = dedup_sentences( $db, $story_ref, $sentences );
        my $stop_words = MediaWords::Util::StopWords::get_Chinese_stopwords();
        my $count      = 0;

        for ( my $sentence_num = 0 ; $sentence_num < $#$sentences ; $sentence_num++ )
        {
            my $words = _tokenize_ZH( $sentences->[ $sentence_num ], $segmenter );

            #print $sentences[$sentence_num]."\n\n----------\n";
            #print join "\n\n", @words;
            for ( my $word_num = 0 ; $word_num < $#$words ; $word_num++ )
            {
                my $word = ( $words->[ $word_num ] );

                if ( ( !$$stop_words{ $word } ) )
                {
                    $sentence_word_counts->{ $sentence_num }->{ $word }->{ word } ||= $word;
                    $sentence_word_counts->{ $sentence_num }->{ $word }->{ count }++;
                }
            }
            _insert_story_sentence( $db, $story, $sentence_num, $sentences->[ $sentence_num ] );
        }

    }

    #if the text is in English
    else
    {
        my $stop_stems = MediaWords::Util::StopWords::get_tiny_stop_stem_lookup();
        my $stemmer    = MediaWords::Util::Stemmer->new;
        my $sentences  = Lingua::EN::Sentence::MediaWords::get_sentences( $story_text ) || return;
        $sentences = dedup_sentences( $db, $story_ref, $sentences );

        for ( my $sentence_num = 0 ; $sentence_num < @{ $sentences } ; $sentence_num++ )
        {
            my $words = _tokenize( [ $sentences->[ $sentence_num ] ] );
            my $stems = $stemmer->stem( @{ $words } );

            for ( my $word_num = 0 ; $word_num < @{ $words } ; $word_num++ )
            {
                my ( $word, $stem ) = ( $words->[ $word_num ], $stems->[ $word_num ] );

                limit_string_length( $word, 256 );
                limit_string_length( $stem, 256 );

                if ( _valid_stem( $stem, $word, $stop_stems ) )
                {
                    $sentence_word_counts->{ $sentence_num }->{ $stem }->{ word } ||= $word;
                    $sentence_word_counts->{ $sentence_num }->{ $stem }->{ count }++;
                }
            }

            _insert_story_sentence( $db, $story, $sentence_num, $sentences->[ $sentence_num ] );
        }
    }

    _insert_story_sentence_words( $db, $story, $sentence_word_counts );

    #testing print
    q{while ( my ($key, $value) = each(%$sentence_word_counts) ) {
		 	print "level 1:  $key\n";
			while ( my ($key, $value1) = each(%$value) ) {
       				 print "*level 2:  $key\n";
				while ( my ($key, $value2) = each(%$value1) ) {
		   				 print "**level 3:  $key => $value2\n";
	   			 }
   			}
	 }};
}

# fill the story_sentence_words table with all stories in ssw_queue
sub fill_story_sentence_words
{
    my ( $db ) = @_;

    my $block_size = 1;

    my $count = 0;
    while ( my $stories = $db->query( "select * from ssw_queue order by stories_id limit $block_size" )->hashes )
    {
        if ( !@{ $stories } )
        {
            last;
        }

        for my $story ( @{ $stories } )
        {
            say STDERR "story [ $story->{ stories_id } ] " . ++$count . " ...";

            update_story_sentence_words( $db, $story, 0 );

            $db->query( "delete from ssw_queue where stories_id = ?", $story->{ stories_id } );
        }
        $db->commit();
    }
}

# return a where clause that restricts the media_sets_id to the given media_sets_id or else
# adds no restriction at all if the media_sets_id is not defined
sub _get_media_set_clause
{
    my ( $media_sets_id ) = @_;

    if ( !defined( $media_sets_id ) )
    {
        return '1=1';
    }
    else
    {
        return "media_sets_id = $media_sets_id";
    }
}

# return a where clause that restricts the dashboard_topics_id to the given dashboard_topics_id or else
# adds no restriction at all if the dashboard_topics_id is not defined
sub _get_dashboard_topic_clause
{
    my ( $dashboard_topics_id ) = @_;

    if ( !defined( $dashboard_topics_id ) )
    {
        return '1=1';
    }
    else
    {
        return "dashboard_topics_id = $dashboard_topics_id";
    }
}

# return media_set and dashboard_topic update clauses
sub _get_update_clauses
{
    my ( $dashboard_topics_id, $media_sets_id ) = @_;

    my $d = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $m = _get_media_set_clause( $media_sets_id );

    return "and $d and $m";
}

#
sub _update_total_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: total_weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        "delete from total_weekly_words where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses" );

    $db->query(
"INSERT INTO total_weekly_words(media_sets_id, dashboard_topics_id, publish_week, total_count) select media_sets_id, dashboard_topics_id, publish_week, sum(stem_count) as total_count from weekly_words where  publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses group by media_sets_id, dashboard_topics_id, publish_week  order by publish_week asc, media_sets_id, dashboard_topics_id "
    );
}

# update the top_500_weekly_words table with the 500 most common stop worded stems for each media_sets_id each week
sub _update_top_500_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: top_500_weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        "delete from top_500_weekly_words where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses" );
    $db->query(
        "delete from total_top_500_weekly_words where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses"
    );

    #TODO figure out if regexp_replace( term, E'''s?\\\\Z', '' ) is really necessary

    # Note in postgresql [:alpha:] doesn't include international characters.
    # [^[:digit:][:punct:][:cntrl:][:space:]] is the closest equivalent to [:alpha:] to include international characters
    $db->query(
        "insert into top_500_weekly_words (media_sets_id, term, stem, stem_count, publish_week, dashboard_topics_id) " .
          "  select media_sets_id, regexp_replace( term, E'''s?\\\\Z', '' ), " .
          "      stem, stem_count, publish_week, dashboard_topics_id " . "    from ( " .
          "      select media_sets_id, term, stem, stem_count, publish_week, dashboard_topics_id, " .
          "          rank() over ( partition by media_sets_id, dashboard_topics_id order by stem_count desc ) as stem_rank  "
          . "      from weekly_words "
          . "      where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses "
          . "        and not is_stop_stem( 'long', stem ) and stem ~ '[^[:digit:][:punct:][:cntrl:][:space:]]' ) q "
          . "    where stem_rank < 500 "
          . "    order by stem_rank asc " );

    $db->query( "insert into total_top_500_weekly_words (media_sets_id, publish_week, total_count, dashboard_topics_id) " .
          "  select media_sets_id, publish_week, sum( stem_count ), dashboard_topics_id from top_500_weekly_words " .
          "    where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses " .
          "    group by media_sets_id, publish_week, dashboard_topics_id" );
}

# update the top_500_weekly_author_words table with the 500 most common stop worded stems for each media_sets_id each week
sub _update_top_500_weekly_author_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    return if ( $dashboard_topics_id || $media_sets_id );

    say STDERR "aggregate: top_500_weekly_author_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
"delete from top_500_weekly_author_words where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses"
    );
    $db->query(
"delete from total_top_500_weekly_author_words where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses"
    );

    # Note in postgresql [:alpha:] doesn't include international characters.
    # [^[:digit:][:punct:][:cntrl:][:space:]] is the closest equivalent to [:alpha:] to include international characters
    $db->query(
        "insert into top_500_weekly_author_words (media_sets_id, term, stem, stem_count, publish_week, authors_id) " .
          "  select media_sets_id, regexp_replace( term, E'''s?\\\\Z', '' ), " .
          "      stem, stem_count, publish_week, authors_id " . "    from ( " .
          "      select media_sets_id, term, stem, stem_count, publish_week, authors_id, " .
          "          rank() over ( partition by media_sets_id, authors_id order by stem_count desc ) as stem_rank  " .
          "      from weekly_author_words " .
          "      where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses " .
          "        and not is_stop_stem( 'long', stem ) and stem ~ '[^[:digit:][:punct:][:cntrl:][:space:]]' ) q " .
          "    where stem_rank < 500 " . "    order by stem_rank asc " );

    $db->query( "insert into total_top_500_weekly_author_words (media_sets_id, publish_week, total_count, authors_id) " .
          "  select media_sets_id, publish_week, sum( stem_count ), authors_id from top_500_weekly_author_words " .
          "    where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses " .
          "    group by media_sets_id, publish_week, authors_id" );
}

sub _update_daily_stories_counts
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: update_daily_stories_counts $sql_date";

    my $dashboard_topic_clause = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $media_set_clause       = _get_media_set_clause( $media_sets_id );
    my $update_clauses         = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query( "delete from daily_story_count where publish_day = '${ sql_date }'::date $update_clauses" );

    #$db->query( "delete from daily_words where publish_day = '${ sql_date }'::date $update_clauses" );
    #$db->query(
    #    "delete from total_daily_words where publish_day = '${ sql_date }'::date $update_clauses" );

    if ( !$dashboard_topics_id )
    {

        my $sql =
          "insert into daily_story_count (media_sets_id, dashboard_topics_id, publish_day, story_count) " .
          "                     select media_sets_id, null as dashboard_topics_id,  " .
          "                      min(publish_day) as publish_day, count(*) as story_count" .
          "                      from story_sentence_words ssw, media_sets_media_map msmm  " .
          "                      where ssw.publish_day = '${sql_date}'::date and " .
          "                      ssw.media_id = msmm.media_id and  $media_set_clause " .
          "                      group by msmm.media_sets_id, ssw.publish_day ";

        $db->query( $sql );

    }

}

# update the given table for the given date and interval
sub _update_daily_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: daily_words $sql_date";

    my $dashboard_topic_clause = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $media_set_clause       = _get_media_set_clause( $media_sets_id );
    my $update_clauses         = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query( "delete from daily_words where publish_day = '${ sql_date }'::date $update_clauses" );
    $db->query( "delete from total_daily_words where publish_day = '${ sql_date }'::date $update_clauses" );

    if ( !$dashboard_topics_id )
    {
        $db->query( "insert into daily_words (media_sets_id, term, stem, stem_count, publish_day, dashboard_topics_id) " .
              "          select media_sets_id, term, stem, sum_stem_counts, publish_day, null from " .
              "               (select  *, rank() over (w order by stem_count_sum desc, term desc) as term_rank, " .
              "                sum(stem_count_sum) over w as sum_stem_counts  from " .
              "                    ( select media_sets_id, term, stem, sum(stem_count) as stem_count_sum, " .
              "                      min(publish_day) as publish_day, null " .
              "                      from story_sentence_words ssw, media_sets_media_map msmm  " .
              "                      where ssw.publish_day = '${sql_date}'::date and " .
              "                      ssw.media_id = msmm.media_id and  $media_set_clause " .
              "                      group by msmm.media_sets_id, ssw.stem, ssw.term " .
              "                        ) as foo  " .
              "                WINDOW w  as (partition by media_sets_id, stem, publish_day ) " .
              "	               )  q                                                         " .
              "              where term_rank = 1 " );
    }

    my $dashboard_topics = $db->query( "select * from dashboard_topics where 1=1 and $dashboard_topic_clause" )->hashes;

    for my $dashboard_topic ( @{ $dashboard_topics } )
    {
        my $query_2 =
          "    insert into daily_words (media_sets_id, term, stem, stem_count, publish_day, dashboard_topics_id) " .
          "          select media_sets_id, term, stem, sum_stem_counts, publish_day, dashboard_topics_id from " .
          "               (select  *, rank() over (w order by stem_count_sum desc, term desc) as term_rank, " .
          "                sum(stem_count_sum) over w as sum_stem_counts  from " .
          " ( select media_sets_id, ssw.term, ssw.stem, sum(ssw.stem_count) stem_count_sum,    " .
          "  min(ssw.publish_day) as publish_day, ?::integer as dashboard_topics_id  from " .
          "     story_sentence_words ssw,                                                          " .
          "( select media_sets_id, stories_id, sentence_number from story_sentence_words sswq, media_sets_media_map msmm " .
          " where                                                           " .
          " sswq.media_id = msmm.media_id and sswq.stem = ? and sswq.publish_day = ? and " .
          " $media_set_clause  group by msmm.media_sets_id, stories_id, sentence_number " .
          " ) as ssw_sentences_for_query  " . " where ssw.stories_id=ssw_sentences_for_query.stories_id and " .
          " ssw.sentence_number=ssw_sentences_for_query.sentence_number " . " group by media_sets_id, ssw.stem, term " .
          "                        ) as foo  " .
          "                WINDOW w  as (partition by media_sets_id, stem, publish_day ) " .
          "	               )  q                                                         " .
          "             where term_rank = 1 ";

        # doing these one by one is the only way I could get the postgres planner to create
        # a sane plan
        $db->query( $query_2, $dashboard_topic->{ dashboard_topics_id }, $dashboard_topic->{ query }, $sql_date );
    }

    $db->query( "insert into total_daily_words (media_sets_id, publish_day, total_count, dashboard_topics_id) " .
          " select media_sets_id, publish_day, sum(stem_count), dashboard_topics_id " . " from daily_words " .
          " where publish_day = '${sql_date}'::date $update_clauses " .
          " group by media_sets_id, publish_day, dashboard_topics_id " );

    return 1;
}

# update the given table for the given date and interval
sub _update_daily_author_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    return if ( $dashboard_topics_id || $media_sets_id );

    say STDERR "aggregate: update_daily_author_words $sql_date";

    my $dashboard_topic_clause = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $media_set_clause       = _get_media_set_clause( $media_sets_id );
    my $update_clauses         = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $update_clauses = '';

    $db->query(
        "delete from daily_author_words where publish_day = date_trunc( 'day', '${ sql_date }'::date ) $update_clauses" );

    $db->query(
        "delete from total_daily_author_words where publish_day = date_trunc( 'day', '${ sql_date }'::date ) $update_clauses"
    );

    my $query = <<"END_SQL";
INSERT INTO daily_author_words( authors_id     , media_sets_id  , term, stem, stem_count, publish_day)
SELECT authors_id     , media_sets_id  , term, stem, sum_stem_counts, publish_day
FROM   (SELECT  *                                                                   ,
                rank() over (w ORDER BY stem_count_sum DESC, term DESC) AS term_rank,
                SUM(stem_count_sum) over w                              AS sum_stem_counts
       FROM     ( SELECT  authors_id, media_sets_id, term, stem, SUM(stem_count)  AS stem_count_sum,
                         MIN(publish_day) AS publish_day, NULL
                FROM     story_sentence_words ssw, media_sets_media_map msmm, authors_stories_map
                WHERE    ssw.publish_day = '${sql_date}'::DATE AND  ssw.stories_id  =authors_stories_map.stories_id
                AND      ssw.media_id    = msmm.media_id
                GROUP BY msmm.media_sets_id, ssw.stem, ssw.term, authors_id
                ) AS foo WINDOW w AS (partition BY media_sets_id, stem, publish_day )
       )
       query
WHERE  term_rank       = 1
AND    sum_stem_counts > 1
END_SQL

    $db->query( $query );

    say STDERR "Completed query $query";

    $db->query( "insert into total_daily_author_words (authors_id, media_sets_id, publish_day, total_count) " .
          " select authors_id, media_sets_id, publish_day, sum(stem_count)    " . " from daily_author_words " .
          " where publish_day = '${sql_date}'::date $update_clauses " .
          " group by authors_id, media_sets_id, publish_day " );

    return 1;
}

# update the given table for the given date and interval
sub _update_daily_country_counts
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    return 1 if ( $dashboard_topics_id );

    my $media_set_clause = _get_media_set_clause( $media_sets_id );

    $db->query( "delete from daily_country_counts where publish_day = '${ sql_date }'::date and $media_set_clause" );

    my $all_countries = MediaWords::Util::Countries::get_countries_for_counts();

    my $stemmed_country_terms = [ map { MediaWords::Util::Countries::get_stemmed_country_terms( $_ ) } @{ $all_countries } ];

    my $single_terms_list =
      join( ',', map { $db->dbh->quote( $_->[ 0 ] ) } grep { @{ $_ } == 1 } @{ $stemmed_country_terms } );

    $db->query( "insert into daily_country_counts( media_sets_id, publish_day, country, country_count ) " .
          "  select media_sets_id, publish_day, stem, stem_count from daily_words " .
          "    where publish_day = '$sql_date'::date and dashboard_topics_id is null and $media_set_clause" .
          "      and stem in ( $single_terms_list )" );

    my $double_country_terms = [ grep { @{ $_ } == 2 } @{ $stemmed_country_terms } ];

    for my $country ( @{ $double_country_terms } )
    {
        my $country_name = join( " ", @{ $country } );
        my ( $term_a, $term_b ) = map { $db->dbh->quote( $_ ) } @{ $country };

        $db->query(
            "insert into daily_country_counts ( media_sets_id, publish_day, country, country_count ) " .
              "  select msmm.media_sets_id, ssw.publish_day, ?, count(*) " .
              "    from story_sentence_words ssw, media_sets_media_map msmm " .
              "    where ssw.media_id = msmm.media_id and ssw.publish_day = '$sql_date'::date " .
              "      and stem = $term_a and exists " .
              "        ( select 1 from story_sentence_words sswb where ssw.publish_day = sswb.publish_day " .
              "              and ssw.media_id = sswb.media_id and sswb.stem = $term_b " .
              "              and ssw.stories_id = sswb.stories_id and ssw.sentence_number = sswb.sentence_number ) " .
              "   group by msmm.media_sets_id, ssw.publish_day",
            $country_name
        );
    }

    return 1;
}

# get quoted, comma separate list of the dates in the week starting with
# the given date
sub _get_week_dates_list
{
    my ( $start_date ) = @_;

    my $dates = [ $start_date ];
    for my $i ( 1 .. 6 )
    {
        push( @{ $dates }, MediaWords::Util::SQL::increment_day( $start_date, $i ) );
    }

    return join( ',', map { "'$_'::date" } @{ $dates } );
}

# update the given table for the given date and interval
sub _update_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    my ( $week_start_date ) = $db->query( " SELECT  date_trunc( 'week', '${ sql_date }'::date ) " )->flat;

    $sql_date = $week_start_date;

    # use an in list of dates instead of sql between b/c postgres is really slow using
    # between for dates
    my $week_dates = _get_week_dates_list( $sql_date );

    $db->query( "delete from weekly_words where publish_week = '${ sql_date }'::date  $update_clauses " );

    my $query =
      "insert into weekly_words (media_sets_id, term, stem, stem_count, publish_week, dashboard_topics_id) " .
      "  select media_sets_id, term, stem, sum_stem_counts, publish_week, dashboard_topics_id from      " .
      "   (select  *, rank() over (w order by stem_count_sum desc, term desc) as term_rank, " .
      "     sum(stem_count_sum) over w as sum_stem_counts  from " .
      "(  select media_sets_id, term, stem, sum(stem_count) as stem_count_sum, " .
      " '${ sql_date }'::date as publish_week, dashboard_topics_id from daily_words " .
      "    where publish_day in ( $week_dates ) $update_clauses " .
      "    group by media_sets_id, stem, term, dashboard_topics_id ) as foo" .
      " WINDOW w  as (partition by media_sets_id, stem, publish_week,  dashboard_topics_id  ) " .
      "	               )  q                                                         " . "              where term_rank = 1 ";

    #say STDERR "query:\n$query";
    $db->query( $query );

    return 1;
}

# update the given table for the given date and interval
sub _update_weekly_author_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    return if ( $dashboard_topics_id || $media_sets_id );

    say STDERR "aggregate: weekly_author_words $sql_date";

    #TODO get rid of dashboards_id from this query
    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        "delete from weekly_author_words where publish_week = date_trunc( 'week', '${ sql_date }'::date ) $update_clauses "
    );

    my $query =
      "insert into weekly_author_words (authors_id, media_sets_id, term, stem, stem_count, publish_week) " .
      "  select authors_id, media_sets_id, term, stem, sum_stem_counts, publish_week from      " .
      "   (select  *, rank() over (w order by stem_count_sum desc, term desc) as term_rank, " .
      "     sum(stem_count_sum) over w as sum_stem_counts  from " .
      "(  select media_sets_id, term, stem, sum(stem_count) as stem_count_sum, " .
      "date_trunc('week', min(publish_day)) as publish_week, authors_id from daily_author_words " .
      "    where publish_day between date_trunc('week', '${sql_date}'::date) " .
      "        and date_trunc( 'week', '${sql_date}'::date )  + interval '6 days' $update_clauses " .
      "    group by media_sets_id, stem, term, authors_id ) as foo" .
      " WINDOW w  as (partition by media_sets_id, stem, publish_week, authors_id  ) " .
      "	               )  q                                                         " . "              where term_rank = 1 ";

    say STDERR "running  weekly_author_words query:$query";

    $db->query( $query );

    return 1;
}

# return true if the date exists in the daily_words table
sub _aggregate_data_exists_for_date
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    my $update_clauses;

    # specifically look for null dashboard_topics_id so that the aggregator doesn't
    # skip a daily run because a new topic has been added with data for just that topic
    # for the day
    if ( !$dashboard_topics_id )
    {
        $update_clauses = "and dashboard_topics_id is null";
        if ( $media_sets_id )
        {
            $update_clauses .= " and media_sets_id = $media_sets_id";
        }
    }
    else
    {
        $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );
    }

    return $db->query( "select 1 as c from daily_words " .
          "  where publish_day = date_trunc( 'day', date '$sql_date' ) $update_clauses limit 1" )->hash;
}

# add one day to the date in sql format
# use a postgres query to make sure we're doing the same thing as postgres, including dst
sub _increment_day
{
    my ( $date ) = @_;

    my $new_date = Date::Format::time2str( "%Y-%m-%d", Date::Parse::str2time( $date ) + 100000 );
}

#Convert the date to YYYY-MM-DD format is necessary and get rid of hours and minutes
sub _truncate_as_day
{
    my ( $date ) = @_;

    my $new_date = Date::Format::time2str( "%Y-%m-%d", Date::Parse::str2time( $date ) );

    return $new_date;
}

sub _date_is_sunday
{
    my ( $date ) = @_;

    return !( localtime( Date::Parse::str2time( $date ) ) )[ 6 ];
}

# update daily_words, weekly_words, and top_500_weekly_words tables for all included dates
# for which daily_words data does not already exist
#
# if dashbaord_topics_id or media_sets_id are specified, only update for the given
# dashboard_topic or media_set
sub update_aggregate_words
{
    my ( $db, $start_date, $end_date, $force, $dashboard_topics_id, $media_sets_id ) = @_;

    $start_date ||= '2008-06-01';
    $end_date ||= Date::Format::time2str( "%Y-%m-%d", time - 86400 );

    say STDERR "update_aggregate_words start_date: '$start_date' end_date:'$end_date' ";

    $start_date = _truncate_as_day( $start_date );
    $end_date   = _truncate_as_day( $end_date );

    my $days          = 0;
    my $update_weekly = 0;

    for ( my $date = $start_date ; $date le $end_date ; $date = _increment_day( $date ) )
    {
        say STDERR "update_aggregate_words: $date ($start_date - $end_date) $days";

        #_update_daily_stories_counts( $db, $date, $dashboard_topics_id, $media_sets_id );

        if ( $force || !_aggregate_data_exists_for_date( $db, $date, $dashboard_topics_id, $media_sets_id ) )
        {
            _update_daily_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_daily_country_counts( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_daily_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            $update_weekly = 1;
        }

        # update weeklies either if there was a daily update for the week and if we are at the end of the date range
        # or the end of a week
        if ( $update_weekly && ( ( $date eq $end_date ) || _date_is_sunday( $date ) ) )
        {
            _update_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_total_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_top_500_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );

            _update_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_top_500_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            $update_weekly = 0;
        }

        $db->commit();

        $days++;
    }

    $db->commit;
}

sub update_aggregate_author_words
{
    my ( $db, $start_date, $end_date, $force, $dashboard_topics_id, $media_sets_id ) = @_;

    $start_date ||= '2008-06-01';
    $end_date ||= Date::Format::time2str( "%Y-%m-%d", time - 86400 );

    $start_date = _truncate_as_day( $start_date );
    $end_date   = _truncate_as_day( $end_date );

    my $days          = 0;
    my $update_weekly = 0;

    for ( my $date = $start_date ; $date le $end_date ; $date = _increment_day( $date ) )
    {
        say STDERR "update_aggregate_words: $date ($start_date - $end_date) $days";

        $update_weekly = 1;

        {
            _update_daily_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
        }

        # update weeklies either if there was a daily update for the week and if we are at the end of the date range
        # or the end of a week
        if ( $update_weekly && ( ( $date eq $end_date ) || _date_is_sunday( $date ) ) )
        {
            {
                _update_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
                _update_top_500_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            }
            $update_weekly = 0;
        }

        $db->commit();

        $days++;
    }

    $db->commit;
}

# update daily_words, weekly_words, and top_500_weekly_words tables for all included dates
# for which daily_words data does not already exist
#
# if dashbaord_topics_id or media_sets_id are specified, only update for the given
# dashboard_topic or media_set
sub update_country_counts
{
    my ( $db, $start_date, $end_date, $force, $dashboard_topics_id, $media_sets_id ) = @_;

    $start_date ||= '2008-06-01';
    $end_date ||= Date::Format::time2str( "%Y-%m-%d", time - 86400 );

    my $days          = 0;
    my $update_weekly = 0;

    for ( my $date = $start_date ; $date le $end_date ; $date = _increment_day( $date ) )
    {
        say STDERR "update_aggregate_country_counts: $date ($start_date - $end_date) $days";

        if ( $force || !_aggregate_data_exists_for_date( $db, $date, $dashboard_topics_id, $media_sets_id ) )
        {
            _update_daily_country_counts( $db, $date, $dashboard_topics_id, $media_sets_id );
            $update_weekly = 1;
        }

        $db->commit();

        $days++;
    }

    $db->commit;
}

1;
