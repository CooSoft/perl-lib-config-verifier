##############################################################################
#
#   File Name    - Verifier.pm
#
#   Description  - A module for checking the domain specific syntax of data
#                  with regards to the structure of that data and the basic
#                  data types.
#
#                  See the POD section for further details.
#
##############################################################################
#
##############################################################################
#
#   Package      - Config::Verifier
#
#   Description  - See the POD section for further details.
#
##############################################################################



# ***** PACKAGE DECLARATION *****

package Config::Verifier;

# ***** DIRECTIVES *****

use 5.036;
use strict;
use warnings;

# ***** REQUIRED PACKAGES *****

# Standard Perl and CPAN modules.

use Carp;
use IO::Handle;

# ***** GLOBAL DATA DECLARATIONS *****

# Constants for assorted messages.

use constant SCHEMA_ERROR => 'Illegal syntax element found in syntax tree ';

# Whether debug messages should be logged or not.

my $debug = 0;

# Lookup hashes for converting assorted measures.

my %duration_in_seconds = ('s' => 1,
                           'm' => 60,
                           'h' => 3_600,
                           'd' => 86_400,
                           'w' => 604_800);
my %amounts = ('B'   => 1,
               'K'   => 1_000,
               'M'   => 1_000_000,
               'G'   => 1_000_000_000,
               'T'   => 1_000_000_000_000,
               'KB'  => 1_000,
               'MB'  => 1_000_000,
               'GB'  => 1_000_000_000,
               'TB'  => 1_000_000_000_000,
               'KiB' => 1_024,
               'MiB' => 1_048_576,
               'GiB' => 1_073_741_824,
               'TiB' => 1_099_511_627_776);

# A lookup hash containing regexes in the form or plain strings that will get
# replaced by their compiled counterparts, whilst having their non-capturing
# counterparts added to the %syntac_regexes hash below. This reduces maintenance
# and mistakes.

my %capturing_regexes = (amount      => '^([-+]?\d+(?:\.\d+)?)([KMGT])?$',
                         amount_data => '^(\d+)((?:[KMGT]i?)?[Bb])$',
                         duration    => '^(\d+)(ms|[smhdw])$');

# A lookup hash for common syntactic elements. Please note the (?!.) sequence at
# the end matches nothing, i.e. '' and undef should go to false. The more
# complex regexes are generated at load time.

