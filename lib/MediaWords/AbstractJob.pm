use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;

{

    package MediaWords::AbstractJob::Configuration;

    #
    # Implements MediaCloud::JobManager::Configuration with values from Media Cloud's configuration
    #

    use Moose;
    use MediaCloud::JobManager::Configuration;
    use MediaCloud::JobManager::Broker::Gearman;
    extends 'MediaCloud::JobManager::Configuration';

    # Job broker
    has 'job_broker' => ( is => 'rw' );

    sub BUILD
    {
        my $self = shift;

        my $config = MediaWords::Util::Config::get_config();

        $self->job_broker( MediaCloud::JobManager::Broker::Gearman->new( servers => $config->{ gearman }->{ servers }, ) );
    }

    # Job broker
    override 'broker' => sub {
        my $self = shift;

        return $self->job_broker;
    };

    no Moose;    # gets rid of scaffolding

    1;
}

{

    package MediaWords::AbstractJob;

    #
    # Superclass of all Media Cloud jobs
    #

    use Moose::Role;
    with 'MediaCloud::JobManager::Job';

    use MediaWords::DB;

    # Run job
    sub run($;$)
    {
        my ( $self, $args ) = @_;

        die "This is a placeholder implementation of the run() subroutine for a job.";
    }

    # Return default configuration
    sub configuration()
    {
        # It would be great to place configuration() in some sort of a superclass
        # for all the Media Cloud jobs, but Moose::Role doesn't
        # support that :(
        return MediaWords::AbstractJob::Configuration->instance;
    }

    no Moose;    # gets rid of scaffolding

    # Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
    __PACKAGE__;
}
