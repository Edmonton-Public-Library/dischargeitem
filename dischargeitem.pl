#!/usr/bin/perl -w
#######################################################################################
#
# Discharges an item.
#
#    Copyright (C) 2017  Andrew Nisbet Edmonton Public Library
# The Edmonton Public Library respectfully acknowledges that we sit on
# Treaty 6 territory, traditional lands of First Nations and Metis people.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Author:  Andrew Nisbet, Edmonton Public Library
# Created: Thu Jul 3 11:15:37 MDT 2014
# Rev:  
#          0.6 - Fix with edititem, requires item by item apiserver. 
#          0.4 - Bug shows station library in history but items don't show in 
#                selitem. Fix with edititem. 
#          0.3 - Add -s switch to change station library for default of EPLMNA. 
#          0.2 - Updated documentation (no -t switch). 
#          0.1 - Removing restriction to require item ids in -i file. 
#          0.0 - Dev. 
#Dependencies: pipe.pl  
#
#######################################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
#######################################################################################
# ***                  Edit these to suit your environment                        *** #
$ENV{'PATH'}  = qq{:/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/usr/bin:/usr/sbin};
$ENV{'UPATH'} = qq{/s/sirsi/Unicorn/Config/upath};
#######################################################################################
my $VERSION            = qq{0.6};
chomp( my $TEMP_DIR    = `getpathname tmp` );
# my $HOME_DIR         = qq{$TEMP_DIR};
my $HOME_DIR           = qq{.};
my $REQUEST_FILE       = qq{$HOME_DIR/D_ITEM_TXRQ.cmd};
my $RESPONSE_FILE      = qq{$HOME_DIR/D_ITEM_TXRS.log};
my $TRX_NUM            = 1; # Transaction number ranges from 1-99, then restarts
my $API_LINE_COUNT     = 0; # for reporting
my $STATION            = "EPLMNA"; # station performing the transactions, used in history record.
chomp( my $DATE        = `date +%Y%m%d` );
chomp( my $TIME        = `date +%H%M%S` );
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
chomp( my $BINCUSTOM   = `getpathname bincustom` );
my $PIPE               = "$BINCUSTOM/pipe.pl";

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: echo <itemID> | $0 [-LUx] [-s<STATION>]
Usage notes for $0.pl.
This script discharges items received on standard in as bar codes.

 -L     : Change the item library to the call number after discharge.
 -s[LIB]: Change the station library from the default 'EPLMNA'.
 -U     : Actually do the update, otherwise it will output the files it would
          have run with APIserver.
 -x     : This (help) message.

example: $0 -x
example: cat items.lst | $0 -U
example: echo 31221012345678 | $0
example: echo 31221012345678 | $0 -U
example: echo 31221012345678 | $0 -s"EPLWHP" -U
example: echo 31221012345678 | $0 -LU
Version: $VERSION
EOF
    exit;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'Ls:Ux';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	$STATION = $opt{'s'} if ( $opt{'s'} );
}

# This function checks items off of a card via API server transactions.
# Example: Request Line (discharge) from a Log File:
# E200808010805220634R ^S86EVFFCIRC^FEEPLJPL^FcNONE^FWJPLCIRC^NQ31221082898953^CO08/01/2008^Fv20000000^^O
# Below is same line but using logprint and translate commands:
# 8/1/2008,08:05:22 Station: 0634 Request: Sequence #: 86 Command: Discharge Item station login user access:CIRC
# station library:EPLJPL  station login clearance:NONE  station user's user ID:JPLCIRC  item ID:31221082898953
# date of discharge:08/01/2008  Max length of transaction response:20000000
# param: itemId the id of the item 31221012345678
# param: discharge date.
# return: API server command formatted and ready for printing to file.
sub getDischargeItemAPI( $$ )
{
	# Requests have the following components:
	# Start-of-request (^S)
	# Two-digit sequence number (01 - 99)
	# Two-character command code
	# Zero or more pieces of data
	# End-of-request (^O)
	# Each piece of data consists of the following elements:
	# Two-character data code
	# Zero or more characters of data
	my $itemId        = shift;
	chomp $itemId;
	my $dischargeDate = shift;
	my $transactionRequestLine = "";
	$TRX_NUM++;
	if ( $TRX_NUM > 99 ) 
	{
		$TRX_NUM = 1;
	}
	$transactionRequestLine = 'E';
	$transactionRequestLine .= $DATE;
	$transactionRequestLine .= $TIME;
	$transactionRequestLine .= '0001';
	$transactionRequestLine .= 'R'; #request
	$transactionRequestLine .= ' ';
	$transactionRequestLine .= '^S';
	$transactionRequestLine .= $TRX_NUM = '0' x ( 2 - length( $TRX_NUM ) ) . $TRX_NUM;
	$transactionRequestLine .= 'EV'; #Discharge Item command code
	$transactionRequestLine .= 'FF'; #station login user access
	$transactionRequestLine .= 'ADMIN';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'FE'; #station library
	$transactionRequestLine .= $STATION;
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'FcNONE';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'FW'; #station user's user ID
	$transactionRequestLine .= 'ADMIN';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'NQ'; #Item ID
	$transactionRequestLine .= $itemId;
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'CO'; #Date of Discharge
	$transactionRequestLine .= $dischargeDate; #must be MM/DD/YYYY format
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'Fv'; #Max length of transaction response
	$transactionRequestLine .= '20000000';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'O';
	return "$transactionRequestLine\n";
}

