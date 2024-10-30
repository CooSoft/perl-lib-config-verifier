#!/usr/bin/perl

use 5.036;
use strict;
use warnings;

use Test::More;

use Config::Verifier qw(:common_routines);

sub test_values($good, $type, $syntax, @values)
{

    my %syntax_tree = ('m:value' => $syntax);
    for my $value (@values)
    {
        my $data = {value => $value};
        my $path = 'Top';
        my $status = '';
        verify($data, \%syntax_tree, $path, \$status);
        if ($good)
        {
            is($status, '', "Good $type check [$value]");
        }
        else
        {
            isnt($status, '', "Bad $type check [$value]");
        }
    }

}

my $exception = '';
sub exception_protect($fn)
{

    $exception = '';

    local $@;
    my $ret_val;
    eval
    {
        $ret_val = &$fn();
    };
    if ($@)
    {
        $exception = "$@";
        note("Exception thrown [$exception]");
        return undef;
    }

    return $ret_val;

}

my (@bad,
    @good);

# Check floats.

@good = qw(0 0.1 83478347 384.34878 +293289 +2873.5666 -33 -2385.66 0.1e10 +12e2
+1.2e-1 -0.2e-1 -2e+3 -2.057e4);
@bad = (' 0.1', '0.1 ', '0.1.2', '0.1e1.2', '2e 3', '2.3 e3', '++6.6afe10');
test_values(1, 'float format', 'f:', @good);
test_values(0, 'float format', 'f:', @bad);
@good = qw(83478347 384.34878 +293289 +2873.5666 2385.66 0.1e10 +12e2);
@bad = qw(2.2 -1.44 100e-2);
test_values(1, 'float minimum', 'f:10', @good);
test_values(0, 'float minimum', 'f:10', @bad);
test_values(1, 'float maximum', 'f:,10e12', @good);
test_values(0, 'float maximum', 'f:,-10e2', @bad);
test_values(1, 'float range', 'f:10,10e12', @good);
test_values(0, 'float range', 'f:-10e2,-2', @bad);
@bad = ('f: 10,20', 'f:10,20 ', ' f:10,20', 'f:10,20 ', 'f:10, 20', 'f:++10,20',
        'f:10.23-e3,123.434', 'f:10.23,--123', 'f:1-.44,10.5+e5', 'f:1,2,3',
        'f:10,5');
foreach my $range (@bad)
{
    exception_protect(sub { return test_values(1,
                                               'float bad range',
                                               $range,
                                               1); });
    like($exception,
         qr/^Illegal syntax element found in syntax tree/,
         "float range [$range]");
}

# Check integers.

@good = qw(0 1 83478347 +293289 -33);
@bad = (' 0', '1 ', '0.1', '1e12', '2 3', '2.3 e3', '+6.6e10');
test_values(1, 'integer format', 'i:', @good);
test_values(0, 'integer format', 'i:', @bad);
@good = qw(83478348 384 +293288 +2874 23886 10000);
@bad = qw(2 -1 8 4 -33);
test_values(1, 'integer minimum', 'i:10', @good);
test_values(0, 'integer minimum', 'i:10', @bad);
test_values(1, 'integer maximum', 'i:,100000000', @good);
test_values(0, 'integer maximum', 'i:,-100', @bad);
test_values(1, 'integer range', 'i:10,100000000', @good);
test_values(0, 'integer range', 'i:-1000,-40', @bad);
test_values(1, 'integer step', 'i:10,100000000,2', @good);
test_values(0, 'integer step', 'i:-1000,-2,2', @bad);
@bad = ('i: 10,20', 'i:10,20 ', ' i:10,20', 'i:10,20 ', 'i:10, 20', 'i:++10,20',
        'i:23,--123', 'i:1-4,10.5e5', 'i:14,10.5e5', 'i:1,2,3,4', 'i:10,5',
        'i:10,20,3');
foreach my $range (@bad)
{
    exception_protect(sub { return test_values(1,
                                               'integer bad range',
                                               $range,
                                               1); });
    like($exception,
         qr/^Illegal syntax element found in syntax tree/,
         "integer range [$range]");
}

# Check amounts.

@good = qw(0K 37467M 029838G 3784T 7.3 -3 4 -9K 9.8K -24.7G);
@bad = (' 0K', '^1K', ' M', '20k', '.99G', '^', '$', '--6G', 'M', '4KK', '-',
        ' ', '.');
test_values(1, 'amount', 'R:amount', @good);
test_values(0, 'amount', 'R:amount', @bad);

# Check data amounts.

@good = qw(0B 3KB 37467MB 029838GB 3784TB 99b 1Kb 8Mb 4Gb 1Tb 5KiB 4MiB 7GiB
           8TiB 1Kib 4Mib 77Gib 1Tib);
@bad = (' 0KB', '^1K', '7MB$', '20Ki', '.99GB', '^', '$', '--6GB', 'Mb', '4Kiz',
        '-', ' ', '.');
