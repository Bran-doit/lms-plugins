package Plugins::SearchFocus::Names;
use strict;
use warnings;
use utf8;
use Plugins::SearchFocus::I18N qw(loc language);
use Plugins::SearchFocus::Engine ();
use Time::HiRes qw(time);

our $DEFAULT_ALIASES = $Plugins::SearchFocus::Engine::DEFAULT_NAME_ALIASES;

sub normal { Plugins::SearchFocus::Engine::normal($_[0]); }
sub parseAliases {
    my $text=Plugins::SearchFocus::Engine::text($_[0]//'');
    die loc('Namensvarianten: maximal 32000 Zeichen','Name aliases: maximum 32000 characters') if length($text)>32000;
    my %rules; my $line=0; my $entries=0;
    for my $row (split /\r?\n/,$text) {
        $line++;
        next if $row =~ /^\s*(?:#|$)/;
        die loc('Namensvarianten: maximal 100 Einträge','Name aliases: maximum 100 entries') if ++$entries>100;
        my @fields=split /\|/,$row,-1;
        die loc('Namensvarianten, Zeile %s: Name | Nachname | Varianten erwartet','Name aliases, line %s: expected Name | Family name | Aliases',$line) unless @fields==3;
        my ($name,$family,$aliases)=map {s/^\s+|\s+$//gr} @fields;
        die loc('Namensvarianten, Zeile %s: Name fehlt oder ist zu lang','Name aliases, line %s: name missing or too long',$line) unless length($name) && length($name)<=256;
        my $key=normal($name);
        die loc('Namensvarianten, Zeile %s: gültiger Name fehlt','Name aliases, line %s: valid name missing',$line) unless length $key;
        die loc('Namensvarianten, Zeile %s: Name doppelt','Name aliases, line %s: duplicate name',$line) if exists $rules{$key};
        $family=normal($family);
        my @aliases=grep {length} map {normal($_)} split /;/,$aliases;
        die loc('Namensvarianten, Zeile %s: maximal 12 Varianten mit je 256 Zeichen','Name aliases, line %s: maximum 12 aliases of 256 characters each',$line) if @aliases>12 || grep {length($_)>256} @aliases;
        for my $variant ($key,@aliases) {
            die loc('Namensvarianten, Zeile %s: maximal 12 Wörter je Name','Name aliases, line %s: maximum 12 words per name',$line) if scalar(split / /,$variant)>12;
            die loc('Namensvarianten, Zeile %s: Nachname muss in jedem Namen vollständig vorkommen','Name aliases, line %s: family name must occur in full in every name',$line)
                if length($family) && index(" $variant "," $family ")<0;
        }
        $rules{$key}={family=>$family,aliases=>\@aliases};
    }
    return \%rules;
}
sub quality {
    my ($q,$word,$initialAllowed)=@_;
    return (100,loc('exakt','exact')) if $q eq $word;
    return (25,loc('Initiale','initial')) if $initialAllowed && length($q)==1 && length($word)>1 && index($word,$q)==0;
    return (80,loc('Wortanfang','word prefix')) if length($q)>1 && index($word,$q)==0;
    return (60,loc('Tippfehler','typo')) if Plugins::SearchFocus::Engine::oneEdit($q,$word);
    return (0,'');
}
sub scoreVariant {
    my ($name,$query,$terms,$family,$alias,$mode)=@_;
    my @words=split / /,$name;
    my %familyIndices;
    if (length $family) {
        my @f=split / /,$family;
        for my $i (0..$#words) {
            next if $i+@f>@words;
            if (join(' ',@words[$i..$i+$#f]) eq $family) { $familyIndices{$_}=1 for $i..$i+$#f; }
        }
    }
    my $hasAnchor=grep {length($_)>=4} @$terms;
    my %states=(0=>{score=>0,why=>[],anchor=>0});
    for my $i (0..$#words) {
        my %next=%states;
        for my $mask (keys %states) {
            for my $j (0..$#$terms) {
                next if $mask & (1<<$j);
                my ($quality,$kind)=quality($terms->[$j],$words[$i],$hasAnchor && !$familyIndices{$i});
                next unless $quality;
                # Only explicitly configured family names carry surname priority.
                my $weight=length($family) ? ($familyIndices{$i}?1000:250) : 1000;
                my $points=int($weight*$quality/100);
                my $new=$mask | (1<<$j);
                my $sum=$states{$mask}{score}+$points;
                my $anchor=$states{$mask}{anchor} || length($terms->[$j])>1;
                if (!$next{$new} || $sum>$next{$new}{score} || ($sum==$next{$new}{score} && $anchor && !$next{$new}{anchor})) {
                    $next{$new}={score=>$sum,anchor=>$anchor,why=>[@{$states{$mask}{why}},"$terms->[$j] → $words[$i]: $kind, +$points"]};
                }
            }
        }
        %states=%next;
    }
    my $best;
    for my $mask (sort {$a<=>$b} keys %states) {
        next unless $mask && ($states{$mask}{anchor} || $name eq $query);
        next if $mode ne 'or' && $mask!=(1<<@$terms)-1;
        my $count=unpack('%32b*',pack('L',$mask));
        my $score=$states{$mask}{score}+2000*($count-1);
        my $exact=$name eq $query;
        $score+=100000 if $exact;
        $score=int($score*0.9) if $alias;
        if (!$best || $score>$best->{score}) {
            $best={score=>$score,reason=>join('; ',($alias?loc('Personenspezifische Variante','Person-specific alias'):loc('Vorhandener Name','Library name')),
                ($exact?loc('Vollständiger Name','Full name'):()),@{$states{$mask}{why}},
                ($count>1?loc('Mehrwortbonus: ','Multiword bonus: ').(2000*($count-1)):()),($alias?loc('Variantenfaktor: 90 %','Alias factor: 90 %'):()))};
        }
    }
    return $best;
}
sub rank {
    my ($rows,$query,$config)=@_;
    my $terms=Plugins::SearchFocus::Engine::tokens($query);
    return [] unless @$terms;
    my $normalized=normal($query);
    my $rules=parseAliases($config->{name_aliases});
    my @result;
    for my $row (@$rows) {
        my $name=normal($row->{name});
        my $rule=$rules->{$name} || {family=>'',aliases=>[]};
        my $best=scoreVariant($name,$normalized,$terms,$rule->{family},0,$config->{mode}||'and');
        for my $alias (@{$rule->{aliases}}) {
            next if $alias eq $name;
            my $hit=scoreVariant($alias,$normalized,$terms,$rule->{family},1,$config->{mode}||'and');
            $best=$hit if $hit && (!$best || $hit->{score}>$best->{score});
        }
        push @result,{%$best,id=>0+$row->{id},label=>Plugins::SearchFocus::Engine::text($row->{name})} if $best;
    }
    return [sort {$b->{score}<=>$a->{score} || $a->{id}<=>$b->{id}} @result];
}
sub search {
    my ($class,$dbh,$query,$config)=@_;
    my $start=time;
    # Read the existing names, including composers. LMS applies client/role filters later.
    my $rows=$dbh->selectall_arrayref('SELECT id,name FROM contributors',{Slice=>{}});
    my $result=rank($rows,$query,$config);
    return {rows=>$result,candidates=>scalar(@$rows),ms=>int((time-$start)*1000)};
}
1;