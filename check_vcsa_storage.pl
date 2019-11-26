#!/usr/bin/perl

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

# nagios: -epn
# --
# check_vcsa_storage - Check VCSA Storage Usage
# Copyright (C) 2019 Alexander Krogloth, git@krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

use strict;
use warnings;

use REST::Client;
use Data::Dumper;
use Getopt::Long;
use JSON;
use HTTP::Request::Common;
use POSIX qw(strftime);

GetOptions(
    'hostname=s' => \my $Hostname,
    'username=s' => \my $Username,
    'password=s' => \my $Password,
    'warning=i' => \my $Warning,
    'critical=i' => \my $Critical,
    'exclude=s'             =>  \my @excludelistarray,
    'help|?'     => sub { exec perldoc => -F => $0 or die "Cannot execute perldoc: $!\n"; },
) or Error("$0: Error in command line arguments\n");

my %Excludelist;
@Excludelist{@excludelistarray}=();
my $excludeliststr = join "|", @excludelistarray;

sub Error {
    print "$0: " . $_[0] . "\n";
    exit 2;
}
Error('Option --hostname needed!') unless $Hostname;
Error('Option --username needed!') unless $Username;
Error('Option --password needed!') unless $Password;
Error('Option --warning needed!') unless $Warning;
Error('Option --critical needed!') unless $Critical;

use LWP::UserAgent;
my $ua = LWP::UserAgent->new();

$ua->ssl_opts(SSL_verify_mode => 0);
$ua->ssl_opts(verify_hostname => 0);

my $request = POST "https://$Hostname/rest/com/vmware/cis/session";
$request->authorization_basic($Username, $Password);
 
my $response = $ua->request($request);

my $content = $response->decoded_content;

my $token = decode_json($content)->{value};

my $startTime = strftime "%Y-%m-%dT%H:%M:%S.000Z", gmtime ( time - 1800);
my $endTime = strftime "%Y-%m-%dT%H:%M:%S.000Z", gmtime;

my @storage = ( "boot", "root", "archive", "swap", "autodeploy", "imagebuilder", "db", "seat", "netdump", "dblog", "core", "log", "updatemgr" );

my $query_string;
my $count = 1;

foreach (@storage){
	$query_string .= "&item.names.$count=storage.used.filesystem.$_";
	$count++;
	$query_string .= "&item.names.$count=storage.totalsize.filesystem.$_";
	$count++;
}

my $url = "https://$Hostname/rest/appliance/monitoring/query?item.interval=MINUTES5&item.function=MAX&item.start_time=$startTime&item.end_time=$endTime&$query_string";

my $client = REST::Client->new();
$client->addHeader('vmware-api-session-id' => $token);
$client->GET($url);

my $res = decode_json($client->responseContent);

my $value = $res->{'value'};

my %storage;

foreach my $filesystem (@$value){

	my $name = $filesystem->{'name'};

        if (($excludeliststr) && ($name =~ m/$excludeliststr/)){
		next;
	}
	
	my (undef, $type, undef, $fs) = split(/\./, $name);

	my $data_value;
	
	use Scalar::Util qw(looks_like_number);

	my $data_points = $filesystem->{'data'};

	foreach (@$data_points){

		if(looks_like_number($_)){
			$data_value = $_;
		}
	}

	$storage{$fs}{$type} = $data_value;

}

my @critical_fs;
my @warning_fs;
my @ok_fs;

my $crit_msg;
my $warn_msg;
my $ok_msg;

foreach my $fs (keys %storage){

	my $used = $storage{$fs}{'used'};
	my $total = $storage{$fs}{'totalsize'};

	my $percent = $used/$total*100;
	$percent = sprintf("%.2f", $percent);

	if($percent > $Critical){
		push(@critical_fs, $fs);
		$crit_msg .= "$fs ($percent %), ";
	} elsif($percent > $Warning){
		push(@warning_fs, $fs);
		$warn_msg .= "$fs ($percent %), ";
	} else {
		push(@ok_fs, $fs);
		$ok_msg .= "$fs ($percent %), ";
	}

	$storage{$fs}{percent} = $percent;

}

chop($crit_msg) if $crit_msg;
chop($warn_msg) if $warn_msg;
chop($ok_msg);

if(scalar @critical_fs){
	print "CRITICAL: ";
	print "$crit_msg\n";
	print "WARNING: $warn_msg\n" if $warn_msg;
	print "OK: $ok_msg\n" if $ok_msg;
	exit 2;
} elsif(scalar @warning_fs){
        print "WARNING: ";
        print "$warn_msg\n";
	print "OK: $ok_msg\n" if $ok_msg;
        exit 1;
} else {
        print "OK: ";
        print $ok_msg . "\n";
	exit 0;
}
