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

my $clear_table = $dbh->prepare("truncate table employee_ids");
$clear_table->execute or die "SQL Error: $DBI::errstr\n";


my $query = $dbh->prepare("insert into employee_ids (eeid,email) values (?,?)");

print "updating employee_ids table with values from $file\n";

foreach my $eeid (keys %employees){
	my $email = $employees{$eeid}{'Work Email'};
	#validate employee id and actian email
	if (($eeid =~ /^\d+a?$/) && ($email =~ /[\w\-]+\.[\w\-]+\@actian\.com/)){
		$query->execute($eeid, $employees{$eeid}{'Work Email'}) or die "SQL Error: $DBI::errstr\n";
	}else{
		print "employee id ($eeid) or email ($email) problem\n";
		exit;
	}
}

