package Plugins::RadioStations::Detector;
use strict;
use warnings;
use URI;
use URI::Escape qw(uri_escape_utf8);
use Slim::Networking::SimpleAsyncHTTP;

sub podcast_hint {
    my ($entry) = @_;
    return (($entry->{parser} || '') =~ /podcast|rss/i
        || ($entry->{url} || '') =~ m{(?:/(?:podcasts?|episodes?)/|\.(?:rss|xml)(?:[?#]|$)|^podcast:)}i) ? 1 : 0;
}

sub public_lookup {
    my ($url) = @_;
    my $uri = eval { URI->new($url) };
    return 0 unless $uri && $uri->can('host') && $uri->host;
    my $host = lc $uri->host;
    return 0 if $uri->userinfo || $host !~ /\./ || $host =~ /(?:\.local|\.lan|\.internal)$/
        || $host =~ /^(?:localhost|127\.|10\.|192\.168\.|169\.254\.|0\.|172\.(?:1[6-9]|2\d|3[01])\.)/;
    return 0 if $host =~ /:/ || $url =~ /[?&](?:token|auth|password|key|secret|sessionid)=/i;
    return 1;
}

sub header_result {
    my ($headers, $code) = @_;
    return {kind=>'unknown', reason=>'unreachable'} unless $headers && $code && $code >= 200 && $code < 300;
    my $type = lc($headers->header('Content-Type') || '');
    return {kind=>'podcast', reason=>'feed'} if $type =~ /(?:rss|atom)/;
    # A finite resource, attachment, or duration is not enough evidence of live radio.
    my $finite = ($headers->header('Content-Length') || 0) > 0
        || $headers->header('Content-Range') || $headers->header('Content-Disposition')
        || $headers->header('X-Content-Duration') || $headers->header('Content-Duration');
    my $name = $headers->header('icy-name') || '';
    my $meta = $headers->header('icy-metaint') || $headers->header('icy-genre') || $headers->header('icy-br');
    return {kind=>'radio', reason=>'icy'} if !$finite && $type =~ m{^audio/} && length($name) && $meta;
    return {kind=>'unknown', reason=>$finite ? 'finite' : 'insufficient'};
}

# Serial, asynchronous evidence checks. No stream body is downloaded: HEAD only.
# api is the plugin's mirror-aware JSON transport; injectable for tests.
sub classify {
    my ($entry, $known, $api, $done) = @_;
    my $url = $entry->{url} || '';
    return $done->({kind=>'podcast', reason=>'podcast'}) if podcast_hint($entry);
    return $done->({kind=>'radio', reason=>'known'}) if $known->{$url};
    return $done->({kind=>'radio', reason=>'tunein'})
        if $url =~ m{^https?://opml\.radiotime\.com/Tune\.ashx\?(?:[^#]*&)?id=s\d+(?:&|$)}i;
    my $probe = sub {
        return $done->({kind=>'unknown', reason=>'protocol'}) unless $url =~ m{^https?://}i;
        Slim::Networking::SimpleAsyncHTTP->new(
            sub {my $http=shift; $done->(header_result($http->headers, $http->code));},
            sub {$done->({kind=>'unknown', reason=>'unreachable'});},
            {timeout=>5, maxRedirect=>3},
        )->head($url, 'User-Agent'=>'RadioStations/0.9.0', 'Icy-MetaData'=>1);
    };
    return $probe->() unless public_lookup($url);
    $api->('/json/stations/byurl?url=' . uri_escape_utf8($url), sub {
        my $rows = shift;
        if (ref $rows eq 'ARRAY') {
            for my $row (@$rows) {
                next unless ref $row eq 'HASH' && $row->{stationuuid};
                next unless ($row->{url} || '') eq $url || ($row->{url_resolved} || '') eq $url;
                return $done->({kind=>'radio', reason=>'directory', uuid=>$row->{stationuuid}});
            }
        }
        $probe->();
    }, sub {$probe->();});
}

1;







