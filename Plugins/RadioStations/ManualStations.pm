package Plugins::RadioStations::ManualStations;

use strict;
use warnings;
use URI;

# One line per station: Name | URL, or a URL alone. Never fetch URLs here.
sub parse {
    my ($text) = @_;
    my (@items, @errors, %seen);
    my $line = 0;
    for my $entry (split /\r\n|\n|\r/, $text || '') {
        ++$line;
        $entry =~ s/^\s+|\s+$//g;
        next unless length $entry;
        my ($name, $url) = $entry =~ m{^https?://}i
            ? ('', $entry) : $entry =~ /^(.*?)\s*\|\s*(https?:\/\/.*)$/i;
        $name = '' unless defined $name;
        $url = '' unless defined $url;
        $url =~ s/^\s+|\s+$//g;
        $name =~ s/^\s+|\s+$//g;
        my $valid = eval {
            my $uri = URI->new($url);
            $url !~ /[\s\x00-\x1f\x7f]/ && $url =~ m{^https?://}i && $uri->host;
        };
        unless ($valid) { push @errors, $line; next; }
        next if $seen{$url}++;
        push @items, {
            name => length($name) ? $name : $url,
            type => 'audio', url => $url, favorites_url => $url,
            image => 'plugins/RadioStations/html/images/icon.png',
            on_select => 'play', playall => 1, bitrate => 128,
        };
    }
    return (\@items, \@errors);
}

1;
