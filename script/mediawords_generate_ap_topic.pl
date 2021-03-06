#!/usr/bin/env perl

# generate topic by creating topic_links between stories with identical sentences

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;

# search postgres for all sentences matching between the give media_id and the given media sources
# return a list of hashes with these fields: ref_stories_id, ref_sentence_number, source_stories_id, sentence_md5
sub find_story_sentence_matches
{
    my ( $db, $media_id, $media_tags_ids ) = @_;

    my $media_tags_ids_list = join( ',', map { $_ + 0 } @{ $media_tags_ids } );

    my $sentence_matches = $db->query( <<SQL, $media_id )->hashes;
with ap_sentences as (
    select
            ssc.first_stories_id ref_stories_id,
            s.url ref_url,
            ssc.sentence_md5,
            ssc.first_sentence_number sentence_number
        from story_sentence_counts ssc
            join stories s on ( ssc.first_stories_id = s.stories_id )
            join story_sentences ss
                on ( ss.stories_id = ssc.first_stories_id and ss.sentence_number = ssc.first_sentence_number )
        where
            s.media_id = \$1     and
            s.publish_date between '2015-01-13' and '2015-02-13' and
            length( ss.sentence ) > 32
)


select
        ap.ref_stories_id,
        ap.ref_url,
        mssc.first_stories_id source_stories_id,
        ms.url source_url
    from ap_sentences ap
        join story_sentence_counts mssc on ( ap.sentence_md5 = mssc.sentence_md5 and mssc.media_id <> \$1 )
        join media_tags_map mtm on ( mssc.media_id = mtm.media_id )
        join stories ms on ( mssc.first_stories_id = ms.stories_id )
    where
        mtm.tags_id in ( $media_tags_ids_list )
    group by
        ap.ref_stories_id,
        ap.ref_url,
        mssc.first_stories_id,
        ms.url
    having count(*) > 3

SQL

    return $sentence_matches;
}

# get or find 'ap sentences' topic
sub get_topic
{
    my ( $db ) = @_;

    my $topic_name = 'ap sentences';

    my $topic = $db->query( <<SQL, $topic_name )->hash;
select * from topics where name = ?
SQL

    return $topic if ( $topic );

    $topic = {
        name                => $topic_name,
        pattern             => '(ap sentences)',
        solr_seed_query     => '(ap sentences)',
        solr_seed_query_run => 't',
        description         => 'pseudo topic for analyzing syndication of ap sentences',
    };

    $topic = $db->create( 'topics', $topic );

    $db->create(
        'topic_dates',
        {
            topics_id  => $topic->{ topics_id },
            start_date => '2015-01-13',
            end_date   => '2015-02-13',
            boundary   => 't',
        }
    );

    return $topic;

}

# insert topic_stories rows for all distinct stories in story_sentence_matches
sub insert_topic_stories
{
    my ( $db, $topic, $story_sentence_matches ) = @_;

    my $stories_id_lookup = {};
    for my $ssm ( @{ $story_sentence_matches } )
    {
        $stories_id_lookup->{ $ssm->{ ref_stories_id } }    = 1;
        $stories_id_lookup->{ $ssm->{ source_stories_id } } = 1;
    }

    my $stories_ids = [ keys( %{ $stories_id_lookup } ) ];

    # create table topic_stories (
    #     topic_stories_id          serial primary key,
    #     topics_id                int not null references topics on delete cascade,
    #     stories_id                      int not null references stories on delete cascade,
    #     link_mined                      boolean default 'f',
    #     iteration                       int default 0,
    #     link_weight                     real,
    #     redirect_url                    text,
    #     valid_foreign_rss_story         boolean default false
    # );

    say STDERR "STORIES " . scalar( @{ $stories_ids } );

    for my $stories_id ( @{ $stories_ids } )
    {
        my $story_exists = $db->query( <<SQL, $topic->{ topics_id }, $stories_id )->hash;
select 1 from topic_stories where topics_id = ? and stories_id = ?
SQL

        next if ( $story_exists );

        my $cs = {
            topics_id  => $topic->{ topics_id },
            stories_id => $stories_id,
            link_mined => 't',
            iteration  => 0
        };
        $db->create( 'topic_stories', $cs );
    }
}

# for each item in story_sentence_matches, create a topic_link
# with the given source_stories_id and ref_stories_id
sub insert_topic_links
{
    my ( $db, $topic, $story_sentence_matches ) = @_;

    my $cid = $topic->{ topics_id };

    say STDERR "MATCHES " . scalar( @{ $story_sentence_matches } );

    for my $ssm ( @{ $story_sentence_matches } )
    {
        my $link_exists = $db->query( <<SQL, $cid, $ssm->{ source_stories_id }, $ssm->{ ref_stories_id } )->hash;
select 1 from topic_links where topics_id = ? and stories_id = ? and ref_stories_id = ?
SQL

        next if ( $link_exists );

        # create table topic_links (
        #     topic_links_id        serial primary key,
        #     topics_id            int not null,
        #     stories_id                  int not null,
        #     url                         text not null,
        #     redirect_url                text,
        #     ref_stories_id              int references stories on delete cascade,
        #     link_spidered               boolean default 'f'
        # );

        my $cl = {
            topics_id      => $cid,
            stories_id     => $ssm->{ source_stories_id },
            url            => $ssm->{ ref_url },
            ref_stories_id => $ssm->{ ref_stories_id }
        };

        $db->create( 'topic_links', $cl );
    }

    say STDERR "";
}

# generate alternative form of story_sentence_matches in which each source_stories_id that are associated
# with a given sentence each point to each other as well as pointing to the ap store that is the ref_stories_id
sub get_peer_matches
{
    my ( $story_sentence_matches ) = @_;

    my $source_lookup = {};
    map { push( @{ $source_lookup->{ $_->{ ref_stories_id } } }, $_ ) } @{ $story_sentence_matches };

    my $peer_matches = [];
    for my $source_matches ( values( %{ $source_lookup } ) )
    {
        for my $a ( @{ $source_matches } )
        {
            for my $b ( @{ $source_matches } )
            {
                next if ( $b->{ source_stories_id } == $a->{ source_stories_id } );

                my $peer_match = {
                    source_stories_id => $a->{ source_stories_id },
                    ref_stories_id    => $b->{ source_stories_id },
                    ref_url           => $b->{ source_url }
                };
                push( @{ $peer_matches }, $peer_match );
            }
        }
    }

    return $peer_matches;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $media_id = 209366;

    # us msm, us pol blogs, us part cons/liberal/libertarian
    my $media_tags_ids = [ 8875027, 8875108, 8878292, 8878293, 8878294 ];

    my $story_sentence_matches = find_story_sentence_matches( $db, $media_id, $media_tags_ids );

    my $topic = get_topic( $db );

    say STDERR "INSERT STORIES";

    insert_topic_stories( $db, $topic, $story_sentence_matches );

    say STDERR "INSERT LINKS";

    insert_topic_links( $db, $topic, $story_sentence_matches );

    my $peer_matches = get_peer_matches( $story_sentence_matches );

    say STDERR "INSERT PEER LINKS";

    insert_topic_links( $db, $topic, $peer_matches );

    say STDERR "DONE";
}

main();
