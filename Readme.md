=== Thu Apr 23 16:16:42 MDT 2015 ===

Project Notes
-------------
This script is used specifically by AV incomplete to discharge items regardless of the account. This script takes any number of items on STDIN and discharges them, but in the case of AV incomplete, takes them one at a time.
Instructions for Running
------------------------
```
dischargeitem -x
example: /s/sirsi/Unicorn/Bincustom/dischargeitem.pl -x
example: cat item_bar_codes.lst | /s/sirsi/Unicorn/Bincustom/dischargeitem.pl -U
example: echo 31221012345678 | /s/sirsi/Unicorn/Bincustom/dischargeitem.pl
```


Product Description
-------------------
Perl script written by Andrew Nisbet for Edmonton Public Library, distributable by the enclosed license.

Repository Information
----------------------
This product is under version control using Git.

Dependencies
------------
None. Place in /s/sirsi/Unicorn/Bincustom.

Known Issues
------------
None
