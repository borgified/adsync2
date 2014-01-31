#!/usr/bin/env perl

use strict;
use warnings;
use Text::CSV;
use Data::Dumper;
use DBI;
use Net::LDAPS;

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

#Employee Name:name
#Employee Id:none
#Job title:title
#Business Unit:company
#Home Department:department.description
#Location:c-st-physicalDeliveryOfficeName
#Work Phone:telephoneNumber
#Work Fax:facsimileTelephoneNumber
#Work Email:mail
#Manager:manager


while(my $fields = $csv->getline($data)){

	#detect if the first field starts with 'Employee Name' if so, then this is
	#our header we'll use it as the key for our hash.
	my $x=0;

	if(${$fields}[0] eq 'Employee Name'){
		@header=@{$fields};
		next;
	}else{

		foreach my $field (@{$fields}){
			$employees{"${$fields}[-2]"}{"$header[$x]"}="$field";
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

#first find the employee by their email
#we're going to make use of the work we did in another script (dumpad.pl)
#and query the database for info rather than going to AD directly.

my $my_cnf = '/secret/my_cnf.cnf';

my $dbh = DBI->connect("DBI:mysql:"
	. ";mysql_read_default_file=$my_cnf"
	.';mysql_read_default_group=ldap',
	undef,
	undef
) or die "something went wrong ($DBI::errstr)";

#generate hashes to do name lookups by dn and vice versa. used for looking up managers mostly.

my $q2 = $dbh->prepare("select * from ldap");
$q2->execute;

my %d2n;
my %n2d;

while(my @row = $q2->fetchrow_array){
	#print "$row[0] $row[8]\n";
	$d2n{$row[0]}="$row[8]";
	$n2d{$row[8]}=$row[0];
}



my $query = $dbh->prepare("select * from ldap where mail = ?");

foreach my $email (keys(%employees)){
	my $rv=$query->execute($email);
	my($dn,$title,$department,$description,$mail,$sam,$givenName,$sn,$name,$company,$c,$st,$physicalDeliveryOfficeName,$telephoneNumber,$facsimileTelephoneNumber,$manager) = $query->fetchrow_array;
	if($rv != 1){
		print "\ndid not find $mail\n\n";

		#extract givenname and sn from email
		$email=~/(.*)\.(.*)\@/;
		my $givenName=$1;
		my $sn=$2;

		my $search_by_name = $dbh->prepare("select dn,mail from ldap where givenName like \'$givenName\' or sn like \'$sn\'");

		my $rv2=$search_by_name->execute;

		if($rv2 eq '0E0'){
			print "Sorry, I can't even hazard a guess at who this is: $email\n";
			print "You should find out who this is manually.\n";
			print "Just hit <ENTER> to go on to the next employee.\n";
			<STDIN>;
		}else{

			print "$rv2 I'm going to take some wild guesses, YOU choose the right one:\n\n";
			my $x=0;
			my @choices;
			while(my ($dn,$mail) = $search_by_name->fetchrow_array()){
				print $x++." $dn ($mail)\n";
				push(@choices,$dn);
			}	

			print "Your answer: ";	
			my $answer=<STDIN>;
			#check that the answer is in the valid range
			print "You chose: $answer\n";<STDIN>;
		}
	}else{
		#using email, we matched an account! compare remaining fields

		print ">>>>$rv $email\n";

		$employees{$email}{"Home Department"} =~ /(.*)\.(.*)/;
		my $dept = $1;
		my $desc = $2;

		my @count_dashes = split(//,$employees{$email}{"Location"});
		my $count=0;
		foreach my $char (@count_dashes){
			if($char eq '-'){
				$count++;
			}
		}

		my $country;
		my $state_or_foreign_city;
		my $office_name;

		if($count == 1){
			$employees{$email}{"Location"} =~ /(.*)-(.*)/;
			$country = $1;
			$state_or_foreign_city = $2;
			$office_name=$state_or_foreign_city;

		}elsif($count == 2){
			$employees{$email}{"Location"} =~ /(.*)-(.*)-(.*)/;
			$country = $1;
			$state_or_foreign_city = $2;
			$office_name = $3;
		}else{
			print "Location field in CSV does not conform to known standard. Investigate IRPT before continuing.\n";
			exit;
		}

		#translate the manager's field to his name rather than show dn (too long)
		if($manager ne 'none'){
			$manager=$d2n{$manager};
		}

		my $newmanager;
		#make sure that CSV's manager field resolves to a dn
		if($employees{$email}{"Manager"} ne ''){
			$newmanager = $n2d{$employees{$email}{"Manager"}};
		}

		printf " %40s | %40s | %40s \n", "","AD", "CSV";
		print "-"x120,"-------","\n";
		printf " %40s | %40s | %40s \n", "Employee Name", $name, $employees{$email}{"Employee Name"};
		printf " %40s | %40s | %40s \n", "Job title",$title, $employees{$email}{"Job title"};
		printf " %40s | %40s | %40s \n", "Business Unit",$company,$employees{$email}{"Business Unit"};
		print "-"x120,"-------","\n";
		printf " %40s | %40s | %40s \n", "Home Department","",$employees{$email}{"Home Department"};
		printf " %40s | %40s | %40s \n", "department",$department, $dept;
		printf " %40s | %40s | %40s \n", "description",$description, $desc;
		print "-"x120,"-------","\n";
		printf " %40s | %40s | %40s \n", "Location","",$employees{$email}{"Location"};
		printf " %40s | %40s | %40s \n", "c",$c, $country;
		printf " %40s | %40s | %40s \n", "st",$st, $state_or_foreign_city;
		printf " %40s | %40s | %40s \n", "physicalDeliveryOfficeName",$physicalDeliveryOfficeName,$office_name;
		print "-"x120,"-------","\n";
		printf " %40s | %40s | %40s \n", "Work Phone",$telephoneNumber,$employees{$email}{"Work Phone"};
		printf " %40s | %40s | %40s \n", "Work Fax",$facsimileTelephoneNumber,$employees{$email}{"Work Fax"};
		printf " %40s | %40s | %40s \n", "Work Email",$email,$employees{$email}{"Work Email"};
		printf " %40s | %40s | %40s \n", "Manager",$manager,$employees{$email}{"Manager"};

		print "\nupdate? (y/n) ";
		my $input="";
		$input=<STDIN>;
		chomp($input);
		if(lc($input) eq 'y'){


			my $result=$ldap->modify($dn,
				replace => {
					name => $employees{$email}{"Employee Name"},
					title => $employees{$email}{"Job title"},
					company => $employees{$email}{"Business Unit"},
					department => $dept,
					description => $desc,
					c => $country,
					st => $state_or_foreign_city,
					physicalDeliveryOfficeName => $office_name,
					manager => $newmanager,
				}
			);
			print $result->error,"\n";
			$result->code && warn "failed to replace entry\n" && $input=<STDIN>;


			#update phone only if we have that info in CSV and nothing in AD
			if(($telephoneNumber eq 'none') && ($employees{$email}{"Work Phone"} ne '')){
				my $result=$ldap->modify($dn,
					replace => {
						telephoneNumber => $employees{$email}{"Work Phone"},
					}
				);
				print $result->error,"\n";
				$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
			}

			#update fax only if we have that info in CSV and nothing in AD
			if(($facsimileTelephoneNumber eq 'none') && ($employees{$email}{"Work Fax"} ne '')){
				my $result=$ldap->modify($dn,
					replace => {
						facsimileTelephoneNumber => $employees{$email}{"Work Fax"},
					}
				);
				print $result->error,"\n";
				$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
			}

		}else{
			print "Ok, skipping without making changes.\n";
		}



####################################### name
#		if($name ne $employees{$email}{"Employee Name"}){
#			print "replacing (name) AD: ".$name." with ITRPT: ".$employees{$email}{"Employee Name"}."\n";
#			print "proceed? (y/n) ";
#			my $input="";
#			$input=<STDIN>;
#			chomp($input);
		#
#			if(lc($input) eq 'y'){
#				my $result=$ldap->modify($dn,
#					replace => {
#						name => $employees{$email}{"Employee Name"},
#					}
#				);
#				print $result->error,"\n";
#				$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
#			}else{
#				print "Ok, skipping without making changes.\n";
#			}
#		
#		}
####################################### title
#		if($title ne $employees{$email}{"Job title"}){
#			print "replacing (title) AD: ".$title." with ITRPT: ".$employees{$email}{"Job title"}."\n";
#			print "proceed? (y/n) ";
#			my $input="";
#			$input=<STDIN>;
#			chomp($input);
		#
#			if(lc($input) eq 'y'){
#				my $result=$ldap->modify($dn,
#					replace => {
#						title => $employees{$email}{"Job title"},
#					}
#				);
#				print $result->error,"\n";
#				$result->code && warn "failed to replace entry\n" && $input=<STDIN>;
#			}else{
#				print "Ok, skipping without making changes.\n";
#			}
#		
#		}
######################################
	}
}

