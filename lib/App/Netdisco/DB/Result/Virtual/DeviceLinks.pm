package App::Netdisco::DB::Result::Virtual::DeviceLinks;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# note to future devs:
# this query does not use the slave_of field in device_port table to group
# ports because what we actually want is total b/w between devices on all
# links, regardless of whether those links are in an aggregate.

__PACKAGE__->table('device_links');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
 SELECT dp.ip AS left_ip, ld.dns AS left_dns, ld.name AS left_name,
        array_agg(dp.port) AS left_port, array_agg(dp.name) AS left_descr,
        sum( COALESCE(dpp.raw_speed,0) ) as aggspeed,
        count(*) AS aggports,
        di.ip AS right_ip, rd.dns AS right_dns, rd.name AS right_name,
        array_agg(dp.remote_port) AS right_port, array_agg(dp2.name) AS right_descr

 FROM device_port dp
 LEFT OUTER JOIN device_port_properties dpp USING (ip, port)
 INNER JOIN device ld ON dp.ip = ld.ip
 INNER JOIN device_ip di ON dp.remote_ip = di.alias
 INNER JOIN device rd ON di.ip = rd.ip
 LEFT OUTER JOIN device_port dp2
   ON (di.ip = dp2.ip
       AND ((dp.remote_port = dp2.port)
            OR (dp.remote_port = dp2.name)
            OR (dp.remote_port = dp2.descr)))

 WHERE dp.remote_port IS NOT NULL
   AND dp.port !~* 'vlan'
   AND (dp.type IS NULL OR dp.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
   AND (dp.name IS NULL OR dp.name !~* 'vlan')
   AND (dp.is_master = 'false' OR dp.slave_of IS NOT NULL)
   AND dp.ip <= di.ip
 GROUP BY left_ip, left_dns, left_name, right_ip, right_dns, right_name
 ORDER BY dp.ip
ENDSQL
);

__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'left_dns' => {
    data_type => 'text',
  },
  'left_name' => {
    data_type => 'text',
  },
  'left_port' => {
    data_type => '[text]',
  },
  'left_descr' => {
    data_type => '[text]',
  },
  'aggspeed' => {
    data_type => 'bigint',
  },
  'aggports' => {
    data_type => 'integer',
  },
  'right_ip' => {
    data_type => 'inet',
  },
  'right_dns' => {
    data_type => 'text',
  },
  'right_name' => {
    data_type => 'text',
  },
  'right_port' => {
    data_type => '[text]',
  },
  'right_descr' => {
    data_type => '[text]',
  },
);

__PACKAGE__->has_many('left_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.left_ip" },
      "$args->{self_alias}.left_port" => { '@>' => \"ARRAY[$args->{foreign_alias}.port]" },
    };
  }
);

__PACKAGE__->has_many('right_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.right_ip" },
      "$args->{self_alias}.right_port" => { '@>' => \"ARRAY[$args->{foreign_alias}.port]" },
    };
  }
);

1;
