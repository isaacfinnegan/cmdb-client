#!/usr/bin/perl
# $Id $

package CMDB::Client;
use Exporter ();
use strict;
use vars qw(
  $VERSION
  @ISA
  @EXPORT
  @EXPORT_TAGS
  @EXPORT_OK);
@ISA    = qw(Exporter);
@EXPORT = qw(
&getRecords
&getRecs
&saveRec
&saveRecord
&getCustomer
&make_json
&eat_json
);
our %EXPORT_TAGS = ( ALL => [ @EXPORT, @EXPORT_OK ] );

use strict;
use JSON;
use Getopt::Std;
use LWP::UserAgent;
use Optconfig;
my @savedARGV=@ARGV;
@ARGV=[];
    my $opt = Optconfig->new('cmdbclient', { 'cmdbclient-http=s' => 'https',
                                      'cmdbclient-host=s' => 'cmdb',
                                      'cmdbclient-realm=s' => 'Authorized Access Only',
                                      'cmdbclient-api_path=s' => '/cmdb_api/v1/',
                                      'cmdbclient-debug' => 0,
                                      'cmdbclient-timeout' => 320,
                                      'cmdbclient-user=s' => 'readonly',
                                      'cmdbclient-pass=s' => 'readonly'
                                   });

@ARGV=@savedARGV;
my $http  = $opt->{'cmdbclient-http'};
my $host=$opt->{'cmdbclient-host'};
my $api_path=$opt->{'cmdbclient-api_path'};
my $api = $api_path . 'system/';
my $req_type   = "application/json";
my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
$ua->timeout($opt->{'cmdbclient-timeout'});
my @failures;
my $DEBUG=0;
if($ENV{CMDB_DEBUG} || $opt->{'cmdbclient-debug'})
{
	$DEBUG=1;
}


=head1 NAME

CMDB::Client - Perl module interface to cmdb for fetching and saving entities (most commonaly systems) 

=head1 SYNOPSIS

   use CMDB::Client;

   my $recs = getRecs('system',{fqdn=>somesystem.com},{});
	# returns arrayref of hashes
   my $return_str = saveRec('system',\%hash,$entity_key,
		{user=>'username', pass=>'password'});

=head1 DESCRIPTION

This module accesses the cmdb rest API to fetch records vi query (not via full resource path) 
and can save records using the REST PUT method.  The getRecs function defaults to a readonly user if no
config is supplied.  The saveRec function will return error if no user config is supplied.


=head1 AUTHOR

Isaac Finnegan, E<lt>isaacfinnegan@gmail.comE<gt>

=cut



# my %opt;
# getopts('q:h:du',\%opt);
# my $DEBUG = $opt{'d'} ? 1 : 0;
# my $UPDATE = $opt{'u'} ? 1 : 0;
# my $QUERY = $opt{'q'} ? $opt{'q'} : "";
my $full_url   = "$http://$host$api";

my $entity_keys={
	system=>'fqdn',
	device=>'fqdn',
	router=>'fqdn',
	change_queue=>'id',
	inv_audit=>'entity_key',
	user=>'username',
	acl=>'acl_id',
	inv_normalizer=>'id',
	role=>'role_id',
	drac=>'drac_id',
	processor=>'cpu_id',
	blade_chassis=>'fqdn',
	network_switch=>'fqdn',
	load_balancer=>'fqdn',
	power_strip=>'fqdn',
	datacenter_subnet=>'subnet',
	snat=>'comkey',
	pool=>'comkey',
	vip=>'comkey',
	cluster_mta=>'cluster_id',
	cluster=>'cluster_id',
	device_ip=>'ip_address'	
};


################################################

=pod

=item getRecords

This function is deprecated, use getRecs

=cut

