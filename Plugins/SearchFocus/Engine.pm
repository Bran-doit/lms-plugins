package Plugins::SearchFocus::Engine;
use strict;
use warnings;
use utf8;
use Plugins::SearchFocus::I18N qw(loc language);
use Unicode::Normalize qw(NFKD);
use Encode qw(decode FB_CROAK);
use Time::HiRes qw(time);

our $DEFAULT_NAME_ALIASES = <<'ALIASES';
# Library name | Family name (optional) | Full-name aliases separated by ;
Chopin | Chopin | Fryderyk Chopin; Frédéric Chopin; Frederik Chopin; Frederyk Chopin
Frédéric Chopin | Chopin | Fryderyk Chopin; Frederik Chopin; Frederyk Chopin
Fryderyk Chopin | Chopin | Frédéric Chopin; Frederik Chopin; Frederyk Chopin
ALIASES

our %DEFAULTS = (enabled=>1, mode=>'and', title=>1, album=>1, artist=>1,
    genre=>0, playlist=>1, lyrics=>0, comment=>0, genre_fuzzy=>1, genre_hide_mixed=>1, name_fuzzy=>1, name_aliases=>$DEFAULT_NAME_ALIASES);
my %WEIGHT = (title=>100, artist=>100, album=>100, playlist=>100, genre=>20, lyrics=>5, comment=>3);
my %ARTICLE = map {$_=>1} qw(der die das des dem den ein eine eines einem einen einer kein keine keines keinem keinen keiner);
my %POSSESSIVE = map {$_=>1} (
    (map {my $stem=$_; map {$stem.$_} ('','e','en','em','er','es')} qw(mein dein sein ihr unser)),
    qw(euer eure euren eurem eurer eures unsre unsren unsrem unsrer unsres)
);
my %LABEL = (title=>['Songtitel','Track title'], artist=>['Interpretenname','Artist name'], album=>['Albumname','Album name'],
    playlist=>['Playlistname','Playlist name'], genre=>['Genre','Genre'], lyrics=>['Liedtext','Lyrics'], comment=>['Kommentar','Comment']);

sub text {
    my $s = defined $_[0] ? "$_[0]" : '';
    if (!utf8::is_utf8($s)) { my $v = eval { decode('UTF-8', $s, FB_CROAK) }; $s=$v if defined $v; }
    return $s;
}
sub normal {
    my $s=lc text($_[0]);
    $s =~ s/ß/ss/g;
    $s=NFKD($s); $s =~ s/\pM//g;
    $s =~ s/[^\pL\pN]+/ /g;
    $s =~ s/^ +| +$//g;
    return $s;
}
sub tokens {
    my $q=text($_[0]);
    die loc('Suchbegriff zu lang (maximal 256 Zeichen)','Search query too long (maximum 256 characters)') if length($q)>256;
    my @t=split / +/, normal($q);
    die loc('Zu viele Suchwoerter (maximal 12)','Too many search words (maximum 12)') if @t>12;
    my %seen; return [grep {length && !$seen{$_}++} @t];
}

# Explicit German word lists, not a grammatical parser. Never remove a token.
# Capitalization is taken from the user's query, never from inconsistent tags.
sub wordWeights {
    my ($query,$terms)=@_;
    my %capital;
    for my $raw (split /[^\pL\pN\pM]+/, text($query)) {
        $capital{normal($raw)}=1 if $raw =~ /^\p{Lu}/;
    }
    my %weights;
    for my $term (@$terms) {
        my ($points,$kind)= $ARTICLE{$term} ? (100,loc('Artikel','article'))
            : $POSSESSIVE{$term} ? (100,loc('Possessivform','possessive form'))
            : $capital{$term} ? (1200,loc('Inhaltswort, großgeschrieben','content word, capitalized'))
            : (1000,loc('Inhaltswort','content word'));
        $weights{$term}={points=>$points,kind=>$kind};
    }
    return \%weights;
}

