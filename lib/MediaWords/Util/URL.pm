package MediaWords::Util::URL;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use URI;
use URI::QueryParam;
use Regexp::Common qw /URI/;
use MediaWords::Util::Web;
use List::MoreUtils qw/uniq/;

# Returns true if URL is in the "http" ("https") scheme
sub is_http_url($)
{
    my $url = shift;

    unless ( $url )
    {
        warn "URL is undefined";
        return 0;
    }

    my $uri = URI->new( $url )->canonical;

    unless ( $uri->scheme )
    {
        warn "Scheme is undefined for URL $url";
        return 0;
    }
    unless ( $uri->scheme eq 'http' or $uri->scheme eq 'https' )
    {
        warn "Scheme is not HTTP(s) or FTP for URL $url";
        return 0;
    }

    return 1;
}

# Normalize URL:
#
# * Fix common mistypes, e.g. "http://http://..."
# * Run URL through URI->canonical, i.e. standardize URL's scheme and hostname
#   case, remove default port, uppercase all escape sequences, unescape octets
#   that can be represented as plain characters, remove whitespace
#   before / after the URL string)
# * Remove #fragment
# * Remove various ad tracking query parameters, e.g. "utm_source",
#   "utm_medium", "PHPSESSID", etc.
#
# Return normalized URL on success; die() on error
sub normalize_url($)
{
    my $url = shift;

    unless ( $url )
    {
        die "URL is undefined";
    }

    # Fix broken URLs that look like this: http://http://www.al-monitor.com/pulse
    $url =~ s~(https?)://https?:?//~$1://~i;

    my $uri = URI->new( $url )->canonical;
    unless ( $uri->scheme )
    {
        die "Scheme is undefined for URL $url";
    }

    unless ( $uri->scheme eq 'http' or $uri->scheme eq 'https' or $uri->scheme eq 'ftp' )
    {
        die "Scheme is not HTTP(s) or FTP for URL $url";
    }

    # Remove #fragment
    $uri->fragment( undef );

    my @parameters_to_remove;

    # GA parameters (https://support.google.com/analytics/answer/1033867?hl=en)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ utm_source utm_medium utm_term utm_content utm_campaign utm_reader utm_place
          ga_source ga_medium ga_term ga_content ga_campaign ga_place /
    );

    # Facebook parameters (https://developers.facebook.com/docs/games/canvas/referral-tracking)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ fb_action_ids fb_action_types fb_source fb_ref
          action_object_map action_type_map action_ref_map
          fsrc /
    );

    # metrika.yandex.ru parameters
    @parameters_to_remove = ( @parameters_to_remove, qw/ yclid _openstat / );

    if ( $uri->host =~ /facebook\.com$/i )
    {
        # Additional parameters specifically for the facebook.com host
        @parameters_to_remove = ( @parameters_to_remove, qw/ ref fref hc_location / );
    }

    if ( $uri->host =~ /nytimes\.com$/i )
    {
        # Additional parameters specifically for the nytimes.com host
        @parameters_to_remove = (
            @parameters_to_remove,
            qw/ emc partner _r hp inline smid WT.z_sma bicmp bicmlukp bicmst bicmet abt
              abg /
        );
    }

    if ( $uri->host =~ /livejournal\.com$/i )
    {
        # Additional parameters specifically for the livejournal.com host
        @parameters_to_remove = ( @parameters_to_remove, qw/ thread nojs / );
    }

    # Some other parameters (common for tracking session IDs, advertising, etc.)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ PHPSESSID PHPSESSIONID
          cid s_cid sid ncid ir
          ref oref eref
          ns_mchannel ns_campaign
          wprss custom_click source
          feedName feedType /
    );

    # Make the sorting default (e.g. on Reddit)
    # Some other parameters (common for tracking session IDs, advertising, etc.)
    push( @parameters_to_remove, 'sort' );

    # Delete the "empty" parameter (e.g. in http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6)
    push( @parameters_to_remove, '' );

    # Remove cruft parameters
    foreach my $parameter ( @parameters_to_remove )
    {
        $uri->query_param_delete( $parameter );
    }

    # Remove parameters that start with '_' (e.g. '_cid') because they're more likely to be the tracking codes
    my @parameters = $uri->query_param;
    foreach my $parameter ( @parameters )
    {
        if ( $parameter =~ /^_/ )
        {
            $uri->query_param_delete( $parameter );
        }
    }

    return $uri->as_string;
}

