use strict;
use warnings;
package Perlbal::Plugin::TrustedUpstreamProxies;
# ABSTRACT: Trusted upstream proxies from file

use JSON;
use Perlbal;
use Net::Netmask;

my %netmasks = ();

sub load {
    Perlbal::register_global_hook(
        'manage_command.trusted_upstream_proxies_file', sub {
            my $mc = shift->parse(
                qr/^\s*trusted_upstream_proxies_file\s+=\s+(.+)\s*$/,
                'usage: TRUSTED_UPSTREAM_PROXIES_FILE = <FILENAME>',
            );

            my ($file) = $mc->args;
            -f $file
                or die "Can't find file: $file\n";

            open my $fh, '<', $file
                or die "Can't open $file: $!\n";

            my $content = do { local $/; <$fh> };

            close $fh
                or die "Can't close $file: $!\n";

            my $values;
            eval {
                $values = decode_json $content;
                1;
            } or do {
                die "Can't decode JSON: $content: $@\n";
            };

            # simple check
            foreach my $svc ( keys %{$values} ) {
                my @netmasks = @{ $values->{$svc} };
                foreach my $netmask (@netmasks) {
                    eval {
                        Net::Netmask->new($netmask);
                        1;
                    } or do {
                        die "Bad netmask provided for $svc ($netmask): $@\n";
                    }
                }
            }

            %netmasks = %{$values};

            return 1;
        },
    );
}

sub register {
    my ( $class, $svc ) = @_;
    $svc->register_hook(
        'TrustedUpstreamProxies', 'start_http_request', sub {
            my $client   = shift;
            my $svc      = $client->{'service'};
            my $svc_name = $svc->{'name'};

            my $netmasks = $netmasks{$svc_name}
                or return 0;

            $svc->{'trusted_upstream_proxies'}
                and return 0;

            $svc->{'trusted_upstream_proxies'} = $netmasks;

            return 0;
        },
    );

    return 1;
}

sub unregister {
    my ( $class, $svc ) = @_;

    $svc->unregister_hooks('TrustedUpstreamProxies');

    return 1;
}

1;

__END__

=pod

=head1 SYNOPSIS

F<perlbal.conf>:

    LOAD TrustedUpstreamProxies

    TRUSTED_UPSTREAM_PROXIES_FILE = netmasks.json

    CREATE POOL sites
      POOL sites ADD 127.0.0.1:8090

    CREATE SERVICE http_balancer
      SET listen                  = 8081
      SET role                    = reverse_proxy
      SET pool                    = sites
      SET persist_client          = on
      SET persist_backend         = on
      SET persist_client_timeout  = 3600
      SET backend_persist_cache   = 10
      SET connect_ahead           = 10
      SET plugins                 = TrustedUpstreamProxies
    ENABLE http_balancer

F<netmasks.json>:

    {
        "http_balancer": [ "127.0.0.1" ]
    }

=head1 DESCRIPTION

Perlbal doesn't automatically add upstream proxies for security purposes.

In order to enable it, you need to turn on the C<always_trusted> flag
(which you should B<only> turn on if you trust your proxies fully - which
you shouldn't) or set the C<trusted_upstream_proxies>.

With later versions of Perlbal, C<trusted_upstream_proxies> supports
multiple netmasks. However, it cannot read from a file.

This plugin changes that, which just might be worthless.
