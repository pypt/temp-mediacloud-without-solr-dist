package MediaWords::DBI::Media::Rescrape;

#
# Media (re)scraping utilities
#

use strict;
use warnings;

use Modern::Perl "2013";

use MediaWords::CommonLibs;

use MediaWords::DBI::Media;
use MediaWords::DBI::Feeds;
use MediaWords::GearmanFunction::RescrapeMedia;
use Feed::Scrape::MediaWords;

# add default feeds for a single medium
sub enqueue_rescrape_media($)
{
    my ( $medium ) = @_;

    return MediaWords::GearmanFunction::RescrapeMedia->enqueue_on_gearman( { media_id => $medium->{ media_id } } );
}

# for each medium in $media, enqueue an RescrapeMedia job for any medium
# that is lacking feeds
sub add_feeds_for_feedless_media
{
    my ( $db, $media ) = @_;

    for my $medium ( @{ $media } )
    {
        my $media_has_active_syndicated_feeds = $db->query(
            <<END,
            SELECT 1
            FROM media
            WHERE media_id = ?
              AND media_has_active_syndicated_feeds(media_id) = 't'
END
            $medium->{ media_id }
        )->hash;

        unless ( $media_has_active_syndicated_feeds )
        {
            enqueue_rescrape_media( $medium );
        }
    }
}

# (re-)enqueue RescrapeMedia jobs for all unmoderated media
# ("RescrapeMedia" Gearman function is "unique", so Gearman will skip media
# IDs that are already enqueued)
sub enqueue_rescrape_media_for_unmoderated_media($)
{
    my ( $db ) = @_;

    my $media = $db->query(
        <<EOF
        SELECT *
        FROM media
        WHERE media_has_active_syndicated_feeds(media_id) = 'f'
EOF
    )->hashes;

    map { enqueue_rescrape_media( $_ ) } @{ $media };

    return 1;
}

# Move feeds from "feeds_after_rescraping" to "feeds" table
# Note: it doesn't create a transaction itself, so make sure to do that in a caller
sub move_feeds_after_rescraping_to_feeds($$)
{
    my ( $db, $feeds_after_rescraping ) = @_;

    unless ( ref $feeds_after_rescraping eq ref [] )
    {
        die "'feeds_after_rescraping' is not an arrayref.";
    }

    foreach my $feed_after_rescraping ( @{ $feeds_after_rescraping } )
    {

        unless ( ref $feed_after_rescraping eq ref {} )
        {
            die "Feed is not a hashref.";
        }
        unless ($feed_after_rescraping->{ feeds_after_rescraping_id }
            and $feed_after_rescraping->{ media_id } )
        {
            die "Feed hashref doesn't have required keys.";
        }

        my $feed = {
            media_id    => $feed_after_rescraping->{ media_id },
            name        => $feed_after_rescraping->{ name },
            url         => $feed_after_rescraping->{ url },
            feed_type   => $feed_after_rescraping->{ feed_type },
            feed_status => 'active',
        };

        my $existing_feed = $db->query(
            <<EOF,
            SELECT *
            FROM feeds
            WHERE url = ?
              AND media_id = ?
EOF
            $feed_after_rescraping->{ url },
            $feed_after_rescraping->{ media_id }
        )->hash;
        if ( $existing_feed )
        {
            $db->update_by_id( 'feeds', $existing_feed->{ feeds_id }, $feed );
        }
        else
        {
            $db->create( 'feeds', $feed );
        }

        if ( $feed->{ feed_type } eq 'syndicated' )
        {
            # If media is getting rescraped and syndicated feeds were just
            # found, disable the "web_page" feeds that we might have added
            # previously
            my $active_webpage_feeds = $db->query(
                <<EOF,
                SELECT *
                FROM feeds
                WHERE media_id = ?
                  AND feed_type = 'web_page'
                  AND feed_status = 'active'
EOF
                $feed->{ media_id }
            )->hashes;
            foreach my $active_webpage_feed ( @{ $active_webpage_feeds } )
            {
                MediaWords::DBI::Feeds::disable_feed( $db, $active_webpage_feed->{ feeds_id } );
            }
        }

        $db->query(
            <<EOF,
            DELETE FROM feeds_after_rescraping
            WHERE feeds_after_rescraping_id = ?
EOF
            $feed_after_rescraping->{ feeds_after_rescraping_id }
        );
    }
}

