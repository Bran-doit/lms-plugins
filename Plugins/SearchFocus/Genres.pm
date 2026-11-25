package Plugins::SearchFocus::Genres;
use strict;
use warnings;
use utf8;
use Plugins::SearchFocus::I18N qw(loc language);
use Plugins::SearchFocus::Engine;

# Deliberately small equivalence list; spelling variants are not musical synonyms.
sub canonical {
    my $word=shift;
    return 'klassik' if $word =~ /^(classic|klassic|klassik)$/;
    return $word;
}
sub words { return [map {canonical($_)} split / +/, Plugins::SearchFocus::Engine::normal($_[0])]; }
sub quality {
    my ($query,$word)=@_;
    return 1000 if $query eq $word;
    my @variants=$word eq 'klassik' ? qw(klassik classic klassic) : ($word);
    return 800 if grep {index($_,$query)==0} @variants;
    my @queries=$query eq 'klassik' ? qw(klassik classic klassic) : ($query);
    for my $q (@queries) {
        return 600 if grep {Plugins::SearchFocus::Engine::oneEdit($q,$_)} @variants;
    }
    return 0;
}
sub score {
    my ($name,$query,$hide,$known)=@_;
    return if length(Plugins::SearchFocus::Engine::text($query))>256;
    my $q=words($query);
    return unless @$q && @$q<=12;
    my @parts=grep {length} split /\s*[-+\/&\x{2013}\x{2014}]\s*/, Plugins::SearchFocus::Engine::text($name);
    if (@parts==1 && $known) {
        my $components=words($parts[0]);
        @parts=@$components if @$components>1 && !grep {!$known->{$_}} @$components;
    }
    my @tokens;
    for my $i (0..$#parts) { push @tokens,map {{word=>$_,part=>$i}} @{words($parts[$i])}; }
    return unless @tokens;
    # Dynamic programming: one candidate word per query word, no double counting.
    my %states=(0=>{sum=>0,parts=>{},fuzzy=>0});
    for my $token (@tokens) {
        my %next=%states;
        for my $mask (keys %states) {
            for my $i (0..$#$q) {
                next if $mask & (1<<$i);
                my $quality=quality($q->[$i],$token->{word});
                next unless $quality;
                my $new=$mask | (1<<$i);
                my $sum=$states{$mask}{sum}+$quality;
                my %parts=(%{$states{$mask}{parts}},$token->{part}=>1);
                my $candidate={sum=>$sum,parts=>\%parts,fuzzy=>$states{$mask}{fuzzy}+($quality==600?1:0)};
                if (!$next{$new} || $sum>$next{$new}{sum}
                    || ($sum==$next{$new}{sum} && scalar(keys %parts)>scalar(keys %{$next{$new}{parts}}))) {
                    $next{$new}=$candidate;
                }
            }
        }
        %states=%next;
    }
    my $best=$states{(1<<@$q)-1} or return;
    my $mixed=@parts>1;
    my $targeted=scalar(keys %{$best->{parts}})==@parts;
    return if $hide && $mixed && !$targeted;
    my $base=!$mixed ? (@$q==@tokens ? 1000 : 800)
        : $targeted ? 1000 : exists($best->{parts}{0}) ? 800 : 400;
    my $points=int($base*$best->{sum}/(@$q*1000));
    return {score=>$points,reason=>($mixed ? ($targeted?loc('Mischgenre gezielt','Explicit compound genre'):loc('Mischgenre, Bestandteil','Compound genre component')):loc('Eigenständiges Genre','Standalone genre'))
        .loc('; Grundgewicht: ','; Base weight: ').$base.loc('; Tippfehler: ','; Typos: ').$best->{fuzzy}.loc('; Varianten classic/klassic/klassik gleichwertig','; classic/klassic/klassik are equivalent')};
}
sub rank {
    my ($rows,$query,$hide)=@_;
    # Fixed genre components: classification must not change with client filters.
    my %known=map {$_=>1} qw(klassik jazz rock pop blues country soul funk reggae techno house metal folk gospel electronic ambient hiphop);
    my @ranked;
    for my $row (@$rows) { my $rating=score($row->{genre},$query,$hide,\%known); push @ranked,{%$row,%$rating} if $rating; }
    return [sort {$b->{score}<=>$a->{score} || $a->{id}<=>$b->{id}} @ranked];
}

my ($originalGenres,$originalSearch,$config,$installed);
sub install {
    $config=shift;
    return if $installed;
    $originalGenres=Slim::Control::Request::addDispatch(['genres','_index','_quantity'],[0,1,1,\&genresQuery]);
    $originalSearch=Slim::Control::Request::addDispatch(['search','_index','_quantity'],[0,1,1,\&searchQuery]);
    $installed=1;
}
sub uninstall {
    return unless $installed;
    Slim::Control::Request::addDispatch(['genres','_index','_quantity'],[0,1,1,$originalGenres]);
    Slim::Control::Request::addDispatch(['search','_index','_quantity'],[0,1,1,$originalSearch]);
    $installed=0;
}
sub installed { return $installed?1:0; }
sub enabled { my $c=$config->(); return $c->{enabled} && $c->{genre_fuzzy}; }
# Original genre query applies all LMS filters before ranking and pagination.
sub candidates {
    my ($request,$general,$search)=@_;
    my $child=Slim::Control::Request->new($request->clientid,['genres','0','2147483647']);
    my $params=$request->getParamsCopy;
    if ($general) {
        my $library=Slim::Music::VirtualLibraries->getRealId($params->{library_id})
            || Slim::Music::VirtualLibraries->getLibraryIdForClient($request->client);
        $child->addParam('library_id',$library) if $library;
    } else {
        for my $key (keys %$params) {
            next if $key =~ /^_/ || $key eq 'search' || $key eq 'tags';
            $child->addParam($key,$params->{$key});
        }
    }
    $child->addParam('tags','s');
    $child->addParam('search',$search) if defined $search;
    $originalGenres->($child);
    return $child->getResults;
}
sub page {
    my ($request,$rows)=@_;
    my ($valid,$start,$end)=$request->normalize(scalar($request->getParam('_index')),scalar($request->getParam('_quantity')),scalar(@$rows));
    return [] unless $valid;
    return [@$rows[$start..$end]];
}
sub genresQuery {
    my $request=shift;
    my $query=$request->getParam('search');
    return $originalGenres->($request) unless enabled() && defined($query) && length($query)
        && !defined($request->getParam('genre_id'));
    my $data=candidates($request,0);
    my $rows=rank($data->{genres_loop}||[],$query,$config->()->{genre_hide_mixed});
    my $tags=$request->getParam('tags')||'';
    $request->addResult('rescan',$data->{rescan}) if $data->{rescan};
    $request->addResult('count',scalar @$rows);
    if ($tags =~ /Z/) {
        my @index;
        for my $row (@$rows) {
            my $letter=$row->{textkey}||substr($row->{genre},0,1);
            if (@index && $index[-1][0] eq $letter) { $index[-1][1]++; }
            else { push @index,[$letter,1]; }
        }
        $request->addResult('indexList',\@index);
    }
    if ($tags ne 'CC' && $tags !~ /ZZ/) {
        my $i=0;
        for my $row (@{page($request,$rows)}) {
            for my $key (qw(id genre favorites_url)) { $request->addResultLoop('genres_loop',$i,$key,$row->{$key}) if defined $row->{$key}; }
            $request->addResultLoop('genres_loop',$i,'textkey',$row->{textkey}) if $tags =~ /s/;
            $i++;
        }
    }
    $request->setStatusDone;
}
sub searchQuery {
    my $request=shift;
    $originalSearch->($request);
    return unless defined $request->getResult('count');
    my $query=$request->getParam('term');
    return unless enabled() && defined($query) && length($query);
    my $data=candidates($request,1);
    my $rows=rank($data->{genres_loop}||[],$query,$config->()->{genre_hide_mixed});
    # The original search omits category counts on pages beyond that category.
    my $old=$request->getResult('genres_count');
    unless (defined $old) {
        my $probe=Slim::Control::Request->new($request->clientid,['search','0','1']);
        my $params=$request->getParamsCopy;
        $probe->addParam($_,$params->{$_}) for grep {$_ !~ /^_/} keys %$params;
        $originalSearch->($probe);
        $old=$probe->getResult('genres_count')||0;
    }
    my $results=$request->getResults;
    delete $results->{genres_loop};
    $request->addResult('genres_count',scalar @$rows);
    $request->addResult('count',($request->getResult('count')||0)-($old||0)+@$rows);
    my $i=0;
    for my $row (@{page($request,$rows)}) {
        $request->addResultLoop('genres_loop',$i,'genre_id',$row->{id});
        $request->addResultLoop('genres_loop',$i,'genre',$row->{genre});
        $i++;
    }
}
1;
