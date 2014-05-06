#!/usr/bin/env perl

#use the information in ldap.employee_ids to update AD employee id entries.

use strict;
use warnings;
use DBI;
use Net::LDAPS;
use Encode;

my %config = do '/secret/actian.config';

my($ldap) = Net::LDAPS->new($config{'host'}) or die "Can't bind to ldap: $!\n";

my $mesg=$ldap->bind(
	dn      => "$config{'username'}",
	password => "$config{'password'}",
);  

if($mesg->error eq 'Success'){
}else{  
	print "check AD credentials\n";
	print $mesg->error;
}

my $my_cnf = '/secret/my_cnf.cnf';

my $dbh = DBI->connect("DBI:mysql:"
	. ";mysql_read_default_file=$my_cnf"
	.';mysql_read_default_group=ldap',
	undef,
	undef
) or die "something went wrong ($DBI::errstr)";

$dbh->{'mysql_enable_utf8'} = 1;
$dbh->do('SET NAMES utf8');


my $q = $dbh->prepare("select * from employee_ids");
$q->execute;

my %eid;

while(my @row = $q->fetchrow_array){
	my $a = decode_utf8($row[2]);
	my $b = encode_utf8($a);

	#$eid{dn}=eid
	$eid{$b}=$row[0];
}

my $input;

foreach my $dn (sort keys %eid){
	print "$dn $eid{$dn}\n";
	my $result=$ldap->modify($dn,
		replace => {
			employeeID => $eid{$dn},
		}
	);
	print $result->error,"\n";
	$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
}

$ldap->unbind;
