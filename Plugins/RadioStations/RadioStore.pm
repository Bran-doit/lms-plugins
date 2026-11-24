package Plugins::RadioStations::RadioStore;
use strict;
use warnings;
use JSON::XS ();
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);
use File::Spec;
use File::Copy qw(copy);
use File::Temp qw(tempfile);

sub path {
    require Slim::Utils::OSDetect;
    return File::Spec->catfile(Slim::Utils::OSDetect::dirsFor('prefs'), 'radiostations-favorites.json');
}

sub load {
    my $file = path();
    return [] unless -e $file;
    open my $fh, '<:raw', $file or die "Cannot read radio favorites: $!";
    local $/; my $data = JSON::XS::decode_json(<$fh>); close $fh;
    die 'Invalid radio favorites file' unless ref $data eq 'HASH' && $data->{version} == 1 && ref $data->{items} eq 'ARRAY';
    return $data->{items};
}

sub _backup {
    my ($file) = @_;
    return unless -f $file;
    my ($fh, $backup) = tempfile('radio-favorites-backup-XXXXXX', DIR => File::Spec->catpath((File::Spec->splitpath($file))[0,1], ''), UNLINK => 0);
    close $fh;
    copy($file, $backup) or die "Cannot back up favorites: $!";
    return $backup;
}

sub save {
    my ($items) = @_;
    my $file = path();
    my ($volume, $dir) = File::Spec->splitpath($file);
    _backup($file);
    my ($fh, $tmp) = tempfile('radiostations-write-XXXXXX', DIR => File::Spec->catpath($volume, $dir, ''), UNLINK => 0);
    binmode $fh;
    my $bytes = JSON::XS::encode_json({version => 1, items => $items});
    print {$fh} $bytes or die "Cannot write radio favorites: $!";
    close $fh or die "Cannot close radio favorites: $!";
    rename($tmp, $file) or die "Cannot replace radio favorites: $!";
    # Verify the persisted destination before any source entry can be deleted.
    my $check = load();
    die 'Radio favorites verification failed' unless JSON::XS->new->canonical->encode($check) eq JSON::XS->new->canonical->encode($items);
}

sub add_items {
    my ($items)=@_;
    my $stored=load(); my %seen=map {$_->{url}=>1} @$stored;
    my $added=0;
    for my $item (@$items) {
        next if $seen{$item->{url}}++;
        push @$stored,{%$item,id=>id($item->{url})}; ++$added;
    }
    save($stored) if $added;
    return $added;
}

sub id { sha256_hex(encode_utf8($_[0] || '')) }

sub candidates {
    my ($favorites, $known) = @_;
    my (@result, %seen);
    my $walk;
    $walk = sub {
        for my $entry (@{$_[0] || []}) {
            $walk->($entry->{outline}) if ref $entry->{outline} eq 'ARRAY';
            my $url = $entry->{URL} || $entry->{url} || next;
            # Keep folders, local albums, feeds and podcast-specific schemes out.
            next unless ($entry->{type} || '') =~ /^(?:audio|playlist)$/;
            next unless $url =~ m{^(?:https?|mms|rtsp|icy|tunein)://}i;
            next if $url =~ m{\.(?:rss|xml)(?:[?#]|$)}i || $seen{$url}++;
            my $icon = $entry->{icon} || '';
            push @result, {
                id => id($url), name => $entry->{text} || $url, url => $url,
                type => $entry->{type}, parser => $entry->{parser}, image => $icon,
                suggested => ($known->{$url} || $icon =~ m{plugins/(?:RadioBrowser|RadioStations)/}
                    || $url =~ m{^https?://opml\.radiotime\.com/Tune\.ashx\?.*\bid=s\d+(?:&|$)}i) ? 1 : 0,
            };
        }
    };
    $walk->($favorites->toplevel);
    return \@result;
}

sub copy_selected {
    my ($favorites,$selected,$known)=@_;
    my @items=grep {$selected->{$_->{id}}} @{candidates($favorites,$known || {})};
    return add_items(\@items);
}

sub move_selected {
    my ($favorites, $selected, $known) = @_;
    my @move = grep {$selected->{$_->{id}}} @{candidates($favorites, $known || {})};
    return 0 unless @move;
    _backup($favorites->filename) || die 'Cannot locate original favorites for backup';
    my $stored = load();
    my %byUrl = map {$_->{url} => $_} @$stored;
    for my $item (@move) {
        $byUrl{$item->{url}} ||= {map {$_ => $item->{$_}} qw(id name url type parser image)};
    }
    save([sort {$a->{url} cmp $b->{url}} values %byUrl]);
    for my $item (@move) {
        # The same URL can occur in multiple folders. Resolve its index anew.
        my $guard = 0;
        while ($favorites->hasUrl($item->{url})) {
            die 'Cannot remove duplicate favorite' if ++$guard > 10000;
            $favorites->deleteUrl($item->{url});
            die 'LMS could not save favorites' if $favorites->error;
        }
    }
    return scalar @move;
}

sub restore_selected {
    my ($favorites, $selected) = @_;
    my $items = load();
    my @keep;
    my $count = 0;
    for my $item (@$items) {
        unless ($selected->{$item->{id}}) { push @keep, $item; next; }
        $favorites->add($item->{url}, $item->{name}, $item->{type}, $item->{parser}, undef, $item->{image}) unless $favorites->hasUrl($item->{url});
        die 'LMS could not restore favorite' if $favorites->error || !$favorites->hasUrl($item->{url});
        ++$count;
    }
    save(\@keep) if $count;
    return $count;
}

1;