# Exactly one edit on normalized whole words; short words are too ambiguous.
sub oneEdit {
    my ($a,$b)=@_;
    return 0 if length($a)<4 || length($b)<4 || $a eq $b;
    return 0 if abs(length($a)-length($b))>1;
    if (length($a)==length($b)) {
        my @diff=grep {substr($a,$_,1) ne substr($b,$_,1)} 0..length($a)-1;
        return 1 if @diff==1;
        return @diff==2 && $diff[1]==$diff[0]+1
            && substr($a,$diff[0],1) eq substr($b,$diff[1],1)
            && substr($a,$diff[1],1) eq substr($b,$diff[0],1);
    }
    ($a,$b)=($b,$a) if length($a)>length($b);
    my $i=0;
    $i++ while $i<length($a) && substr($a,$i,1) eq substr($b,$i,1);
    return substr($a,$i) eq substr($b,$i+1);
}

# Weighted matching: each metadata word can explain at most one fuzzy term.
# Augmenting paths retain higher-weight terms while finding alternative words.
sub assignSimilar {
    my ($term,$edges,$owner,$seen)=@_;
    for my $word (@{$edges->{$term} || []}) {
        next if $seen->{$word}++;
        if (!exists $owner->{$word} || assignSimilar($owner->{$word},$edges,$owner,$seen)) {
            $owner->{$word}=$term;
            return 1;
        }
    }
    return 0;
}

sub evaluate {
    my ($fields,$terms,$query,$mode,$weights)=@_;
    $weights ||= wordWeights($query,$terms);
    return unless @$terms;
    my %hit; my %words; my %reserved; my @why; my $exact=0;
    for my $key (sort keys %$fields) {
        my $label=loc(@{$LABEL{$key}});
        my $value=normal($fields->{$key}); next unless length $value;
        # Separators between related names are normalized to spaces; phrases are
        # not an operator in v0.1. Each query word must start a metadata word.
        my @words=split / +/, $value;
        $words{$_}=1 for @words;
        my @matched;
        for my $term (@$terms) {
            if (grep {index($_,$term)==0} @words) {
                $reserved{$_}=1 for grep {index($_,$term)==0} @words;
                $hit{$term}=$WEIGHT{$key} if !$hit{$term} || $hit{$term}<$WEIGHT{$key};
                push @matched,$term;
            }
        }
        push @why, "$label: " . join(', ',@matched) if @matched;
        if ($value eq $query && $key !~ /^(lyrics|comment|genre)$/) {
            $exact=100000 if $exact<100000;
            unshift @why,loc('Exakter %s','Exact %s',$label);
        }
    }
    return unless keys %hit;
    return if $mode ne 'or' && keys(%hit)!=@$terms;
    my $multiple=2000*(keys(%hit)-1);
    my $score=$exact+$multiple;
    my @contributions;
    for my $term (@$terms) {
        next unless exists $hit{$term};
        my $word=$weights->{$term};
        $score += $word->{points}+$hit{$term};
        push @contributions,loc('%s: %s (%s) + %s Feldpunkte','%s: %s (%s) + %s field points',$term,$word->{points},$word->{kind},$hit{$term});
    }
    push @why,loc('Wertung: ','Score: ').join(', ',@contributions);
    my %edges;
    my @missing=sort {$weights->{$b}{points}<=>$weights->{$a}{points} || $a cmp $b}
        grep {!exists $hit{$_}} @$terms;
    for my $term (@missing) {
        $edges{$term}=[grep {!$reserved{$_} && oneEdit($term,$_)} sort keys %words];
    }
    my %owner;
    assignSimilar($_,\%edges,\%owner,{}) for @missing;
    for my $word (sort keys %owner) {
        my $term=$owner{$word};
        my $bonus=int($weights->{$term}{points}*0.6);
        $score += $bonus;
        push @why,loc('Ähnlichkeit: %s ≈ %s (eine Buchstabenänderung): +%s Punkte','Similarity: %s ≈ %s (one edit): +%s points',$term,$word,$bonus);
    }
    push @why,loc('Mehrwortbonus: %s','Multiword bonus: %s',$multiple) if $multiple;
    push @why,loc('Exaktbonus: %s','Exact bonus: %s',$exact) if $exact;
    return {score=>$score,reason=>join('; ',@why)};
}

