#!/usr/bin/perl -w
use strict;
use JSON::Tiny qw{encode_json true false};

# variables
my ($final);

# output something to STDOUT
print "this is in STDOUT\n";

# output something to STDERR
print STDERR "this is in STDERR\n";

# final output
$final = {
	'testmin-success' => true,
	'my-hash' => {
		'a' => 1,
		'b' => 'bee',
	},
	'my-null' => undef,
	'my-arr' => ['one', true, false, -2],
};

# output success
print encode_json($final), "\n";
