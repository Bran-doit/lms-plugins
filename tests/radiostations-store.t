use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use lib '.';
use Plugins::RadioStations::RadioStore;
my $dir = tempdir(CLEANUP => 1);
my $file = "$dir/radio.json";
{
    no warnings 'redefine';
    *Plugins::RadioStations::RadioStore::path = sub {$file};
}
{
    package FakeFavorites;
    sub new {bless {rows=>$_[1], file=>$_[2], deletes=>0}, $_[0]}
    sub toplevel {$_[0]{rows}}
    sub filename {$_[0]{file}}
    sub error {0}
    sub _flat {my @r; for (@{$_[1]}) {push @r, $_; push @r, $_[0]->_flat($_->{outline}) if $_->{outline}} @r}
    sub hasUrl {scalar grep {($_->{URL}||'') eq $_[1]} $_[0]->_flat($_[0]{rows})}
    sub deleteUrl {
        my ($self,$url)=@_;
        my $stored = Plugins::RadioStations::RadioStore::load();
        die 'destination must exist before delete' unless grep {$_->{url} eq $url} @$stored;
        $self->{deletes}++;
        my $walk; $walk=sub {my $rows=shift; for(my $i=0;$i<@$rows;$i++) {if(($rows->[$i]{URL}||'') eq $url){splice @$rows,$i,1; return 1} return 1 if $rows->[$i]{outline} && $walk->($rows->[$i]{outline});} return 0};
        $walk->($self->{rows});
    }
    sub add {my ($self,$url,$name,$type,$parser,$hotkey,$icon)=@_; push @{$self->{rows}}, {URL=>$url,text=>$name,type=>$type,parser=>$parser,icon=>$icon} unless $self->hasUrl($url)}
}
my $source = "$dir/favorites.opml";
open my $fh,'>',$source or die $!; print $fh '<opml>original backup fixture</opml>'; close $fh;
my $radio = {text=>'Ä Radio', URL=>'https://radio.test/live',type=>'audio',icon=>'https://radio.test/logo.png',parser=>'custom'};
my $favorites = FakeFavorites->new([
    {%$radio}, {text=>'nested',outline=>[{%$radio}]},
    {text=>'Podcast',URL=>'https://podcast.test/episode.mp3',type=>'audio'},
    {text=>'RSS',URL=>'https://podcast.test/feed.rss',type=>'link'},
    {text=>'Album',URL=>'db:album=1',type=>'audio'},
],$source);
my $candidates = Plugins::RadioStations::RadioStore::candidates($favorites, {$radio->{URL}=>'uuid'});
is(scalar @$candidates,2,'candidate audio list excludes album and RSS and deduplicates nested URLs');
ok($candidates->[0]{suggested},'known radio suggested');
ok(!$candidates->[1]{suggested},'unknown audio is not claimed to be radio');
my %selection = ($candidates->[0]{id}=>1);
is(Plugins::RadioStations::RadioStore::copy_selected($favorites,\%selection,{}),1,'selected station copied');
is($favorites->{deletes},0,'copy never deletes source entries');
is($favorites->hasUrl($radio->{URL}),2,'copy preserves source folders and duplicates');
is(Plugins::RadioStations::RadioStore::copy_selected($favorites,\%selection,{}),0,'repeated copy deduplicated');
is(Plugins::RadioStations::RadioStore::load()->[0]{parser},'custom','copy retains playback parser');
is(Plugins::RadioStations::RadioStore::restore_selected($favorites,\%selection),1,'returning copied entry supported');
is($favorites->hasUrl($radio->{URL}),2,'return does not add another source duplicate');
is(Plugins::RadioStations::RadioStore::move_selected($favorites,\%selection,{}),1,'selected radio moved');
is($favorites->{deletes},2,'duplicate entries removed safely after destination saved');
ok($favorites->hasUrl('https://podcast.test/episode.mp3'),'unselected podcast retained');
ok($favorites->hasUrl('db:album=1'),'album retained');
my $saved = Plugins::RadioStations::RadioStore::load();
is($saved->[0]{image},$radio->{icon},'logo preserved');
is($saved->[0]{parser},'custom','playback parser preserved');
opendir my $dh, $dir or die $!;
my @backups = grep {/^radio-favorites-backup-/} readdir $dh;
closedir $dh;
ok(scalar @backups,'original backup exists');
is(Plugins::RadioStations::RadioStore::move_selected($favorites,\%selection,{}),0,'repeated transfer does not duplicate');
is(Plugins::RadioStations::RadioStore::restore_selected($favorites,\%selection),1,'restoration supported');
ok($favorites->hasUrl($radio->{URL}),'restored to general favorites');
is(scalar @{Plugins::RadioStations::RadioStore::load()},0,'restoration removes independent copy');
{
    no warnings 'redefine';
    local *Plugins::RadioStations::RadioStore::save = sub {die 'disk full'};
    my $before=$favorites->{deletes};
    eval {Plugins::RadioStations::RadioStore::move_selected($favorites,\%selection,{})};
    like($@,qr/disk full/,'storage failure surfaced');
    is($favorites->{deletes},$before,'source never deleted when destination save fails');
}
is(Plugins::RadioStations::RadioStore::add_items([{name=>'Manual',url=>'https://manual.test/live',type=>'audio'}]),1,'manual station persisted');
is(Plugins::RadioStations::RadioStore::add_items([{name=>'Again',url=>'https://manual.test/live',type=>'audio'}]),0,'manual duplicate deduplicated');
is(Plugins::RadioStations::RadioStore::load()->[0]{name},'Manual','original manual name retained');
done_testing;
