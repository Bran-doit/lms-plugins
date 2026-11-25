use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../..";
use JSON::XS;
use Plugins::DBRepair::Check;
my ($database,$output,$mode,$label,$contextPath)=@ARGV;
my $context={};
if ($contextPath) {open my $c,'<:raw',$contextPath or die $!;local $/;$context=decode_json(<$c>);close $c;}
my $result;
if ($mode eq 'compare') {require Plugins::DBRepair::Compare;$result=Plugins::DBRepair::Compare::run($database,$context->{backup_path},$label,$context);}
else {$result=Plugins::DBRepair::Check::run($database,$mode,$label,$context);}
require Plugins::DBRepair::Evidence;
eval {Plugins::DBRepair::Evidence::enrich($result);1} or $result->{evidence_error}="$@";
open my $fh,'>:raw',"$output.tmp" or die $!;
print {$fh} encode_json($result) or die $!;
close $fh or die $!;
rename "$output.tmp",$output or die $!;
