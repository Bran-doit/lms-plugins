package Plugins::RadioStations::EditorStore;
use strict;
use warnings;
use base qw(Slim::Plugin::Favorites::Opml);
use JSON::XS ();
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Plugins::RadioStations::RadioStore;
my $prefs=preferences('plugin.radiostations');
sub revision {
 return JSON::XS->new->canonical->encode([Plugins::RadioStations::RadioStore::load(),$prefs->get('favoritesOrder'),$prefs->get('favoritesSort')]);
}
sub new {
 my $class=shift;
 my $self=$class->SUPER::new();
 $self->reload;
 return $self;
}
sub reload {
 my $self=shift;
 my $items=Plugins::RadioStations::Plugin::favoriteItems(undef);
 $self->{opml}={head=>{title=>string('PLUGIN_RADIOSTATIONS_FAVORITES')},body=>[{outline=>[map {{text=>$_->{name},URL=>$_->{url},icon=>$_->{image},type=>'audio',parser=>$_->{parser},originalURL=>$_->{url}}} @$items]}],version=>'1.0'};
 $self->{revision}=revision();
}
sub filename {Plugins::RadioStations::RadioStore::path()}
sub save {
 my $self=shift;
 eval {
  die 'Concurrent edit' unless $self->{revision} eq revision();
  my @items;my %seen;
  for my $entry (@{$self->toplevel}) {
   # Native New Favorite creates an unsaved placeholder until Save/Cancel.
   next if ($entry->{URL} || '') eq string('PLUGIN_FAVORITES_URL') && !exists $entry->{originalURL};
   my $url=$entry->{URL} || '';
   die 'Invalid stream URL' unless $url =~ m{^(?:https?|icy|mms|rtsp|tunein)://[^\s/]+(?:[^\s]*)$}i;
   die 'Duplicate URL' if $seen{$url}++;
   my $logo=$entry->{icon} || '';
   die 'Invalid logo URL' if length($logo) && $logo !~ m{^(?:https?://|/?(?:imageproxy|plugins|html)/)}i;
   my $item={id=>Plugins::RadioStations::RadioStore::id($url),name=>$entry->{text} || $url,url=>$url,type=>'audio',image=>$logo};
   $item->{parser}=$entry->{parser} if ($entry->{originalURL} || '') eq $url && $entry->{parser};
   push @items,$item;
  }
  Plugins::RadioStations::RadioStore::save(\@items);
  $prefs->set('favoritesSort','manual');
  $prefs->set('favoritesOrder',[map {$_->{id}} @items]);
  $self->{revision}=revision();
  delete $self->{error};
  1;
 } or do {$self->{error}='SAVEERROR';$self->reload};
}
1;
