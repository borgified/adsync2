v3 of adsync script, completely rewritten from ground up

1. run "./dumpad.pl" to populate ldap.ldap table with at least mail and dn for every active account
2. run "./employeeIds.pl ITRPT*" to create the ldap.employee_ids table based on the mail field of ldap.ldap.
3. run "./eid_sync.pl" to store the employeeID for each employee into AD
4. run "./dumpad.pl" again to repopulate ldap.ldap with all the updated AD values (including the employeeIDs)
5. run "./sync.pl ITRPT*" to perform sync

Optional

6. run "./dumpad.pl" to update ldap.ldap with the new changes from step 5.
7. run "./sync.pl ITRPT*" to see if there are any remaining items to be synched.

repeat 6, 7 as necessary until no more items need to be synched.



Please note:  1. Romy Mager-Omphalius prefers to be known as Romy Mager.  She has never had her full name known to the company and 2.  Cynthia Romero Padilla prefers to be known as Cynthia Padilla.  
