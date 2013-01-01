package App::Netdisco::Daemon::Worker::Manager;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::DeviceProperties 'is_discoverable';
use Net::Domain 'hostfqdn';
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

my $fqdn = hostfqdn || 'localhost';

# forward and reverse mappings for worker role to Netdisco job type (action)
# this needs updating when we invent new job types
my $action_map = {
  Interactive => [qw/location contact portcontrol portname vlan power/]
};
my $role_map = {
  map {$_ => 'Interactive'} @{ $action_map->{Interactive} }
};

sub worker_begin {
  my $self = shift;

  # requeue jobs locally
  my $rs = schema('netdisco')->resultset('Admin')
    ->search({status => "queued-$fqdn"});

  my @jobs = map {$_->get_columns} $rs->all;
  map { $_->{role} = $role_map->{$_->{action}} } @jobs;

  $self->do('add_jobs', \@jobs);
}

sub worker_body {
  my $self = shift;

  # get all pending jobs
  my $rs = schema('netdisco')->resultset('Admin')
    ->search({wid => 0});

  while (1) {
      while (my $job = $rs->next) {
          # filter for discover_*
          next unless is_discoverable($job->device);

          # check for available local capacity
          next unless $self->capacity_for($job);

          # mark job as running
          next unless $self->lock_job($job);

          my $local_job = $job->get_columns;
          $local_job->{role} = $role_map->{$local_job->{action}};

          # copy job to local queue
          $self->do('add_jobs', [$local_job]);
      }

      # reset iterator so ->next() triggers another DB query
      $rs->reset;

      # TODO also check for stale jobs in Netdisco DB

      interruptible_sleep( setting('daemon_sleep_time') || 5 );
  }
}

sub capacity_for {
  my ($self, $job) = @_;

  my $setting_map = {
    Poller => 'daemon_pollers',
    Interactive => 'daemon_interactives',
  };

  my $role = $role_map->{$job->action};
  my $setting = $setting_map->{$role};

  my $current = schema('netdisco')->resultset('Admin')
    ->search({role => $role, status => "queued-$fqdn"})->count;

  return ($current < setting($setting));
}

sub lock_job {
  my ($self, $job) = @_;
  my $happy = 0;

  # lock db row and update to show job has been picked
  try {
      schema('netdisco')->txn_do(sub {
          my $row = schema('netdisco')->resultset('Admin')->find(
            {job => $job->job, status => 'queued'}, {for => 'update'}
          );

          $row->update({status => "queued-$fqdn"});
      });
      $happy = 1;
  };

  return $happy;
}

1;
