#!/usr/bin/env perl

use Text::CSV;
use DBI;
use Data::Dumper;
use strict;
use warnings;


my $file = $ARGV[0] or die "need csv input file\n";
open(my $data, '<:encoding(utf8)', $file) or die "couldnt open file $!\n";

my %employees;
my @header;

my $csv = Text::CSV->new ({
		binary		=> 1,
		auto_diag	=> 1,
		sep_char	=> ',',
	});


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

my $my_cnf = '/secret/my_cnf.cnf';

my $dbh = DBI->connect("DBI:mysql:"
	. ";mysql_read_default_file=$my_cnf"
	.';mysql_read_default_group=ldap',
	undef,
	undef
) or die "something went wrong ($DBI::errstr)";


#get a %hash{email}=dn so we can lookup and store dn info into the employee_ids table

my %e2d;

my $q=$dbh->prepare("select mail,dn from ldap");
$q->execute;

while(my($mail,$dn)=$q->fetchrow_array){
	$e2d{lc($mail)}=$dn;
}


my $clear_table = $dbh->prepare("truncate table employee_ids");
$clear_table->execute or die "SQL Error: $DBI::errstr\n";


my $query = $dbh->prepare("insert into employee_ids (eeid,email,dn) values (?,?,?)");

print "updating employee_ids table with values from $file\n";

foreach my $eeid (keys %employees){
	my $email = lc($employees{$eeid}{'Work Email'});
	#validate employee id and actian email
	if (($eeid =~ /^\d+a?$/) && ($email =~ /[\w\-]+\.[\w\-]+\@actian\.com/) && (exists($e2d{$email}))){
		$query->execute($eeid, $email , $e2d{$email}) or die "SQL Error: $DBI::errstr\n";
	}else{
		print "problem with employee id ($eeid) or email ($email) or e2d hash: $e2d{$email}\n";
		print "this is usually an email problem, enter this person's actual email:\n";
		my $email_answer = <STDIN>;
		chomp($email_answer);
		$query->execute($eeid, $email , $e2d{$email_answer}) or die "SQL Error: $DBI::errstr\nRe-run dumpad.pl and try again.\n";
	}
}