test_values(1, 'amount_data', 'R:amount_data', @good);
test_values(0, 'amount_data', 'R:amount_data', @bad);

# Check booleans.

@good = ('true', 'yes', 'Y', 'y', 'on', '1', 'false', 'no', 'N', 'n', 'off',
         '0', '');
@bad = ('freddy', '2', 'x', ' true', 'TRUE', 'false ', '^', '$', '_', '-', ' ',
        '.');
test_values(1, 'booleans', 'R:boolean', @good);
test_values(0, 'booleans', 'R:boolean', @bad);

# Check duration.

@good = qw(66ms 5s 2m 3h 4d 1w 0w);
@bad = (' 0s', '^1s', ' w', '20D', '2', '^', '$', '-6s', '5ss', '4.5m', '-',
        ' ', '.');
test_values(1, 'duration', 'R:duration', @good);
test_values(0, 'duration', 'R:duration', @bad);

my (@bad_machine,
    @good_machine);

# Check hostname.

@good = qw(www.google.com www.bbc.co.uk flower 01testbed-vm.lab.uk);
@bad = ('-01test.bed', ' hello.com', 'goodbye.org ',
        'still.not-valid_quite.com', 'nor-this.one.com.');
test_values(1, 'hostname', 'R:hostname', @good);
test_values(0, 'hostname', 'R:hostname', @bad);
push(@good_machine, @good);
push(@bad_machine, @bad);

# Check IPv4.

@good = ('192.168.1.0', '192.168.1.24', '10.0.0.1');
@bad = ('192.168.1.1/24', ' 192.168.1.2', '192.168.1.2 ', 'AF.24.5.1',
        '1.1.1.256', '1.1.399.1', '1.1.1.-1');
test_values(1, 'IPv4 addresses', 'R:ipv4_addr', @good);
test_values(0, 'IPv4 addresses', 'R:ipv4_addr', @bad);

# Check IPv4 block (IP address or CIDR).

@good = ('192.168.1.0/24', '192.168.1.24');
@bad = (' 192.168.1.2/24', '192.168.1.2/24 ', 'AF.24.5.1/2', '1.1.1.256',
        '1.1.1.-1');
test_values(1, 'IPv4 block', 'R:ipv4_block', @good);
test_values(0, 'IPv4 block', 'R:ipv4_block', @bad);
push(@good_machine, @good);
push(@bad_machine, @bad);

# Check IPv4 CIDR.

@good = ('192.168.1.0/24', '192.168.1.24/32', '10.0.0.1/0');
@bad = ('192.168.1.1', ' 192.168.1.2/24', '192.168.1.2/24 ', 'AF.24.5.1/2',
        '1.1.1.256/24', '1.1.1.1/33', '1.1.1.1/-1');
test_values(1, 'IPv4 CIDR', 'R:ipv4_cidr', @good);
test_values(0, 'IPv4 CIDR', 'R:ipv4_cidr', @bad);

# Check IPv6.

@good = ('04fa:0938:237::3927', '04fa:0938:237::3927', '::1');
@bad = ('04fa:0938:237::3927/24', ' 04fa:0938:237::3927',
        '04fa:0938:237::3927 ', '04fa:0938:g37::3927',
        '04fa:0938:237::39271', '04fa:0938:237::-3927');
test_values(1, 'IPv6 addresses', 'R:ipv6_addr', @good);
test_values(0, 'IPv6 addresses', 'R:ipv6_addr', @bad);

# Check IPv6 block (IP address or CIDR).

@good = ('04fa:0938:237::3927', '04fa:0938:237::3927/128', '::1');
@bad = (' 04fa:0938:237::3927/64', '04fa:0938:237::3927/28 ',
        '04fa:0938:g37::3927/2', '04fa:0938:g37::39271');
test_values(1, 'IPv6 block', 'R:ipv6_block', @good);
test_values(0, 'IPv6 block', 'R:ipv6_block', @bad);
push(@good_machine, @good);
push(@bad_machine, @bad);

# Check IPv6 CIDR.

@good = ('04fa:0938:237::3927/64', '04fa:0938:237::3927/128', '::1/0');
@bad = ('04fa:0938:237::3927', ' 04fa:0938:237::3927/64',
        '04fa:0938:237::3927/28 ', '04fa:0938:g37::3927/2',
        '04fa:0938:237::3927/129', '04fa:0938:237::3927/-128');
test_values(1, 'IPv6 CIDR', 'R:ipv6_cidr', @good);
test_values(0, 'IPv6 CIDR', 'R:ipv6_cidr', @bad);

# Check machine (can be hostname, IP address or CIDR).

test_values(1, 'machine', 'R:machine', @good_machine);
test_values(0, 'machine', 'R:machine', @bad_machine);

# Check path.

@good = ('/home/fbloggs/.local/bin', '../wall-papers', '~/Test Reports');
@bad = ("/bin\000/null", '/home\/notallowed');
test_values(1, 'Unix path', 'R:unix_path', @good);
test_values(0, 'Unix path', 'R:unix_path', @bad);

