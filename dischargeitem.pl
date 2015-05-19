#!/usr/bin/perl -w
####################################################
#
# Perl source file for project dischargeitem 
# Purpose: Clean up the claims return as per policy July 2, 2014.
# Method:
#
# Discharges an item.
#    Copyright (C) 2015  Andrew Nisbet
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
#          0.2 - Updated documentation (no -t switch). 
#          0.1 - Removing restriction to require item ids in -i file. 
#          0.0 - Dev. 
#
####################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'}  = qq{:/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/usr/bin:/usr/sbin};
$ENV{'UPATH'} = qq{/s/sirsi/Unicorn/Config/upath};
###############################################

# Trim function to remove whitespace from the start and end of the string.
# param:  string to trim.
# return: string without leading or trailing spaces.
sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	$string =~ s/(\s+|\|)//g;
	return $string;
}

my $VERSION        = qq{0.2};
# my $HOME_DIR       = qq{.}; # Test
my $HOME_DIR       = qq{/s/sirsi/Unicorn/EPLwork/Dischargeitem};
my $REQUEST_FILE   = qq{$HOME_DIR/D_ITEM_TXRQ.cmd};
my $RESPONSE_FILE  = qq{$HOME_DIR/D_ITEM_TXRS.log};
my $TRX_NUM        = 1; # Transaction number ranges from 1-99, then restarts
my $API_LINE_COUNT = 0; # for reporting
my $STATION        = "EPLMNA"; # station performing the transactions, used in history record.
my $DATE           = `date +%Y%m%d`;
$DATE              = trim($DATE);
my $TIME           = `date +%H%M%S`;
$TIME              = trim($TIME);

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: echo <itemID> | $0 [-Ux]
Usage notes for $0.pl.
This script discharges items received on standard in.

 -U: Actually do the update, otherwise it will output the files it would have run with APIserver.
 -x: This (help) message.

example: $0 -x
example: cat items.lst | $0 -U
example: echo 31221012345678 | $0
example: echo 31221012345678 | $0 -U
Version: $VERSION
EOF
    exit;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'Ux';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
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
sub dischargeItem( $$ )
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

# Takes today's ANSI date as an arg and converts it to a date suitable for history logs
# and transaction files.
# param: today's date in ANSI format YYYYMMDD 
# return: date in MM/DD/YYYY format
sub getHistoryFormattedDate( $ )
{
	my $dateToday = shift;
	my $NewMonth = substr( $dateToday, 4, 2 );
	my $NewDay = substr( $dateToday, 6, 2 );
	my $NewYear = substr( $dateToday, 0, 4 );
	return $NewMonth . '/' . $NewDay . '/' . $NewYear;
}

init();
open API, ">$REQUEST_FILE" or die "Error opening '$REQUEST_FILE': $!\n";
open LOG, ">$RESPONSE_FILE" or die "Error opening '$RESPONSE_FILE': $!\n";
my $today = getHistoryFormattedDate( $DATE );
while (<>)
{
	print LOG "discharging: $_\n";
	# Item id always comes with a lot of white space on the end from the API so trim it off now.
	my $itemId = trim( $_ );
	# The next two commands discharges the item from the account.
	print API dischargeItem( $itemId, $today );
}
close LOG;
close API;
print "Total items: $API_LINE_COUNT\n";

# Run the API server commands.
if ( $opt{'U'} )
{
	`apiserver -h <$REQUEST_FILE >>$RESPONSE_FILE` if ( -s $REQUEST_FILE );
}
# EOF