my %syntax_regexes =
    (anything              => qr/^.+$/,
     boolean               => qr/^(?:true|yes|[Yy]|on|1|
                                     false|no|[Nn]|off|0|(?!.))$/x,
     name                  => qr/^[-_.\'"()\[\] [:alnum:]]+$/,
     plugin                => qr/^[-_.[:alnum:]]+$/,
     printable             => qr/^[[:print:]]+$/,
     string                => qr/^[-_. [:alnum:]]+$/,
     unix_path             => qr/^(?:(?!\\\/|\000).)+$/,
     user_name             => qr/^[-_[:alnum:]]+[-_ [:alnum:]]+[-_[:alnum:]]+$/,
     variable              => qr/^[[:alpha:]_][[:alnum:]_]+$/);

# ***** FUNCTIONAL PROTOTYPES *****

# Private routines.

state sub generate_regexes;
state sub logger($format, @args)
{
    STDERR->printf($format . "\n", @args);
    return;
}
state sub throw($format, @args)
{
    croak(sprintf($format, @args));
}
state sub verify_arrays;
state sub verify_hashes;
state sub verify_node;

# Public routines.

sub amount_to_units;
sub debug($value = undef)
{
    $debug = $value if (defined($value));
    return $debug;
}
sub duration_to_seconds;
sub match_syntax_value;
sub register_syntax_regex;
sub string_to_boolean($value)
{
    return ($value =~ m/^(?:true|yes|[Yy]|on|1)$/) ? 1 : 0;
}
sub verify($data, $syntax, $name)
{
    my $status = '';
    verify_node($data, $syntax, $name, \$status);
    return $status;
}

# ***** PACKAGE INFORMATION *****

# We are just a procedural module that exports stuff.

use base qw(Exporter);

our %EXPORT_TAGS = (common_routines => [qw(amount_to_units
                                           duration_to_seconds
                                           match_syntax_value
                                           register_syntax_regex
                                           string_to_boolean
                                           verify)]);
our @EXPORT_OK = qw(debug);
Exporter::export_ok_tags(qw(common_routines));
our $VERSION = '1.0';
#
##############################################################################
#
#   Routine      - match_syntax_value
#
#   Description  - Public routine. See the POD section for further details.
#
##############################################################################



sub match_syntax_value($syntax, $value, $error_text = undef)
{

    # We don't allow undefined values.

    return unless(defined($value));

    my ($arg,
        $result,
        $type);

    # Decide what to do based upon the header.

    if ($syntax =~ m/^([cfimRrst]):(.*)/)
    {
        $type = $1;
        $arg = $2;
    }
    else
    {
        throw("%s(syntax = `%s').", SCHEMA_ERROR, $syntax);
    }
    if ($type eq 'c')
    {
        $result = 1;
    }
    elsif ($type eq 'f')
    {
        my $float_re = '[-+]?(?=\d|\.\d)\d*(?:\.\d*)?(?:[Ee][-+]?\d+)?';
        if ($arg =~ m/^(?:($float_re))?(?:,($float_re))?$/)
        {
            my ($min, $max) = ($1, $2);
            throw("%s(syntax = `%s', minimum is greater than maximum).",
                  SCHEMA_ERROR,
                  $syntax)
                if (defined($min) and defined($max) and $min  > $max);
            if ($value =~ m/^$float_re$/
                and (not defined($min) or $value >= $min)
                and (not defined($max) or $value <= $max))
            {
                $result = 1;
            }
            elsif (defined($error_text))
            {
                $$error_text =
                    sprintf('float between %s and %s',
                            defined($min) ? $min : '<No Lower Limit>',
                            defined($max) ? $max : '<No Upper Limit>');
            }
        }
        else
        {
            throw("%s(syntax = `%s').", SCHEMA_ERROR, $syntax);
        }
    }
    elsif ($type eq 'i')
    {
        my $int_re = '[-+]?\d+';
        if ($arg =~ m/^(?:($int_re))?(?:,($int_re)?)?(?:,($int_re)?)?$/)
        {
            my ($min, $max, $step) = ($1, $2, $3);
            throw("%s(syntax = `%s', minimum is greater than maximum).",
                  SCHEMA_ERROR,
                  $syntax)
                if (defined($min) and defined($max) and $min  > $max);
            throw("%s(syntax = `%s', minimum/maximum values are not "
                      . 'compatible with step value).',
                  SCHEMA_ERROR,
                  $syntax)
                if (defined($step)
                    and ((defined($min) and ($min % $step) != 0)
                         or (defined($max) and ($max % $step) != 0)));
            if ($value =~ m/^$int_re$/
                and (not defined($min) or $value >= $min)
                and (not defined($max) or $value <= $max)
                and (not defined($step) or ($value % $step) == 0))
            {
                $result = 1;
            }
            elsif (defined($error_text))
            {
                $$error_text =
                    sprintf('integer between %s and %s%s',
                            defined($min) ? $min : '<No Lower Limit>',
                            defined($max) ? $max : '<No Upper Limit>',
                            defined($step) ? " with a step size of $step" : '');
            }
        }
        else
        {
            throw("%s(syntax = `%s').", SCHEMA_ERROR, $syntax);
        }
    }
    elsif ($type eq 'R')
    {
        if (exists($syntax_regexes{$arg}))
        {
            $result = 1 if ($value =~ m/$syntax_regexes{$arg}/);
        }
        else
        {
            throw("%s(syntax = `%s', unknown syntactic regular expression).",
                  SCHEMA_ERROR,
                  $syntax);
        }
    }
    elsif ($type eq 'r')
    {
        local $@;
        eval
        {
            $result = 1 if ($value =~ m/$arg/);
            1;
        }
        or do
        {
            my $err = $@;
            $err =~ s/ at .+ line \d+\..*//gs;
            throw($err);
        };
    }
    else
    {
        $result = 1 if ($arg eq $value);
    }

    logger("Comparing `%s' against `%s'. Match: %s.",
           $syntax,
           $value,
           ($result) ? 'Yes' : 'No')
        if ($debug);

    return $result;

}
#
##############################################################################
#
#   Routine      - amount_to_units
#
#   Description  - Public routine. See the POD section for further details.
#
##############################################################################



sub amount_to_units($value, $want_bits = 0)
{

    my $units = 0;

    if ((not $want_bits and $value =~ m/$capturing_regexes{amount}/)
        or $value =~ m/$capturing_regexes{amount_data}/)
    {
        my ($amount, $unit) = ($1, $2);
        if (defined($unit))
        {
            $units = $amount * $amounts{($unit =~ s/b/B/gr)};
            my $given_as_bits = ($unit =~ m/.*b$/) ? 1 : 0;
            if (not $given_as_bits and $want_bits)
            {
                $units *= 8;
            }
            elsif ($given_as_bits and not $want_bits)
            {
                $units /= 8;
            }
        }
        else
        {
            $units = $amount;
        }
    }
    else
    {
        throw("Invalid amount `%s' detected.", $value);
    }

    return $units;

}
#
##############################################################################
#
#   Routine      - duration_to_seconds
#
#   Description  - Public routine. See the POD section for further details.
#
##############################################################################



sub duration_to_seconds($duration)
{

    my $seconds = 0;

    if ($duration =~ m/$capturing_regexes{duration}/)
    {
        my ($amount, $unit) = ($1, $2);
        if ($unit eq 'ms')
        {
            $seconds = $amount / 1000;
        }
        else
        {
            $seconds = $amount * $duration_in_seconds{$unit};
        }
    }
    else
    {
        throw("Invalid duration `%s' detected.", $duration);
    }

    return $seconds;

}
#
##############################################################################
#
#   Routine      - register_syntax_regex
#
#   Description  - Public routine. See the POD section for further details.
#
##############################################################################



sub register_syntax_regex($name, $regex)
{

    # The name must be a simple variable like name and the regex pattern must be
    # properly anchored.

    throw("`%s' is not a suitable syntax element name.", $name)
        if ($name !~ m/^[-[:alnum:]_.]+$/);
    throw("`%s' is not anchored to the start and end of the string.", $regex)
        if ($regex !~ m/^\^.*\$$/);
    if (exists($capturing_regexes{$name}))
    {
        throw("Changing `%s' is not allowed as this could break related code.",
              $name);
    }

    # Register it.

    local $@;
    eval
    {
        $syntax_regexes{$name} = qr/$regex/;
        1;
    }
    or do
    {
        my $err = $@;
        $err =~ s/ at .+ line \d+\..*//gs;
        throw($err);
    };

    return;

}
#
##############################################################################
#
#   Routine      - verify_node
#
#   Description  - Checks the specified structure making sure that the domain
#                  specific syntax is ok.
#
#   Data         - $data   : A reference to the data item within the record
#                            that is to be checked. This is either a reference
#                            to an array or a hash as scalars are leaf nodes
#                            and processed inline.
#                  $syntax : A reference to that part of the syntax tree that
#                            is going to be used to check the data referenced
#                            by $data.
#                  $path   : A string containing the current path through the
#                            record for the current item in $data.
#                  $status : A reference to a string that is to contain a
#                            description of what is wrong. If everything is ok
#                            then this string will be empty.
#
##############################################################################



sub verify_node($data, $syntax, $path, $status)
{

    # Check arrays, these are not only lists but also branch points.

    if (ref($data) eq 'ARRAY' and ref($syntax) eq 'ARRAY')
    {
        verify_arrays($data, $syntax, $path, $status);
    }

    # Check records.

    elsif (ref($data) eq 'HASH' and ref($syntax) eq 'HASH')
    {
        verify_hashes($data, $syntax, $path, $status);
    }

    # We should never see any other types as scalars are dealt with on the spot.

    else
    {
        throw('Settings syntax parser, internal state error detected.');
    }

    return;

}
#
##############################################################################
#
#   Routine      - verify_arrays
#
#   Description  - Checks the specified structure making sure that the domain
#                  specific syntax is ok.
#
#   Data         - $data   : A reference to the array data item within the
#                            record that is to be checked.
#                  $syntax : A reference to that part of the syntax tree that
#                            is going to be used to check the data referenced
#                            by $data.
#                  $path   : A string containing the current path through the
#                            record for the current item in $data.
#                  $status : A reference to a string that is to contain a
#                            description of what is wrong. If everything is ok
#                            then this string will be empty.
#
##############################################################################



sub verify_arrays($data, $syntax, $path, $status)
{

    # Scan through the array looking for a match based upon scalar values and
    # container types.

    array_element: foreach my $i (0 .. $#$data)
    {

        # We are comparing scalar values.

        if (ref($data->[$i]) eq '')
        {
            my $err = '';
            foreach my $syn_el (@$syntax)
            {
                if (ref($syn_el) eq '')
                {
                    logger("Comparing `%s->[%u]:%s' against `%s'.",
                           $path,
                           $i,
                           $data->[$i],
                           $syn_el)
                        if ($debug);
                    next array_element
                        if (match_syntax_value($syn_el, $data->[$i], \$err));
                }
            }
            $$status .= sprintf('Unexpected %s found at %s->[%u]. It either '
                                    . "doesn't match the expected value "
                                    . 'format%s, or a list or record was '
                                    . "expected instead.\n",
                                defined($data->[$i])
                                    ? 'value `' . $data->[$i] . "'"
                                    : 'undefined value',
                                $path,
                                $i,
                                ($err ne '') ? " ($err)" : '');
        }

        # We are comparing arrays.

        elsif (ref($data->[$i]) eq 'ARRAY')
        {

            my $local_status = '';

            # As we are going off piste into the unknown (arrays don't really
            # give us much clue as to what we are looking at nor where
            # decisively to go), we may need to backtrack, so use a local status
            # string and then only report anything wrong if we don't find a
            # match at all.

            foreach my $j (0 .. $#$syntax)
            {
                if (ref($syntax->[$j]) eq 'ARRAY')
                {
                    logger("Comparing `%s->[%u]:(ARRAY)' against `(ARRAY)'.",
                           $path,
                           $i)
                        if ($debug);
                    $local_status = '';
                    verify_node($data->[$i],
                                $syntax->[$j],
                                $path . '->[' . $i . ']',
                                \$local_status);
                    next array_element if ($local_status eq '');
                }
            }

            # Only report an error once for each route taken through the syntax
            # tree.

            if ($local_status eq '')
            {
                $$status .= sprintf("Unexpected list found at %s->[%u].\n",
                                    $path,
                                    $i);
            }
            else
            {
                $$status .= $local_status;
            }

        }

        # We are comparing hashes, records, so look to see if there is a common
        # field in one of the hashes. If so then take that branch.

        elsif (ref($data->[$i]) eq 'HASH')
        {

            # We may need to backtrack, so use a local status string and then
            # only report anything wrong if we don't find a match at all.

            # First look for a special matching type field and value. This will
            # give an exact match if set up correctly.

            foreach my $type_key (keys(%{$data->[$i]}))
            {
                my $syn_key = 't:' . $type_key;
                my $type_value = $data->[$i]->{$type_key};
                foreach my $syn_el (@$syntax)
                {
                    if (ref($syn_el) eq 'HASH'
                        and exists($syn_el->{'t:' . $type_key})
                        and match_syntax_value($syn_el->{'t:' . $type_key},
                                               $type_value))
                    {
                        logger("Comparing `%s->[%u]:%s' against `%s' based on "
                                   . "type field `%s'.",
                               $path,
                               $i,
                               join('|', keys(%{$data->[$i]})),
                               join('|', keys(%$syn_el)),
                               $type_key)
                            if ($debug);
                        verify_node($data->[$i],
                                    $syn_el,
                                    $path . '->[' . $i . ']',
                                    $status);
                        next array_element;
                    }
                }
            }

            # Ok that didn't work so check to see if there is only one field in
            # the hash (typically a record type field). If no single key hashes
            # exist then abort, the schema has to change.

            if (keys(%{$data->[$i]}) != 1)
            {
                $$status .= sprintf('Untyped multifield records are not '
                                        . "allowed at %s->[%u].\n",
                                    $path,
                                    $i);
            }
            else
            {

                my $data_field = (keys(%{$data->[$i]}))[0];
                my $local_status = '';
                foreach my $syn_el (@$syntax)
                {
                    if (ref($syn_el) eq 'HASH')
                    {

                        # Don't allow non-typed records.

                        throw('%s(untyped records are not allowed).',
                              SCHEMA_ERROR)
                            unless (keys(%$syn_el) == 1);

                        # Only allow field names that are either constant or
                        # some sort of value. If there are duplicate values then
                        # too bad as the first match will be taken.

                        my $syn_field = (keys(%$syn_el))[0];
                        throw("%s(record type fields cannot be of type `c:').",
                              SCHEMA_ERROR)
                            if ($syn_field eq 'c:');

                        if (match_syntax_value($syn_field, $data_field))
                        {
                            logger("Comparing `%s->[%u]:%s' against `%s'.",
                                   $path,
                                   $i,
                                   join('|', keys(%{$data->[$i]})),
                                   join('|', keys(%$syn_el)))
                                if ($debug);
                            $local_status = '';
                            verify_node($data->[$i],
                                        $syn_el,
                                        $path . '->[' . $i . ']',
                                        \$local_status);
                            if ($local_status eq '')
                            {
                                next array_element;
                            }
                            else
                            {
                                last;
                            }
                        }

                    }
                }

                # Only report an error once for each route taken through the
                # syntax tree.

                if ($local_status eq '')
                {
                    $$status .= sprintf('Unexpected typed record with field '
                                            . "`%s' found at %s->[%u].\n",
                                        $data_field,
                                        $path,
                                        $i);
                }
                else
                {
                    $$status .= $local_status;
                }

            }

        }

    }

    # Unlikely but just check for empty arrays.

    if (@$data == 0)
    {
        $$status .= sprintf("Empty array found at %s. These are not allowed.\n",
                            $path);
    }

    return;

}
#
##############################################################################
#
#   Routine      - verify_hashes
#
#   Description  - Checks the specified structure making sure that the domain
#                  specific syntax is ok.
#
#   Data         - $data   : A reference to the hash data item within the
#                            record that is to be checked.
#                  $syntax : A reference to that part of the syntax tree that
#                            is going to be used to check the data referenced
#                            by $data.
#                  $path   : A string containing the current path through the
#                            record for the current item in $data.
#                  $status : A reference to a string that is to contain a
#                            description of what is wrong. If everything is ok
#                            then this string will be empty.
#
##############################################################################



sub verify_hashes($data, $syntax, $path, $status)
{

    my $custom_fields = grep(/^c\:$/, keys(%$syntax));
    my (@mandatory_fields);

    # Check that all mandatory fields are present.

    foreach my $key (keys(%$syntax))
    {
        if ($key =~ m/^m\:(.+)$/)
        {
            push(@mandatory_fields, $1);
        }
    }
    foreach my $mandatory_field (@mandatory_fields)
    {
        if (not exists($data->{$mandatory_field}))
        {
            $$status .= sprintf('The %s record does not contain the mandatory '
                                    . "field `%s'.\n",
                                $path,
                                $mandatory_field);
        }
    }

    # Check each field.

    hash_key: foreach my $field (keys(%$data))
    {

        my $syn_el;

        # Locate the matching field in the syntax tree.

        if (exists($syntax->{'m:' . $field}))
        {
            $syn_el = $syntax->{'m:' . $field};
        }
        elsif (exists($syntax->{'s:' . $field}))
        {
            $syn_el = $syntax->{'s:' . $field};
        }
        else
        {
            foreach my $key (keys(%$syntax))
            {
                if (match_syntax_value($key, $field))
                {
                    $syn_el = $syntax->{$key};
                    last;
                }
            }
        }

        # Deal with unknown fields, which are ok if we have custom fields in the
        # record.

        if (not defined($syn_el))
        {
            $$status .= sprintf('The %s record contains an invalid field '
                                    . "`%s'.\n",
                                $path,
                                $field)
                unless (grep(/^c\:$/, keys(%$syntax)));
            next hash_key;
        }

        logger("Comparing `%s->%s:%s' against `%s'.",
               $path,
               $field,
               (ref($data->{$field}) eq '')
                   ? $data->{$field} : '(' . ref($data->{$field}) . ')',
               (ref($syn_el) eq '') ? $syn_el : '(' . ref($syn_el) . ')')
            if ($debug);

        # Ok now check that the value is correct and process it.

        if (ref($syn_el) eq '' and ref($data->{$field}) eq '')
        {
            my $err = '';
            if (not match_syntax_value($syn_el, $data->{$field}, \$err))
            {
                $$status .= sprintf("Unexpected %s found at %s. It doesn't "
                                        . 'match the expected value '
                                        . "format%s.\n",
                                    defined($data->{$field})
                                        ? 'value `' . $data->{$field} . "'"
                                        : 'undefined value',
                                    $path . '->' . $field,
                                    ($err ne '') ? " ($err)" : '');
            }
        }
        elsif ((ref($syn_el) eq 'ARRAY' and ref($data->{$field}) eq 'ARRAY')
               or (ref($syn_el) eq 'HASH'
                   and ref($data->{$field}) eq 'HASH'))
        {
            verify_node($data->{$field},
                        $syn_el,
                        $path . '->' . $field,
                        $status);
        }
        elsif (ref($syn_el) eq '')
        {
            $$status .= sprintf('The %s field does not contain a simple '
                                    . "value.\n",
                                $path . '->' . $field);
        }
        elsif (ref($syn_el) eq 'ARRAY')
        {
            $$status .= sprintf("The %s field is not an array.\n",
                                $path . '->' . $field);
        }
        elsif (ref($syn_el) eq 'HASH')
        {
            $$status .= sprintf("The %s field is not a record.\n",
                                $path . '->' . $field);
        }

    }

    return;

}
#
##############################################################################
#
#   Routine      - generate_regexes
#
#   Description  - Generate the less simple regular expressions. This code is
#                  very closely based on the _init_regexp() routine from
#                  Lionel Cons's Config::Validator module.
#
#   Data         - None.
#
##############################################################################



sub generate_regexes()
{

    # The parentheses below are meant to be non-capturing however with all the
    # colons scattered around it's less confusing to use `(...)' rather than
    # `(?:...)'. This is then patched up afterwards.

    my $label = '[[:alnum:]]([[:alnum:]-]{0,61}[[:alnum:]])?';
    my $byte = '25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d';
    my $cidr4 = '(3[0-2]|[1-2]?\d)';
    my $cidr6 = '(12[0-8]|1[0-1]\d|[1-9]?\d)';
    my $hex4 = '[0-9a-fA-F]{1,4}';
    my $ipv4 = "(($byte)\\.){3}($byte)";
    my @tail = (':',
                "(:($hex4)?|($ipv4))",
                ":(($ipv4)|$hex4(:$hex4)?|)",
                "(:($ipv4)|:$hex4(:($ipv4)|(:$hex4){0,2})|:)",
                "((:$hex4){0,2}(:($ipv4)|(:$hex4){1,2})|:)",
                "((:$hex4){0,3}(:($ipv4)|(:$hex4){1,2})|:)",
                "((:$hex4){0,4}(:($ipv4)|(:$hex4){1,2})|:)");
    my $ipv6 = $hex4;
    foreach my $tail (@tail)
    {
        $ipv6 = "$hex4:($ipv6|$tail)";
    }
    $ipv6 = "(:(:$hex4){0,5}((:$hex4){1,2}|:$ipv4)|$ipv6)";
    my $hostname = "(?=.*[[:alpha:]])($label\\.)*$label";
    my $ipv4_block = "$ipv4(/$cidr4)?";
    my $ipv6_block = "$ipv6(/$cidr6)?";

    my %regexes = (hostname   => $hostname,
                   ipv4_addr  => $ipv4,
                   ipv4_block => $ipv4_block,
                   ipv4_cidr  => "$ipv4/$cidr4",
                   ipv6_addr  => $ipv6,
                   ipv6_block => $ipv6_block,
                   ipv6_cidr  => "$ipv6/$cidr6",
                   machine    => "($hostname)|($ipv4_block)|($ipv6_block)");

    # Make non-capturing, compile and then store the regexes in the main syntax
    # table.

    foreach my $name (keys(%regexes))
    {
        $regexes{$name} =~ s/\((?!\?)/(?:/g;
        $syntax_regexes{$name} = qr/^(?:$regexes{$name})$/;
    }

    # Now compile up the capturing regex strings into capturing and
    # non-capturing objects.

    for my $name (keys(%capturing_regexes))
    {
        my $non_capturing = ($capturing_regexes{$name} =~ s/\((?!\?)/(?:/gr);
        $syntax_regexes{$name} = qr/$non_capturing/;
        $capturing_regexes{$name} = qr/$capturing_regexes{$name}/;
    }

    return;

}
#
##############################################################################
#
#   On Load Initialisation Code
#
##############################################################################



generate_regexes();
1;
#
##############################################################################
#
#   Documentation
#
##############################################################################



__END__

=pod

=head1 NAME

Config::Verifier - Verify the structure and values inside Perl data structures

=head1 VERSION

1.0

=head1 SYNOPSIS

  use Config::Verifier qw(:syntax_elements :common_routines);
  my %settings_syntax_tree =
      ('m:config_version' => SYNTAX_FLOAT,
       's:service'        =>
           {'s:log_level'               => 'r:^(?i:ERROR'
                                               . '|WARNING'
                                               . '|ADVISORY'
                                               . '|INFORMATION'
                                               . '|AUTHENTICATION'
                                               . '|DEBUG)$',
            's:debug_options'           => ['r:^(?i:DEBUG_EVERYTHING'
                                            . '|DEBUG_AUTHENTICATION'
                                            . '|DEBUG_RAW_SETTINGS_DUMP'
                                            . '|DEBUG_SETTINGS_DUMP'
                                            . '|DEBUG_SYSTEM_USERS_DUMP'
                                            . '|DEBUG_STACK_TRACES)$'],
            's:hostname_cache'          =>
                {'s:ttl'            => 'R:duration',
                 's:purge_interval' => 'R:duration'},
            's:lowercase_usernames'     => 'R:boolean',
            's:plugins_directory'       => 'R:path',
            's:system_users_cache_file' => 'R:path',
            's:use_syslog'              => 'R:boolean'});
  my $data = YAML::XS::LoadFile("my-config.yml");
  my $status = verify($data, \%settings_syntax_tree, "settings");
  die("Syntax error detected. The reason given was:\n" . $status)
      if ($status ne "");

=head1 DESCRIPTION

The Config::Verifier module checks the given Perl data structure against the
specified syntax tree. Whilst it can be used to verify any textual data ingested
into Perl, its main purpose is to check configuration data. It's also designed
to be lightweight, not having any dependencies beyond the core Perl modules.

When reading in configuration data from a file, it's up to the caller to decide
exactly how this data is read in. Typically one would use some sort of parsing
module like L<JSON> or L<YAML::XS> (which I have found to be the more stringent
for YAML files).

Whilst this module could be used to verify data from many sources, like RESTful
API requests, you would invariably be better off with a module that could read
in a proper schema in an officially recognised format. One such module, for
validating both JSON and YAML is L<JSON::Validator>. However due to its very
capable nature, it does pull in a lot of dependencies, which can be undesirable
for smaller projects, hence this module.

If this module is not to your liking then another option, which I believe
supports ini style configuration files, is L<Config::Validator>.

=head1 SUBROUTINES/METHODS

=over 4

=item B<verify($data, $syntax, $name)>

Checks the specified structure making sure that the domain specific syntax is
ok.

C<$data> is a reference to the data structure that is to be checked, typically
a hash, i.e. a record, but it can also be an array. C<$syntax> is a reference
to a syntax tree that describes what data should be present and its basic
format, including numeric ranges for numbers. C<$name> is a string containing a
descriptive name for the data structure being checked. This will be used as the
base name in any error messages returned by this function.

=item B<amount_to_units($amount)[, $want_bits]>

Converts the amount given in C<$amount> into units. An amount takes the form as
described by C<'R:amount'> or C<'R:amount_data'> and is either a number
optionally followed K, M, G, or T, or a number followed by KB, Kb, KiB, Kib up
to up to TB etc respectively. For the data amounts B and b refer to bytes and
bits, whilst KiB and KB refer to 1024 bytes and 1000 bytes and so on. If
C<$want_bits> is set to true then the returned amount is in bits rather than
bytes. The default default is false and it only applies to amounts of data.

=item B<debug([$flag])>

Turns on the output of debug messages to C<STDERR> when C<$flag> is set to true,
otherwise debug messages are turned off. If C<$flag> isn't specified then
nothing changes.

=item B<duration_to_seconds($duration)>

As above but for seconds. A duration takes the form as described by
C<'R:duration_seconds'> and is a number followed by a time unit that can be one
of s, m, h, d, or w for seconds, minutes, hours, days and weeks respectively.

=item B<match_syntax_value($syntax, $value[, $error])>

Tests the data in C<$value> against an item in the syntax tree as given by
C<$syntax>. C<$error> is an optional reference to a string that is to contain
any type/value errors that are detected.

=item B<register_syntax_regex($name, $regex)>

Registers the regular expression string C<$regex>, which is not a compiled RE
object, as a syntax pattern under the name given in C<$name>. This is then
available for use as C<'R:<Name>' just like the built in syntax patterns. This
can be used to replace any built in pattern or extend the list of patterns. The
regular expression must be anchored, i.e. start and end with ^ and $
respectively.

=item B<string_to_boolean($string)>

Converts the amount given in C<$string> into a boolean (1 or 0). A string
representing a boolean takes the form as described by C<'R:boolean'> and can be
one of true, yes, Y, y, or on for true and false, no N, n, off or '' for false.

=back

=head1 RETURN VALUES

C<verify()> returns a string containing the details of the problems encountered
when parsing the data on failure, otherwise an empty string on success.

C<amount_to_units()> returns an integer.

C<debug()> returns the previous debug message setting as a boolean.

C<duration_to_seconds()> returns the number of seconds that the specified
duration represents.

C<match_syntax_value()> returns true for a match, otherwise false for no match.

C<register_syntax_regex()> returns nothing.

C<string_to_boolean()> returns a boolean.

=head1 NOTES

=head2 Import Tags

=over 4

=item B<:common_routines>

When this import tag is used the following routines are imported into the
calling name space:

    amount_to_units
    duration_to_seconds
    match_syntax_value
    register_syntax_regex
    string_to_boolean
    verify

=back

=head2 Syntax Patterns

Syntax patterns are used to match against specific values. These are expressed
as anchored regular expressions and can be registered, either built in or
registered by the caller an runtime (denoted by C<'R:'>), or simply provided
directly in the syntax tree (denoted by C<'r:'>).

The built in registered ones are:

    R:amount
    R:amount_data
    R:anything
    R:boolean
    R:duration
    R:hostname
    R:ipv4_addr
    R:ipv4_block
    R:ipv4_cidr
    R:ipv6_addr
    R:ipv6_block
    R:ipv6_cidr
    R:machine
    R:name
    R:plugin
    R:printable
    R:string
    R:unix_path
    R:user_name
    R:variable

One can add to the built in list or replace existing entries by using
C<register_syntax_regex()>.

=head2 Syntax Trees

These trees, a container of some sort, typically a hash, describe what should
appear in a given data structure. The hash's key names represent fields that can
be present and their values either refer to further containers, for nested
records or lists, or strings that describe the type of value that should be
present for that field. Key names are strings that consist of a type character
followed by a colon and then the field name. Key and value types are as follows:

    c:      - Custom entries follow, i.e. a key lookup failure isn't an
              error. This is used to cater for parts of a syntax tree that
              need to be dynamic and need to be handled separately.
    f:m,M   - A floating point number with optional minimum and Maximum
              qualifiers.
    i:m,M,s - An integer with optional minimum, Maximum and step qualifiers.
    m:s     - A plain string literal s, invariably representing the name of
              a mandatory field, which is case sensitive.
    R:n     - A built in regular expression with the name n, that is used to
              match against acceptable values. This can also be used to
              match against optional fields that fit that pattern.
    r:reg   - Like R:n but the regular expression is supplied by the caller.
    s:s     - A plain string literal s, typically representing the the name
              of an optional field, which is case sensitive.
    t:s     - Like m: but also signifies a typed field, i.e. a field that
              uniquely identifies the type of the record via its value. Its
              corresponding value must uniquely identify the type of record
              within the list of records at that point in the schema.
    Arrays  - These represent not only that a list of items should be
              present but also that there can be a choice in the different
              types of items, e.g scalar, list or hash.
    Hashes  - These represent records with named fields.

Typically keys can be anything other than containers and values are specific
types, regular expressions or containers. The R: style syntax patterns mentioned
above provide regular expressions for the more common syntax elements.

Please see the example under L</SYNOPSIS>.

=head1 DIAGNOSTICS

One can generate loads of tracing messages to C<STDERR> when debug mode is
turned on via the C<debug()> function.

Exceptions are thrown when there is a problem with the supplied syntax tree.

=head1 DEPENDENCIES

None beyond the core Perl modules.

=head1 SEE ALSO

L<Config::Validator>,
L<JSON::Validator>,
L<JSON>,
L<YAML::XS>

=head1 BUGS AND LIMITATIONS

This module is certainly not exhaustive and doesn't contain support for parsing
non-Linux related items, although that would be trivial to add. Also not
everything can be checked. Maybe a future enhancement could be to have a code
reference mechanism whereby code snippets could be included in the syntax tree.

=head1 AUTHOR

Anthony Edward Cooper. Please report all faults and suggestions to
<aecooper@cpan.org>.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2024 by Anthony Cooper <aecooper@cpan.org>.

This library is free software; you can redistribute it and/or modify it under
the terms of the GNU Lesser General Public License as published by the Free
Software Foundation; either version 3 of the License, or (at your option) any
later version.

This library is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License along
with this library; if not, write to the Free Software Foundation, Inc., 59
Temple Place - Suite 330, Boston, MA 02111-1307 USA.

=cut
