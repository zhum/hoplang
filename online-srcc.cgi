#!/usr/bin/perl

use CGI;

my %json_files=(
  '/tmp/hopsa-web-srcc-ganglia.json' => 'g',
  '/tmp/hopsa-web-srcc.json' => 'u'
  );

my $cgi=new CGI;
my $mode=$cgi->param('mode');

sub min($$){return ($_[0]>$_[1])?$_[1]:$_[0];}
sub max($$){return ($_[0]>$_[1])?$_[0]:$_[1];}

sub mkdata($$){

  if($_[0] eq 'g'){# ganglia data
    $_[1] =~ s/,"/,"g_/
  }
  return $_[1]
}


print CGI::header(-type=>'text/j-son',
             -pragma=>'No-Cache',
             -charset=>'utf-8');

#if($mode eq 'received_IB' or 1){

foreach $f (keys(%json_files)){
  $chapter='unknown';
  open(F,"<$f") or next;
  while(<F>){
    chomp;
#    print $_;
#"sent_IB":{"-":"-","10_0_101_22":["#ffffff",0]
    if(/^\{?\"(\w+)\":\{/){
      $chapter=$1;
      next;
    }
    elsif(/"min":([0-9.eE+-]+)/){
      if(exists($min{$chapter})){
        $min{$chapter}=min($min{$chapter},$1);
      }
      else{
        $min{$chapter}=$1;
      }
#      warn "MIN: $min{$chapter}\n";
    }
    elsif(/"max":([0-9.eE+-]+)/){
      if(exists($max{$chapter})){
        $max{$chapter}=max($max{$chapter},$1);
      }
      else{
        $max{$chapter}=$1;
      }
    }
    elsif(/\}$/){
      if(/^,/){
        push @{$data{$chapter}}, mkdata($json_files{$f},substr($_, 1,-1));
      }
      else{
        push @{$data{$chapter}}, mkdata($json_files{$f},substr($_, 0,-1));
      }
    }
    elsif(/\},$/){
      push @{$data{$chapter}}, mkdata($json_files{$f},substr($_, 1,-2));
    }
    elsif(/^,/){
      push @{$data{$chapter}}, mkdata($json_files{$f},substr($_, 1));
    }
  }
  close F;
}

$joiner='';
print "{\n";
foreach $chapter (keys(%data)){
  print $joiner;
  $joiner=',';
  print "\"$chapter\":{\n";
  foreach $line (@{$data{$chapter}}){
    print $line,",\n";
  }
  print "\"max\":$max{$chapter},\n\"min\":$min{$chapter}\n}\n";
}
print "}\n";

