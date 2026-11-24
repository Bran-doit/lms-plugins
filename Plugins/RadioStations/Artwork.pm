package Plugins::RadioStations::Artwork;
use strict;
use warnings;
use Slim::Utils::Cache;
my $cache=Slim::Utils::Cache->new;
my $fallback='plugins/RadioStations/html/images/icon.png';

# Use LMS's native station artwork cache, not a replacement metadata provider.
# HTTP embedded covers and metadata providers retain their normal precedence.
sub remember {
    my ($url,$logo)=@_;
    return unless $url && $logo && $logo ne $fallback;
    return unless $logo =~ m{^(?:https?://|/?(?:imageproxy/|plugins/|html/))}i;
    $cache->set('rs_logo:'.$url,$logo,2592000);
    seed($url,$logo);
    return $logo;
}
sub logo {
    return $cache->get('rs_logo:'.($_[0] || ''));
}
sub seed {
    my ($url,$logo)=@_;
    return unless $url && $logo;
    my $current=$cache->get('remote_image_'.$url);
    # Never overwrite a cover supplied by a stream, LMS or another plugin.
    if (!$current || $current =~ m{^/?(?:plugins/RadioStations/html/images/icon\.png|html/images/radio\.png)$}) {
        $cache->set('remote_image_'.$url,$logo,86400);
    }
}
sub playing {
    my ($client)=@_;
    return unless $client;
    my $song=$client->playingSong() || return;
    my $track=$song->track || return;
    my $url=$track->url;
    my $logo=logo($url) || return;
    seed($url,$logo);
    if (my $current=$song->currentTrack) {
        # Retain the original playlist logo for resolved streams as well.
        remember($current->url,$logo);
    }
}
1;