# This function changes item libraries via API server transactions.
# Example: Request Line (discharge) from a Log File:
# E201709151630351719R |S24IgFWSMTCHTLHL1|FEEPLLHL|FFSMTCHT|FcNONE|FDSIPCHK|dC6|NQ31221112795559|nNEPLLHL|Fv600000|Ok||O
# param: itemId the id of the item 31221012345678
# param: item library, in format 'EPLLHL'.
# return: API server command formatted and ready for printing to file.
sub getChangeItemLibraryAPI( $$ )
{
	chomp( my $itemId        = shift );
	my $dischargeLibrary     = shift;
	$TRX_NUM++;
	if ( $TRX_NUM > 99 ) 
	{
		$TRX_NUM = 1;
	}
	my $transactionRequestLine = 'E';
	$transactionRequestLine .= $DATE;
	$transactionRequestLine .= $TIME;
	$transactionRequestLine .= '0001';
	$transactionRequestLine .= 'R'; #request
	$transactionRequestLine .= ' ';
	$transactionRequestLine .= '^S';
	$transactionRequestLine .= $TRX_NUM = '0' x ( 2 - length( $TRX_NUM ) ) . $TRX_NUM;
	$transactionRequestLine .= 'Ig'; # Edit Library
	$transactionRequestLine .= 'FF'; # station login user access
	$transactionRequestLine .= 'ADMIN';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'FE'; #station library
	$transactionRequestLine .= $STATION;
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'FcNONE';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'FW'; #station user's user ID
	$transactionRequestLine .= 'ADMIN';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'NQ'; #Item ID
	$transactionRequestLine .= $itemId;
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'nN'; # Library code
	$transactionRequestLine .= $dischargeLibrary;
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'Fv'; #Max length of transaction response
	$transactionRequestLine .= '600000';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'Ok';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= '^';
	$transactionRequestLine .= 'O';
	return "$transactionRequestLine\n";
}

# Gets the item library of the item.
# param:  Item ID.
# return: the library code that the item is being discharged from, or the values
#         supplied in the '-s' switch if used.
sub getLibraryCode( $ )
{
	chomp( my $itemId = shift );
	my $libraryCode = $STATION;
	if ( $opt{'s'} )
	{
		$libraryCode = $opt{'s'};
	}
	elsif ( $opt{'L'} )
	{
		chomp( $libraryCode = `echo "$itemId" | selitem -iB 2>/dev/null | selcallnum -iK -oy 2>/dev/null | pipe.pl -oc0` );
	}
	return $libraryCode;
}

init();
open LOG, ">$RESPONSE_FILE" or die "Error opening '$RESPONSE_FILE': $!\n";
open API, ">$REQUEST_FILE"  or die "Error opening '$REQUEST_FILE': $!\n";
chomp( my $today = `date +%m/%d/%Y` );
my $item_count = 0;
while (<>)
{
	# Clean the line of additional piped values if any. 
	chomp( my $itemId = `echo "$_" | pipe.pl -oc0 -tc0` );
	printf LOG "discharging: '%s'\n", $itemId;
	# Item id always comes with a lot of white space on the end from the API so trim it off now.
	# The next two commands discharges the item from the account.
	chomp( my $discharge_api = getDischargeItemAPI( $itemId, $today ) );
	printf LOG "'%s'\n", $discharge_api;
	printf API "%s\n",   $discharge_api;
	# For some unexplained reason the station library in Hist shows the specified library but selitem reports no change. 
	# Reset them now edititem -y"EPLWHP"
	# SirsiDynix writes these 2 transactions to Hist (in order).
	# EV - Edit item
	# Ig - Edit item library
	#   E201709151630351719R |S22EVFWSMTCHTLHL1|FEEPLLHL|FFSMTCHT|FcNONE|FDSIPCHK|dC6|NQ31221112795559|CO9/15/2017,16:30||O
	#   E201709151630351719R |S24IgFWSMTCHTLHL1|FEEPLLHL|FFSMTCHT|FcNONE|FDSIPCHK|dC6|NQ31221112795559|nNEPLLHL|Fv600000|Ok||O
	# Old technique, we now use API server which will record these transactions.
	# `echo "$itemId" | selitem -iB | edititem -y"$STATION"`;
	if ( $opt{'L'} )
	{ 
		chomp( my $change_item_lib_api = getChangeItemLibraryAPI( $itemId, getLibraryCode( $itemId ) ) );
		printf LOG "'%s'\n", $change_item_lib_api;
		printf API "%s\n",   $change_item_lib_api;
	}
	$item_count++;
}
close API;
if ( $opt{'U'} )
{
	`cat "$REQUEST_FILE" | apiserver -h >>$RESPONSE_FILE 2>/dev/null`; # -e will output the errors but clobber other transactions from today.
}
printf "Total items: %d\n", $item_count;
printf LOG "Total items: %d\n", $item_count;
close LOG;
# EOF