# Check user name.

@good = ('fbloggs', 'Fred Bloggs', '_test-user', '-result_user',
         '-_test User-_');
@bad = (' fbloggs', 'fbloggs ', '$ksjdk', '%isjsk', '&dsjh', '^', '$', '-s',
        ' ', '.');
test_values(1, 'user name', 'R:user_name', @good);
test_values(0, 'user name', 'R:user_name', @bad);

# Check variable names.

@good = ('counter', 'BadException', 'c0unter', '__debug__');
@bad = (' counter', 'eggs ', '0d', '^', '$', '-s', ' ', '.');
test_values(1, 'variable', 'R:variable', @good);
test_values(0, 'variable', 'R:variable', @bad);

# Replace variable definition and retest.

register_syntax_regex('variable', '^[-_+0-9]$');
@good = ('counter', 'BadException', 'c0unter', '__debug__');
@bad = (' counter', 'eggs ', '0d', '^', '$', '-s', ' ', '.');
test_values(0, 'variable', 'R:variable', @good);
test_values(0, 'variable', 'R:variable', @bad);

# Bad regexes and regex names.

exception_protect(sub { register_syntax_regex(' |amount', '^shgdhs'); });
like($exception,
     qr/is not a suitable syntax element name\./,
     'Bad built in regex name [ |amount]');
exception_protect(sub { register_syntax_regex('cost', '^shgdhs'); });
like($exception,
     qr/is not anchored to the start and end of the string\./,
     'Bad regex [^shgdhs]');
exception_protect(sub { register_syntax_regex('cost', '^shgd(?:hs$'); });
like($exception, qr/Unmatched /, 'Bad regex [^shgd(?:hs$');

# Bad RE replacements.

exception_protect(sub { register_syntax_regex('amount', '^[0-9]+$'); });
like($exception, qr/is not allowed as this could break related code\./,
     'Reserved built in regex [amount]');

# Check conversion functions.

my $result;
foreach my $i (({in  => '100',
                 out => 100},
                {in  => '100K',
                 out => 100_000},
                {in  => '100M',
                 out => 100_000_000},
                {in  => '100G',
                 out => 100_000_000_000},
                {in  => '100T',
                 out => 100_000_000_000_000},
                {in  => '10.09',
                 out => 10.09},
                {in  => '10.09K',
                 out => 10090},
                {in  => '+10.09K',
                 out => 10090},
                {in  => '-10.09K',
                 out => -10090}))
{
    $result = exception_protect(sub { return amount_to_units($i->{in}); });
    is ($result, $i->{out}, "amount_to_units [$i->{in}]");
}
foreach my $i (' 100', ' 100K', '100K ', '--10'. '++10', '-10-', '+10+', '^',
               '$', '10.0.0')
{
    exception_protect(sub { return amount_to_units($i); });
    like($exception, qr/^Invalid amount .+ detected./, "amount_to_units [$i]");
}
exception_protect(sub { return amount_to_units('100K', 1); });
like($exception,
     qr/^Invalid amount .+ detected./,
     'amount_to_units(as_bits) [100K]');
foreach my $i (({in  => '100b',
                 out => 12.5},
                {in  => '100Kib',
                 out => 12_800},
                {in  => '100Mib',
                 out => 13_107_200},
                {in  => '100Gib',
                 out => 13_421_772_800},
                {in  => '100Tib',
                 out => 13_743_895_347_200},
                {in  => '100KiB',
                 out => 102_400},
                {in  => '100MB',
                 out => 100_000_000},
                {in  => '100GB',
                 out => 100_000_000_000},
                {in  => '100TB',
                 out => 100_000_000_000_000}))
{
    $result = exception_protect(sub { return amount_to_units($i->{in}); });
    is ($result, $i->{out}, "amount_to_units [$i->{in}]");
}
foreach my $i (({in  => '100B',
                 out => 800},
                {in  => '100KiB',
                 out => 819_200}))
{
    $result = exception_protect(sub { return amount_to_units($i->{in}, 1); });
    is ($result, $i->{out}, "amount_to_units [$i->{in}]");
}

foreach my $i (({in  => '55ms',
                 out => 0.055},
                {in  => '45s',
                 out => 45},
                {in  => '2m',
                 out => 120},
                {in  => '4h',
                 out => 14_400},
                {in  => '3d',
                 out => 259_200},
                {in  => '9w',
                 out => 5_443_200}))
{
    $result = exception_protect(sub { return duration_to_seconds($i->{in}); });
    is ($result, $i->{out}, "duration_to_seconds [$i->{in}]");
}
foreach my $i (' 100', ' 100K', '100K ', '--10'. '++10', '-10-', '+10+', '^',
               '$', '10.0.0', '', ' ')
{
    exception_protect(sub { return duration_to_seconds($i); });
    like($exception,
         qr/^Invalid duration .+ detected./,
         "duration_to_seconds [$i]");
}

done_testing();

exit(0);
