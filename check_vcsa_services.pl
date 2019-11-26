#!/usr/bin/perl

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

# nagios: -epn
# --
# check_vcsa_services - Check VCSA Services state
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

GetOptions(
    'hostname=s' => \my $Hostname,
    'username=s' => \my $Username,
    'password=s' => \my $Password,
    'help|?'     => sub { exec perldoc => -F => $0 or die "Cannot execute perldoc: $!\n"; },
) or Error("$0: Error in command line arguments\n");

sub Error {
    print "$0: " . $_[0] . "\n";
    exit 2;
}
Error('Option --hostname needed!') unless $Hostname;
Error('Option --username needed!') unless $Username;
Error('Option --password needed!') unless $Password;

use LWP::UserAgent;
my $ua = LWP::UserAgent->new();

$ua->ssl_opts(SSL_verify_mode => 0);
$ua->ssl_opts(verify_hostname => 0);

my $request = POST "https://$Hostname/rest/com/vmware/cis/session";
$request->authorization_basic($Username, $Password);
 
my $response = $ua->request($request);

my $content = $response->decoded_content;

my $token = decode_json($content)->{value};

my $url = "https://$Hostname/rest/appliance/vmon/service";

my $client = REST::Client->new();
$client->addHeader('vmware-api-session-id' => $token);
$client->GET($url);

my $res = decode_json($client->responseContent);

my $value = $res->{'value'};

my $not_running = 0;
my $not_running_msg;

foreach my $service (@$value){

	my $name = $service->{'key'};

	my $data = $service->{'value'};

	my $startup = $data->{'startup_type'};
	my $state = $data->{'state'};

	if(($startup eq "AUTOMATIC") && ($state ne "STARTED")){
		$not_running++;
		if($not_running_msg){
			$not_running_msg .= ", $name";
		} else {
			$not_running_msg = $name;
		}
	}

}

if($not_running ne 0){
	print "CRITICAL: $not_running services not running:\n";
	print $not_running_msg . "\n";
	exit 2;
} else {
	print "OK: all services running\n";
	exit 0;
}
