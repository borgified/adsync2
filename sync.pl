#!/usr/bin/env perl

use strict;
use warnings;
use Text::CSV;
use Data::Dumper;
use DBI;
use Net::LDAPS;
use Locale::Country;
use Encode;

my $file = $ARGV[0] or die "need csv input file\n";

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


my $csv = Text::CSV->new ({
		binary		=> 1,
		auto_diag	=> 1,
		sep_char	=> ',',
	});

open(my $data, '<:encoding(utf8)', $file) or die "couldnt open file $!\n";


my %employees;
my @header;

#mappings CSV:AD

#First Name: givenName
#Preferred Name: displayName
#Last Name: sn
#Employee Id: employeeID
#Job title: title
#Business Unit: company
#Home Department: department.description
#Location: c-st-physicalDeliveryOfficeName
#Work Phone: telephoneNumber
#Work Fax: facsimileTelephoneNumber
#Work Email: mail
#Manager ID: none but will be linked to manager
#Mngr. FName: ignored
#Mngr. MName: ignored
#Mngr. LName: ignored


while(my $fields = $csv->getline($data)){

	#detect if the first field starts with 'Employee Name' if so, then this is
	#our header we'll use it as the key for our hash.
	my $x=0;

	if(${$fields}[0] eq 'First Name'){
		@header=@{$fields};
		next;
	}else{

		foreach my $field (@{$fields}){
			#${$fields}[3] is eeid
			$employees{"${$fields}[3]"}{"$header[$x]"}="$field";
			$x++;
		}

	}
}

#print Dumper(\%employees);exit;

unless($csv->eof){
	$csv->error_diag();
}

close($data);


#now time to update AD

#first find the employee by their employee id
#we're going to make use of the work we did in another script (dumpad.pl)
#and query the database for info rather than going to AD directly.

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

my %db;

while(my @row = $q->fetchrow_array){
	my $a = decode_utf8($row[2]);
	my $b = encode_utf8($a);

	#$db{dn}=eid
	$db{$row[0]}=$b;
}




my $query = $dbh->prepare("select * from ldap where eid = ?");

