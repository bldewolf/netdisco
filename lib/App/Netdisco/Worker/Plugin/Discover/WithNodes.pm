package App::Netdisco::Worker::Plugin::Discover::WithNodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';

register_worker({ primary => false }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # if requested, and the device has not yet been
  # arpniped/macsucked, queue those jobs now
  if ($device->in_storage
      and $job->subaction and $job->subaction eq 'with-nodes') {
    if (!defined $device->last_macsuck) {
      jq_insert({
        device => $device->ip,
        action => 'macsuck',
        username => $job->username,
        userip => $job->userip,
      });
    }

    if (!defined $device->last_arpnip) {
      jq_insert({
        device => $device->ip,
        action => 'arpnip',
        username => $job->username,
        userip => $job->userip,
      });
    }
  }

  return Status->done('Ended discover for '. $device->ip);
});

true;