# Search and add new feeds for unmoderated media (media sources that have not
# had default feeds added to them).
#
# Look for feeds that are most likely to be real feeds.  If we find more than
# one but no more than MAX_DEFAULT_FEEDS of those feeds, use the first such one
# and do not moderate the source.  Else, do a more expansive search and mark
# for moderation.
sub rescrape_media($$)
{
    my ( $db, $media_id ) = @_;

    my $medium = $db->find_by_id( 'media', $media_id );
    unless ( $medium )
    {
        die "Media ID $media_id does not exist.";
    }

    my ( $feed_links, $need_to_moderate ) = Feed::Scrape::get_feed_links_and_need_to_moderate( $db, $medium );

    $db->begin_work;

    $db->query(
        <<EOF,
        DELETE FROM feeds_after_rescraping
        WHERE media_id = ?
EOF
        $media_id
    );

    for my $feed_link ( @{ $feed_links } )
    {
        my $feed = {
            media_id  => $media_id,
            name      => $feed_link->{ name },
            url       => $feed_link->{ url },
            feed_type => $feed_link->{ feed_type } || 'syndicated',
        };

        $db->create( 'feeds_after_rescraping', $feed );
    }

    # If we came up with the very same set of feeds after rescraping and the
    # media would need moderation, but we have moderated the very same set of
    # links before (i.e. made the decision about this particular set of feeds),
    # just leave the current set of feeds intact
    my $live_feeds = $db->query(
        <<EOF,
        SELECT media_id,
               name,
               url,
               feed_type
        FROM feeds
        WHERE media_id = ?
          AND feed_type = 'syndicated'
        ORDER BY name, url, feed_type
EOF
        $media_id
    )->hashes;
    my $rescraped_feeds = $db->query(
        <<EOF,
        SELECT media_id,
               name,
               url,
               feed_type
        FROM feeds_after_rescraping
        WHERE media_id = ?
          AND feed_type = 'syndicated'
        ORDER BY name, url, feed_type
EOF
        $media_id
    )->hashes;

    local $Data::Dumper::Sortkeys = 1;
    if ( $medium->{ moderated } and $need_to_moderate and Dumper( $rescraped_feeds ) eq Dumper( $live_feeds ) )
    {
        say STDERR
"Media $media_id would need rescraping but we have moderated the very same feeds previously so disabling moderation";
        $need_to_moderate = 0;
    }

    if ( $need_to_moderate )
    {
        # (Re)set moderated = 'f' so that the media shows up in the moderation page
        $db->query(
            <<EOF,
                UPDATE media
                SET moderated = 'f'
                WHERE media_id = ?
EOF
            $media_id
        );
    }
    else
    {
        # Move all newly scraped feeds to "feeds" table
        my $feeds_after_rescraping = $db->query(
            <<EOF,
            SELECT *
            FROM feeds_after_rescraping
            WHERE media_id = ?
EOF
            $media_id
        )->hashes;
        move_feeds_after_rescraping_to_feeds( $db, $feeds_after_rescraping );

        # Update "last rescraped" value
        $db->query(
            <<EOF,
                UPDATE media_rescraping
                SET last_rescrape_time = NOW()
                WHERE media_id = ?
EOF
            $media_id
        );

        # Set moderated = 't' because maybe this is a new media item that
        # didn't have any feeds previously
        $db->query(
            <<EOF,
                UPDATE media
                SET moderated = 't'
                WHERE media_id = ?
EOF
            $media_id
        );
    }

    $db->commit;
}

1;