# do some simple transformations on a URL to make it match other equivalent
# URLs as well as possible; normalization is "lossy" (makes the whole URL
# lowercase, removes subdomain parts "m.", "data.", "news.", ... in some cases)
sub normalize_url_lossy($)
{
    my $url = shift;

    $url = lc( $url );

    # r2.ly redirects through the hostname, ala http://543.r2.ly
    if ( $url !~ /r2\.ly/ )
    {
        $url =~ s/^(https?:\/\/)(m|media|data|image|www|cdn|topic|article|news|archive|blog|video|\d+?).?\./$1/i;
    }

    $url =~ s/\#.*//;

    $url =~ s/\/+$//;

    # fix broken urls that look like this: http://http://www.al-monitor.com/pulse
    $url =~ s~(https?)://https?:?//~$1://~i;

    return scalar( URI->new( $url )->canonical );
}

# get the domain of the given URL (sans "www." and ".edu"; see t/URL.t for output examples)
sub get_url_domain($)
{
    my $url = shift;

    $url =~ m~https?://([^/#]*)~ || return $url;

    my $host = $1;

    my $name_parts = [ split( /\./, $host ) ];

    my $n = @{ $name_parts } - 1;

    my $domain;
    if ( $host =~ /\.(gov|org|com?)\...$/i )
    {
        $domain = join( ".", ( $name_parts->[ $n - 2 ], $name_parts->[ $n - 1 ], $name_parts->[ $n ] ) );
    }
    elsif ( $host =~ /\.(edu|gov)$/i )
    {
        $domain = join( ".", ( $name_parts->[ $n - 2 ], $name_parts->[ $n - 1 ] ) );
    }
    elsif ( $host =~
        /wordpress.com|blogspot|livejournal.com|privet.ru|wikia.com|feedburner.com|24open.ru|patch.com|tumblr.com/i )
    {
        $domain = $host;
    }
    else
    {
        $domain = join( ".", $name_parts->[ $n - 1 ], $name_parts->[ $n ] );
    }

    return lc( $domain );
}