sub getRecords{
	my $params=shift;
	my $url=shift || $full_url;
	my $results;
	my $query='?_format=json';
	foreach(keys(%$params))
	{
		$query.="&$_=$$params{$_}";
	}
	#$query=~s/\*/\%/g;
	print STDERR "fetching: $url$query\n" if $DEBUG;
	my $port= $http eq 'http' ? '80' : '443';
	my $user= $opt->{'cmdbclient-user'};
	my $pass= $opt->{'cmdbclient-pass'};
	$ua->credentials("$host:$port",'Authorized Personnel Only',$user,$pass);
	my $response = $ua->get( "$url$query" );
    if ( $response->code == 200 ) {
		print STDERR "received:" . $response->content . "\n" if $DEBUG;
		if($response->content)
		{
			$results=eat_json($response->content,{allow_nonref=>1,relaxed=>1,allow_unknown=>1}); 
		}
	}
else
{
	print STDERR $response->code . ": " . $response->content . "\n" if $DEBUG;
}
	return $results;
}

=pod

=item getRecs

This function is used to query for entity records from cmdb.  Any entity can be queried. 
	
	getRecs($entity_name, \@query,\%config)
	 or
	getRecs($entity_name, \%query,\%config)

$entity_name = just a straight string name of the entity 
Example:
	system
	cluster
	service_instance

\@query
Array ref of query strings.   This is the most flexible way to query, as nonstandard 
operators ( ~ !~ > < ) can be used.
Example:
	[" system_type ~ POD|Eng",
	" data_center_code ~ SC4|TOR6 ",
	" agent_reported > 2011-05-01 "]

\%query
Hash of key/value query parameters.  All key/value are = sign operator queries.
Example: 
	{
		system_type=>"POD",
		data_center_code=>"SC4"
	}


\%config
The configuration hashref is optional for getRecs but can contain the following parameters:
	user	Username. Defaults to 'readonly'
	pass	Password. Defaults to 'readonly'
	path	URL Path. Defatuls to current version api path.  (Currently '/inv_api/v1/' )
	host	API Host. Defaults to cmdb.example.com (backend api server)
	http	HTTP Method to use. Defaults to 'http'
	port	HTTP Port to use. Defaults to 80
	format	Data return format URL parameter to pass to the REST API. Defaults to JSON (only current option)

=cut

sub getRecs{
	my($entity,$qparms,$config)=@_;
	$config=$config || {};
	my $query_str="?_format=";
	$query_str.= $config->{'format'} || 'json';
	my $hostname=$config->{'host'} || $host;
	my $http_method=$config->{'http'} || $http;
	my $port= $http_method eq 'http' ? '80' : '443';
	my $path=$config->{'path'} || $api_path;
    my $realm= $config->{'realm'} || $opt->{'cmdbclient-realm'};
	my $user=$config->{'user'} || $opt->{'cmdbclient-user'};
	my $pass=$config->{'pass'} || $opt->{'cmdbclient-pass'};
	$ua->credentials("$hostname:$port",$realm,$user,$pass);
	my $url = "$http_method://$hostname$path$entity/";
	my $results;
	if(ref $qparms eq 'HASH') {
		foreach(keys(%$qparms))
		{
			$query_str.="&$_=$qparms->{$_}";
		}
	}
	elsif(ref $qparms eq 'ARRAY') {
		foreach my $item (@$qparms) {
			next unless $item =~ /(\w+)([!~>=<]+)(.*)/;
			my $key = $1;
			my $op = $2;
			my $val = $3;
			$query_str.="&${key}${op}${val}";
		}
	}
	print STDERR "fetching: $url$query_str\n" if $DEBUG;
	my $response = $ua->get( "$url$query_str" );
    if ( $response->code == 200 ) {
		print STDERR "received:" . $response->content . "\n" if $DEBUG;
		if($response->content)
		{
			$results=eat_json($response->content,{allow_nonref=>1,relaxed=>1,allow_unknown=>1}); 
		}		
	}
	else
	{
		print STDERR "received code:" . $response->code . " " .  $response->content . "\n" if $DEBUG;		
	}
	return $results;
}

=pod

=item saveRec

This function is used to save a single record using the cmdb REST API. Any entity can be saved
	
	saveRec($entity_name, \%record,$key, \%config)

