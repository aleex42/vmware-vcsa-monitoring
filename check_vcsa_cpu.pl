#!/usr/bin/perl

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
$ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS} = 'Net::SSL';

# nagios: -epn
# --
# check_vcsa_cpu - Check VCSA CPU Usage
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
    'help|?'     => sub { exec perldoc => -F => $0 or die "Cannot execute perldoc: $!\n"; },
) or Error("$0: Error in command line arguments\n");

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

my $startTime = strftime "%Y-%m-%dT%H:%M:%S.000Z", gmtime ( time - 200);
my $endTime = strftime "%Y-%m-%dT%H:%M:%S.000Z", gmtime;

my $url = "https://$Hostname/rest/appliance/monitoring/query?item.interval=MINUTES5&item.function=MAX&item.start_time=$startTime&item.end_time=$endTime&item.names.1=cpu.util";

my $client = REST::Client->new();
$client->addHeader('vmware-api-session-id' => $token);
$client->GET($url);

my $res = decode_json($client->responseContent);

my $value = $res->{'value'};

my $cpu_percent = @$value[0]->{'data'}[0];
$cpu_percent = sprintf("%.2f", $cpu_percent);

if($cpu_percent > $Critical){
	print "CRITICAL: CPU Usage $cpu_percent %\n";
	exit 2;
} elsif($cpu_percent > $Warning){
	print "WARNING: CPU Usage $cpu_percent %\n";
	exit 1;
} else {
	print "OK: CPU Usage $cpu_percent %\n";
	exit 0;
}