# From the provided HTML, determine the <meta http-equiv="refresh" /> URL (if any)
sub meta_refresh_url_from_html($;$)
{
    my ( $html, $base_url ) = @_;

    my $url = undef;
    while ( $html =~ m~(<\s*?meta.+?>)~gi )
    {
        my $meta_element = $1;

        if ( $meta_element =~ m~http-equiv\s*?=\s*?["']\s*?refresh\s*?["']~i )
        {
            if ( $meta_element =~ m~content\s*?=\s*?["']\d+?\s*?;\s*?URL\s*?=\s*?(.+?)["']~i )
            {
                $url = $1;
                if ( $url )
                {
                    if ( $url !~ /$RE{URI}/ )
                    {
                        # Maybe it's relative / absolute path?
                        if ( $base_url )
                        {
                            my $uri = URI->new_abs( $url, $base_url );
                            return $uri->as_string;
                        }
                        else
                        {
                            say STDERR
                              "HTML <meta http-equiv=\"refresh\"/> found, but the new URL ($url) doesn't seem to be valid.";
                        }
                    }
                    else
                    {
                        # Looks like URL, so return it
                        return $url;
                    }
                }
            }
        }
    }

    return undef;
}

# From the provided HTML, determine the <link rel="canonical" /> URL (if any)
sub link_canonical_url_from_html($;$)
{
    my ( $html, $base_url ) = @_;

    my $url = undef;
    while ( $html =~ m~(<\s*?link.+?>)~gi )
    {
        my $link_element = $1;

        if ( $link_element =~ m~rel\s*?=\s*?["']\s*?canonical\s*?["']~i )
        {
            if ( $link_element =~ m~href\s*?=\s*?["'](.+?)["']~i )
            {
                $url = $1;
                if ( $url )
                {
                    if ( $url !~ /$RE{URI}/ )
                    {
                        # Maybe it's absolute path?
                        if ( $base_url )
                        {
                            my $uri = URI->new_abs( $url, $base_url );
                            return $uri->as_string;
                        }
                        else
                        {
                            say STDERR
                              "HTML <link rel=\"canonical\"/> found, but the new URL ($url) doesn't seem to be valid.";
                        }
                    }
                    else
                    {
                        # Looks like URL, so return it
                        return $url;
                    }
                }
            }
        }
    }

    return undef;
}

# Fetch the URL, evaluate HTTP / HTML redirects; return URL and data after all
# those redirects; die() on error
sub url_and_data_after_redirects($;$$)
{
    my ( $orig_url, $max_http_redirect, $max_meta_redirect ) = @_;

    unless ( is_http_url( $orig_url ) )
    {
        die "URL is not HTTP(s): $orig_url";
    }

    my $uri = URI->new( $orig_url )->canonical;

    $max_http_redirect //= 7;
    $max_meta_redirect //= 3;

    my $html = undef;

    for ( my $meta_redirect = 1 ; $meta_redirect <= $max_meta_redirect ; ++$meta_redirect )
    {

        # Do HTTP request to the current URL
        my $ua = MediaWords::Util::Web::UserAgent;

        $ua->max_redirect( $max_http_redirect );

        my $response = $ua->get( $uri->as_string );

        unless ( $response->is_success )
        {
            warn "Request to " . $uri->as_string . " was unsuccessful: " . $response->status_line;
            $uri = URI->new( $orig_url )->canonical;
            last;
        }

        my @redirects = $response->redirects();

        # if ( scalar @redirects )
        # {
        #     say STDERR "Redirects:";
        #     foreach my $redirect ( @redirects )
        #     {
        #         say STDERR "* From:";
        #         say STDERR "    " . $redirect->request()->uri()->canonical;
        #         say STDERR "  to:";
        #         say STDERR "    " . $redirect->header( 'Location' );
        #     }
        # }

        my $new_uri = $response->request()->uri()->canonical;
        unless ( $uri->eq( $new_uri ) )
        {
            # say STDERR "New URI: " . $new_uri->as_string;
            $uri = $new_uri;
        }

        # Check if the returned document contains <meta http-equiv="refresh" />
        $html = $response->decoded_content || '';
        my $url_after_meta_redirect = meta_refresh_url_from_html( $html, $uri->as_string );
        if ( $url_after_meta_redirect and $uri->as_string ne $url_after_meta_redirect )
        {
            # say STDERR "URL after <meta /> refresh: $url_after_meta_redirect";
            $uri = URI->new( $url_after_meta_redirect )->canonical;

            # ...and repeat the HTTP redirect cycle here
        }
        else
        {
            # No <meta /> refresh, the current URL is the final one
            last;
        }

    }

    return ( $uri->as_string, $html );
}

# Given the URL, return all URL variants that we can think of:
# 1) Normal URL (the one passed as a parameter)
# 2) URL after redirects (i.e., fetch the URL, see if it gets redirected somewhere)
# 3) Canonical URL (after removing #fragments, session IDs, tracking parameters, etc.)
# 4) Canonical URL after redirects (do the redirect check first, then strip the tracking parameters from the URL)
# 5) URL from <link rel="canonical" /> (if any)
sub all_url_variants($)
{
    my $url = shift;

    # Get URL after HTTP / HTML redirects
    my ( $url_after_redirects, $data_after_redirects ) = url_and_data_after_redirects( $url );

    my %urls = (

        # Normal URL (don't touch anything)
        'normal' => $url,

        # Normal URL after redirects
        'after_redirects' => $url_after_redirects,

        # Canonical URL
        'canonical' => normalize_url( $url ),

        # Canonical URL after redirects
        'after_redirects_canonical' => normalize_url( $url_after_redirects )
    );

    # If <link rel="canonical" /> is present, try that one too
    if ( defined $data_after_redirects )
    {
        my $url_link_rel_canonical = link_canonical_url_from_html( $data_after_redirects, $url_after_redirects );
        if ( $url_link_rel_canonical )
        {
            say STDERR "Found <link rel=\"canonical\" /> for URL $url_after_redirects " .
              "(original URL: $url): $url_link_rel_canonical";

            $urls{ 'after_redirects_canonical_via_link_rel' } = $url_link_rel_canonical;
        }
    }

    return uniq( values %urls );
}

1;