$entity_name = just a straight string name of the entity 
Example:
	system
	cluster
	service_instance

\%record
A hash ref to the fields being changed.  All fields do not need to be submitted to save a record.  If
the record is new then any fields required by the API will need to be present in the hash.

$key
Optional parameter to specify the entity key used in the REST PUT 

\%config
The configuration hashref is required for saveRec and can contain the following parameters:
	user	Username. has no default, this function will error out if no username is supplied'
	pass	Password. has no default, this function will error out if no password is supplied''
	updateonly	If this is set (updateonly=>1) then the function will not try to create the record if 
it does not exist
	key 	The key to use to save the entity against (needed for REST)
	path	URL Path. Defatuls to current version api path.  (Currently '/inv_api/v1/' )
	host	API Host. Defaults to cmdb.example.com (backend api server)
	realm	HTTP Auth Realm. Defaults to 'Authorized Personnel Only'
	http	HTTP Method to use. Defaults to 'http'
	port	HTTP Port to use. Defaults to 80
	format	Data return format URL parameter to pass to the REST API. Defaults to JSON (only current option)

=cut

sub saveRec{
	my($entity,$rec,$rec_key,$config)=@_;
	$config=$config || {};
	return 'error: user and pass required'	unless($config->{'user'} && $config->{'pass'});
	my $hostname=$config->{'host'} || $host;
	my $http_method=$config->{'http'} || $http;
	my $port= $http_method eq 'http' ? '80' : '443';
	my $path=$config->{'path'} || $api_path;
	my $realm=$config->{'realm'} || $opt->{'cmdbclient-realm'};
	my $user=$config->{'user'} || $opt->{'cmdbclient-user'};
	my $pass=$config->{'pass'} || $opt->{'cmdbclient-pass'};
	my $key=$config->{'key'} || $entity_keys->{$entity};
	my $json=make_json($rec);
	$rec_key=$rec_key || $rec->{$key};
	return 'error: key needed for this entity' unless($key);
	$ua->credentials("$hostname:$port",$realm,$user,$pass);
	my $url = "$http_method://$hostname$path$entity/";
    my $response = $ua->get( "$url$rec_key" );
 	print STDERR "got " . $response->code . " for $url$rec_key\n" if $DEBUG;
   if ( $response->code == 200 ) {
	#return "found in cmdb";
        # UPDATE
        my $request = HTTP::Request->new('PUT' => "$url$rec_key");
        $request->content_type('application/json');
        $request->content ($json);
        $response = $ua->request($request);
        
        if( $response->is_success ){
            return " $entity($rec_key) updated successfully.";
        } else {
            return "failed to update $entity($rec_key)" . $response->content;
	#	return 'error';
            #print FAIL "$json\n".$response->status_line.": ".$response->content."\n\n";
        }
    }
	else
	{
		if($config->{'updateonly'})
		{
			return 'no create:updateonly';
		}
		# CREATE
        my $request = HTTP::Request->new('POST' => $url);
        $request->content_type('application/json');
        $request->content ($json);
        $response = $ua->request($request);
        
        if( $response->is_success ){
            return "$entity($rec_key) successfully created.";
        } else {
            return "failed to create $entity($rec_key).  " . $response->content  . $json; 
		return 'error';
            #print FAIL "$json\n".$response->status_line.": ".$response->content."\n\n";
        }
        
	}
    $response = $ua->get( "$url$rec_key" );
    if ( $response->code != 200 ) {
		print STDERR "api says operation successful but no record found after\n" if $DEBUG;
		return "error";
	}
}




sub eat_json {
   my ($json_text, $opthash) = @_;
    return ($JSON::VERSION > 2.0 ? from_json($json_text, $opthash) : JSON->new()->jsonToObj($json_text, $opthash));
}

sub make_json {
   my ($obj, $opthash) = @_;
    return ($JSON::VERSION > 2.0 ? to_json($obj, $opthash) : JSON->new()->objToJson($obj, $opthash));
}
