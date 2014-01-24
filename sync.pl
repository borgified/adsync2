#!/usr/bin/env perl

use strict;
use warnings;
use Text::CSV;
use Data::Dumper;
use DBI;


my $file = $ARGV[0] or die "need csv input file\n";

my $csv = Text::CSV->new ({
		binary		=> 1,
		auto_diag	=> 1,
		sep_char	=> ',',
	});

open(my $data, '<:encoding(utf8)', $file) or die "couldnt open file $!\n";


my %employees;
my @header;

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

#print Dumper(\%employees);

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

my $query = $dbh->prepare("select dn from ldap where mail = ?");

foreach my $mail (keys(%employees)){
	my $rv=$query->execute($mail);
	my @result = $query->fetchrow_array;
	if($rv != 1){
		print "\ndid not find $mail\n\n";

		#extract givenname and sn from email
		$mail=~/(.*)\.(.*)\@/;
		my $givenName=$1;
		my $sn=$2;

		my $search_by_name = $dbh->prepare("select dn,mail from ldap where givenName like \'$givenName\' or sn like \'$sn\'");

		my $rv2=$search_by_name->execute;

		if($rv2 eq '0E0'){
			print "Sorry, I can't even hazard a guess at who this is: $mail\n";
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
		#we found a matching account, go ahead and update
		print "$rv @result $mail\n";
	}

}