# All SQL fragments below are fixed application code. IDs/search are parameters.
sub columns {
    my ($type,$prefs)=@_;
    my ($table,$label,%fields);
    if ($type eq 'track') {
        $table='tracks'; $label='t.title';
        %fields=(title=>'t.title',album=>'(SELECT title FROM albums WHERE id=t.album)',
          artist=>"(SELECT GROUP_CONCAT(c.name, ' | ') FROM contributors c JOIN contributor_track ct ON ct.contributor=c.id WHERE ct.track=t.id)",
          genre=>"(SELECT GROUP_CONCAT(g.name, ' | ') FROM genres g JOIN genre_track gt ON gt.genre=g.id WHERE gt.track=t.id)",
          lyrics=>'t.lyrics',comment=>"(SELECT GROUP_CONCAT(value, ' | ') FROM comments WHERE track=t.id)");
    } elsif ($type eq 'album') {
        $table='albums'; $label='t.title';
        %fields=(album=>'t.title',artist=>"(SELECT GROUP_CONCAT(c.name, ' | ') FROM contributors c JOIN contributor_album ca ON ca.contributor=c.id WHERE ca.album=t.id)",
          lyrics=>"(SELECT GROUP_CONCAT(lyrics, ' | ') FROM tracks WHERE album=t.id)",
          comment=>"(SELECT GROUP_CONCAT(c.value, ' | ') FROM comments c JOIN tracks tr ON tr.id=c.track WHERE tr.album=t.id)");
    } elsif ($type eq 'contributor') {
        $table='contributors'; $label='t.name'; %fields=(artist=>'t.name');
    } elsif ($type eq 'playlist') {
        $table='tracks'; $label='t.title'; %fields=(playlist=>'t.title');
    } elsif ($type eq 'work') {
        $table='works'; $label='t.title'; %fields=(title=>'t.title',artist=>'(SELECT name FROM contributors WHERE id=t.composer)');
    } else { die loc('Unbekannte Suchkategorie','Unknown search category'); }
    my @keys=grep {$prefs->{$_}} sort keys %fields;
    return ($table,$label,\@keys,join('', map {", $fields{$_} AS $_"} @keys));
}

sub search {
    my ($class,$dbh,$type,$query,$prefs)=@_;
    my $started=time;
    my $terms=tokens($query);
    my $weights=wordWeights($query,$terms);
    my $normalized=normal($query);
    my ($table,$label,$keys,$extra)=columns($type,$prefs);
    return {rows=>[],candidates=>0,ms=>0} unless @$terms && @$keys;
    # OR yields a conservative candidate set even for AND searches. Final field
    # verification is performed before LMS filters, counts and pagination.
    my @raw=grep {length} split /[^\pL\pN]+/, lc text($query);
    my %seen; my @variants=grep {!$seen{$_}++} (@$terms,@raw);
    my $match=join(' OR ',map {"type:$type $_*"} @variants);
    my $ids=$dbh->selectcol_arrayref('SELECT DISTINCT CAST(SUBSTR(id,33) AS INTEGER) FROM fulltext WHERE fulltext MATCH ?',undef,$match);
    my @ids=grep {defined && /^\d+$/ && $_>0} @$ids;
    my $count=@ids; my @result;
    while (@ids) {
        my @batch=splice(@ids,0,200);
        my $sql="SELECT t.id, $label AS label$extra FROM $table t WHERE t.id IN (".join(',',('?') x @batch).')';
        my $rows=$dbh->selectall_arrayref($sql,{Slice=>{}},@batch);
        for my $row (@$rows) {
            my %fields=map {$_=>$row->{$_}} @$keys;
            my $hit=evaluate(\%fields,$terms,$normalized,$prefs->{mode},$weights);
            next unless $hit;
            push @result,{%$hit,id=>0+$row->{id},label=>text($row->{label})};
        }
    }
    @result=sort {$b->{score}<=>$a->{score} || $a->{id}<=>$b->{id}} @result;
    return {rows=>\@result,candidates=>$count,ms=>int(1000*(time-$started))};
}
1;
