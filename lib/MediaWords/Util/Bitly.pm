package MediaWords::Util::Bitly;

#
# Bit.ly API helper
#

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Web;
use MediaWords::Util::Config;
use JSON;

use constant BITLY_API_ENDPOINT => 'https://api-ssl.bitly.com/';

# Sends a request to Bit.ly API, returns a 'data' key hashref with results; die()s on error
sub request($$)
{
    my ( $path, $params ) = @_;

    unless ( $path )
    {
        die "Path is null; should be something like '/v3/link/lookup'";
    }
    unless ( $params )
    {
        die "Parameters argument is null; should be hashref of API call parameters";
    }
    unless ( ref( $params ) eq ref( {} ) )
    {
        die "Parameters argument is not a hashref.";
    }

    # Add access token
    my $config       = MediaWords::Util::Config::get_config;
    my $access_token = $config->{ bitly }->{ access_token };
    unless ( $access_token )
    {
        die "Bit.ly Generic Access Token is not set in the configuration";
    }
    if ( $params->{ access_token } )
    {
        die "Access token is already set; not resetting to the one from configuration";
    }
    $params->{ access_token } = $access_token;

    my $uri = URI->new( BITLY_API_ENDPOINT );
    $uri->path( $path );
    $uri->query_form( $params );
    my $url = $uri->as_string;

    my $ua       = MediaWords::Util::Web::UserAgent;
    my $response = $ua->get( $url );

    unless ( $response->is_success )
    {
        die "Error while fetching API response: " . $response->status_line . "; URL: $url";
    }

    my $json_string = $response->decoded_content;

    my $json;
    eval { $json = decode_json( $json_string ); };
    if ( $@ or ( !$json ) )
    {
        die "Unable to decode JSON response: $@; JSON: $json_string";
    }
    unless ( ref( $json ) eq ref( {} ) )
    {
        die "JSON response is not a hashref; JSON: $json_string";
    }

    if ( $json->{ status_code } != 200 )
    {
        die "API returned non-200 HTTP status code " . $json->{ status_code } . "; JSON: $json_string";
    }

    my $json_data = $json->{ data };
    unless ( $json_data )
    {
        die "JSON 'data' key is undef; JSON: $json_string";
    }
    unless ( ref( $json_data ) eq ref( {} ) )
    {
        die "JSON 'data' key is not a hashref; JSON: $json_string";
    }

    return $json_data;
}

1;