foreach my $eid (keys(%employees)){
	my $rv=$query->execute($eid);
	my($dn,$title,$department,$description,$mail,$sam,$givenName,$sn,$displayname,$company,$c,$st,$physicalDeliveryOfficeName,$telephoneNumber,$facsimileTelephoneNumber,$manager,$l,$upn,$name,$eid) = $query->fetchrow_array;
	if($rv != 1){
		die "\nI failed to find ($eid) in AD. Make sure AD has ($eid) set for ($employees{$eid}->{'Work Email'}) and that the contents of AD are dumped to ldap.ldap using dumpad.pl";
	}

	#make sure utf8 gets preserved
	$dn = encode_utf8(decode_utf8($dn));
	$title = encode_utf8(decode_utf8($title));
	$department = encode_utf8(decode_utf8($department));
	$description = encode_utf8(decode_utf8($description));
	$givenName = encode_utf8(decode_utf8($givenName));
	$sn = encode_utf8(decode_utf8($sn));
	$displayname = encode_utf8(decode_utf8($displayname));
	$company = encode_utf8(decode_utf8($company));
	$st = encode_utf8(decode_utf8($st));
	$physicalDeliveryOfficeName = encode_utf8(decode_utf8($physicalDeliveryOfficeName));
	$manager = encode_utf8(decode_utf8($manager));
	$l = encode_utf8(decode_utf8($l));
	$name = encode_utf8(decode_utf8($name));


	#lets check to make sure that all the data from ITRPT for this $eid matches with the current ldap values. if not, update it.


#my $result=$ldap->modify($dn,
#replace => {
#displayname => $employees{$email}{"Employee Name"},
#title => $employees{$email}{"Job title"},
#company => $employees{$email}{"Business Unit"},
#department => $dept,
#description => $desc,
#c => $country,
#physicalDeliveryOfficeName => $office_name,
#manager => $newmanager,
#}
#);
#print $result->error,"\n";
#$result->code && warn "failed to replace entry\n" && $input=<STDIN>;




	my $needs_update="";
	my $input;
	#-----------------------------------------
	if($employees{$eid}{'First Name'} ne $givenName){
		$needs_update=$needs_update."FN: $employees{$eid}{'First Name'},";
		my $result=$ldap->modify($dn, replace => { givenName => $employees{$eid}{'First Name'}});
		print $result->error,"\n";
		$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
	}
	#-----------------------------------------
	my $pref = $employees{$eid}{'Preferred Name'}." ".$employees{$eid}{'Last Name'};

	if($pref ne $displayname){
		$needs_update=$needs_update."PN: $pref,";
		my $result=$ldap->modify($dn, replace => { displayName => $pref});
		print $result->error,"\n";
		$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
	}
	#-----------------------------------------
	if($employees{$eid}{'Last Name'} ne $sn){
		$needs_update=$needs_update."LN: $employees{$eid}{'Last Name'},";
		my $result=$ldap->modify($dn, replace => { sn => $employees{$eid}{'Last Name'}});
		print $result->error,"\n";
		$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
	}
	#-----------------------------------------
	if($employees{$eid}{'Job title'} ne $title){
		$needs_update=$needs_update."JT: $employees{$eid}{'Job title'},";
		my $result=$ldap->modify($dn, replace => { title => $employees{$eid}{'Job title'}});
		print $result->error,"\n";
		$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
	}
	#-----------------------------------------
	if($employees{$eid}{'Business Unit'} ne $company){
		$needs_update=$needs_update."BU: $employees{$eid}{'Business Unit'},";
		my $result=$ldap->modify($dn, replace => { company => $employees{$eid}{'Business Unit'}});
		print $result->error,"\n";
		$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
	}
	#-----------------------------------------
	my @count_items = split(/\./,$employees{$eid}{'Home Department'});
	my $count_items=@count_items;

	if($count_items == 3){
		$employees{$eid}{'Home Department'} =~ /(.*)\.(.*)/;
		if(($1 ne $department)||($2 ne $description)){
			$needs_update=$needs_update."HD: $employees{$eid}{'Home Department'},";
			my $result=$ldap->modify($dn, replace => { department => $1, description => $2});
			print $result->error,"\n";
			$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
		}
	}elsif($count_items == 2){
		if(($employees{$eid}{'Home Department'} ne $department)||($description ne 'none')){
			$needs_update=$needs_update."HD: $employees{$eid}{'Home Department'},";
			my $result=$ldap->modify($dn, replace => { department => $employees{$eid}{'Home Department'}});
			print $result->error,"\n";
			$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
			$result=$ldap->modify($dn, delete => [ qw(description) ]);
			print $result->error,"\n";
			$result->code && warn "failed to delete entry\n" && $input=<STDIN>;
		}
	}else{
		print "$eid Home Department field in ITRPT is in unknown format (it must have 2 or 3 items): $employees{$eid}{'Home Department'}";
		exit;
	}
	#-----------------------------------------
	my @count_dashes = split(//,$employees{$eid}{'Location'});
	my $count=0;
	foreach my $char (@count_dashes){
		if($char eq '-'){
			$count++;
		}
	}

	if($count == 1){
		$employees{$eid}{'Location'} =~ /(.*)-(.*)/;

		my $country = $1;
		my $city = $2;
		#if countrys are not in their 2 letter country code, convert it into one
		if($country !~ /\b\w\w\b/){
			$country=uc(country2code($country));
		}

		if(($country ne $c)||($city ne $physicalDeliveryOfficeName)){
			$needs_update=$needs_update."L: $employees{$eid}{'Location'},";
			my $result=$ldap->modify($dn, replace => { c => $country, physicalDeliveryOfficeName => $city});
			print $result->error,"\n";
			$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
		}

	}elsif($count == 2){
		$employees{$eid}{'Location'} =~ /(.*)-(.*)-(.*)/;

		my $country = $1;
		my $state = $2;
		my $city = $3;
		#if countrys are not in their 2 letter country code, convert it into one
		if($country !~ /\b\w\w\b/){
			$country=uc(country2code($country));
		}

		if(($country ne $c)||($state ne $st)||($city ne $physicalDeliveryOfficeName)){
			$needs_update=$needs_update."L: $employees{$eid}{'Location'},";
			my $result=$ldap->modify($dn, replace => { c => $country, st => $state, physicalDeliveryOfficeName => $city});
			print $result->error,"\n";
			$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
		}
	}else{
		print "Location field in ITRPT does not conform to known standard. Investigate IRPT before continuing. $eid $employees{$eid}{'Location'}\n";
		exit;
	}

# lisa says she hasnt received phone number updates from IT in years so the data in AD is likely
# to be more up to date than ITRPT
#	#-----------------------------------------
#	if(($employees{$eid}{'Work Phone'} ne '') && ($employees{$eid}{'Work Phone'} ne $telephoneNumber)){
#		$needs_update=$needs_update."WP: $employees{$eid}{'Work Phone'},";
#	}
#	#-----------------------------------------
#	if(($employees{$eid}{'Work Fax'} ne '') && ($employees{$eid}{'Work Fax'} ne $facsimileTelephoneNumber)){
#		$needs_update=$needs_update."WF: $employees{$eid}{'Work Fax'},";
#	}

	#-----------------------------------------
	my $mid = $employees{$eid}{'Manager ID'};
	if(($employees{$eid}{'Manager ID'} eq '') && ($employees{$eid}{'First Name'} eq 'Steve') && ($employees{$eid}{'Last Name'} eq 'Shine')){
		#steve shine doesnt have a manager, this is ok
	}elsif($db{$mid} ne $manager){
		$needs_update=$needs_update."M: $employees{$eid}{'Manager ID'},";
		my $result=$ldap->modify($dn, replace => { manager => $db{$mid}});
		print $result->error,"\n";
		$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
	}
	#-----------------------------------------


	if($needs_update ne ''){
		print "$eid $needs_update\n";
	}else{
		print "$eid\n";
	}



}

$ldap->unbind;

print "you should now re-run dumpad.pl to pick up all the latest changes to AD before rerunning sync.pl again.\n";
