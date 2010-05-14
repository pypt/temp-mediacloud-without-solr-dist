package MediaWords::Controller::Clusters;

# set of screens for listing, creating, and viewing the results of clustering runs

use strict;
use warnings;
use parent 'Catalyst::Controller';

use MediaWords::Cluster;
use MediaWords::Util::Tags;

sub index : Path : Args(0)
{
    return list( @_ );
}

# list existing cluster runs
sub list : Local
{
    my ( $self, $c ) = @_;

    my $cluster_runs =
      $c->dbis->query( "select mcr.*, ms.name as media_set_name from media_cluster_runs mcr, media_sets ms " .
          "  where mcr.media_sets_id = ms.media_sets_id " . "  order by mcr.media_cluster_runs_id" )->hashes;

    $c->stash->{ cluster_runs } = $cluster_runs;

    $c->stash->{ template } = 'clusters/list.tt2';
}

# create a new cluster run, including both creating the media_cluster_runs entry and doing the cluster run
sub create : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/cluster.yml',
            method           => 'post',
            action           => $c->uri_for( '/clusters/create' ),
        }
    );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'clusters/create.tt2';
        return;
    }

    my $cluster_run =
      $c->dbis->create_from_request( 'media_cluster_runs', $c->request,
        [ qw/start_date end_date media_sets_id description num_clusters/ ] );

    MediaWords::Cluster::execute_and_store_media_cluster_run( $c->dbis, $cluster_run );

    $c->response->redirect( $c->uri_for( '/clusters/view/' . $cluster_run->{ media_cluster_runs_id } ) );
}

# view the results of a cluster run
sub view : Local
{
    my ( $self, $c, $cluster_runs_id ) = @_;

    my $run = $c->dbis->find_by_id( 'media_cluster_runs', $cluster_runs_id ) || die( "Unable to find run $cluster_runs_id" );

    my $media_clusters =
      $c->dbis->query( "select * from media_clusters where media_cluster_runs_id = ?", $cluster_runs_id )->hashes;

    for my $mc ( @{ $media_clusters } )
    {
        $mc->{ media } = $c->dbis->query(
            "select m.* from media m, media_clusters_media_map mcmm " .
              "  where m.media_id = mcmm.media_id and mcmm.media_clusters_id = ?",
            $mc->{ media_clusters_id }
        )->hashes;

        $mc->{ internal_features } = $c->dbis->query(
            "select * from media_cluster_words " . "  where media_clusters_id = ? and internal = 't' " .
              "  order by weight desc",
            $mc->{ media_clusters_id }
        )->hashes;

        $mc->{ external_features } = $c->dbis->query(
            "select * from media_cluster_words " . "  where media_clusters_id = ? and internal = 'f' " .
              "  order by weight desc",
            $mc->{ media_clusters_id }
        )->hashes;
    }

    $run->{ tag_name } = MediaWords::Util::Tags::lookup_tag_name( $c->dbis, $run->{ tags_id } );

    $c->stash->{ media_clusters } = $media_clusters;
    $c->stash->{ run }            = $run;

    $c->stash->{ template } = 'clusters/view.tt2';
}

1;
