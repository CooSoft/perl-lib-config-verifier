##############################################################################
#
#   File Name    - Verifier.pm
#
#   Description  - A module for checking the domain specific syntax of data
#                  with regards to the structure of that data and the basic
#                  data types. This module sort of behaves like a schema
#                  validator. However, the data type and value checking is
#                  limited to what you can express as a simple string or
#                  regular expression. For example, you can check that a value
#                  is a correct enumeration or that a number is an integer or
#                  a float but not the value of that number against a range.
#
#   Authors      - A.E.Cooper.
#
#   Legal Stuff  - Copyright (c) 2024 Anthony Edward Cooper
#                  <aecooper@cpan.org>.
#
#                  This library is free software; you can redistribute it
#                  and/or modify it under the terms of the GNU Lesser General
#                  Public License as published by the Free Software
#                  Foundation; either version 3 of the License, or (at your
#                  option) any later version.
#
#                  This library is distributed in the hope that it will be
#                  useful, but WITHOUT ANY WARRANTY; without even the implied
#                  warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#                  PURPOSE. See the GNU Lesser General Public License for
#                  more details.
#
#                  You should have received a copy of the GNU Lesser General
#                  Public License along with this library; if not, write to
#                  the Free Software Foundation, Inc., 59 Temple Place - Suite
#                  330, Boston, MA 02111-1307 USA.
#
##############################################################################
#
##############################################################################
#
#   Package      - Config::Verifier
#
#   Description  - See above.
#
##############################################################################



# ***** PACKAGE DECLARATION *****

package Config::Verifier;

# ***** DIRECTIVES *****

require 5.012;

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

# A lookup hash for converting assorted durations into seconds.

my %duration_in_seconds = ('s' => 1,
                           'm' => 60,
                           'h' => 3600,
                           'd' => 86400,
                           'w' => 604800);

# A lookup hash for common syntactic elements. Please note the (?!.) sequence at
# the end matches nothing, i.e. '' and undef should go to false. The more
# complex regexes are generated at load time.

my %syntax_regexes =
    (anything  => qr/^.+$/,
     boolean   => qr/^(?i:true|yes|on|1|false|no|off|0|(?!.))$/,
     duration  => qr/^(?i:\d+(?:ms|[smhdw]))$/,
     float     => qr/^\d+(?:\.\d+)?$/,
     name      => qr/^[-_.\'"()\[\] [:alnum:]]+$/,
     path      => qr/^[[:alnum:][:punct:] ]+$/,
     plugin    => qr/^[-_.[:alnum:]]+$/,
     printable => qr/^[[:print:]]+$/,
     string    => qr/^[-_. [:alnum:]]+$/,
     user_name => qr/^[-_ [:alnum:]]+$/,
     variable  => qr/^[[:alnum:]_]+$/);

# ***** FUNCTIONAL PROTOTYPES *****

# Public routines.

sub debug(;$)
{
    $debug = $_[0] if (defined($_[0]));
    return $debug;
}
sub duration_to_milliseconds($);
sub duration_to_seconds($);
sub match_syntax_value($$;$);
sub register_syntax_regex($$);
sub verify($$$$);

# Private routines.

sub generate_regexes();
sub logger(@)
{
    STDERR->printf(@_);
    STDERR->print("\n");
    return;
}
sub throw(@)
{
    croak(sprintf(@_));
}
sub verify_arrays($$$$);
sub verify_hashes($$$$);

# ***** PACKAGE INFORMATION *****

# We are just a procedural module that exports stuff.

use base qw(Exporter);

our %EXPORT_TAGS = (common_routines => [qw(duration_to_milliseconds
                                           duration_to_seconds
                                           match_syntax_value
                                           register_syntax_regex
                                           verify)]);
our @EXPORT_OK = qw(debug);
Exporter::export_ok_tags(qw(common_routines));
our $VERSION = '1.0';
#
##############################################################################
#
#   Routine      - verify
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



sub verify($$$$)
{

    my ($data, $syntax, $path, $status) = @_;

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



sub verify_arrays($$$$)
{

    my ($data, $syntax, $path, $status) = @_;

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
                    verify($data->[$i],
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
                        verify($data->[$i],
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

                        throw('%s(untyped records are not allowed)',
                              SCHEMA_ERROR)
                            unless (keys(%$syn_el) == 1);

                        # Only allow plain strings as field names.

                        my $syn_field = (keys(%$syn_el))[0];
                        throw("%s(record typefields must be of type `m:', `s:' "
                                  . "or `t:')",
                              SCHEMA_ERROR)
                            unless ($syn_field =~ m/^[mst]:/);

                        if (match_syntax_value($syn_field, $data_field))
                        {
                            logger("Comparing `%s->[%u]:%s' against `%s'.",
                                   $path,
                                   $i,
                                   join('|', keys(%{$data->[$i]})),
                                   join('|', keys(%$syn_el)))
                                if ($debug);
                            $local_status = '';
                            verify($data->[$i],
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



sub verify_hashes($$$$)
{

    my ($data, $syntax, $path, $status) = @_;

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
            verify($data->{$field},
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
#   Routine      - match_syntax_value
#
#   Description  - Tests a value against an item in the syntax tree.
#
#   Data         - $syntax      : The element in the syntax tree that the
#                                 value is to be compared against.
#                  $value       : The string that is to be compared against
#                                 the syntax element.
#                  $error_text  : A reference to the string that is to contain
#                                 expected type or range mismatch information.
#                                 This is optional.
#                  Return Value : True for a match, otherwise false.
#
##############################################################################



sub match_syntax_value($$;$)
{

    my ($syntax, $value, $error_text) = @_;

    # We don't allow undefined values.

    return unless(defined($value));

    my ($arg,
        $result,
        $type);

    # Decide what to do based upon the header.

    if ($syntax =~ m/^([cfimRrstw]):(.*)/)
    {
        $type = $1;
        $arg = $2;
    }
    else
    {
        throw("%s(syntax = `%s', value = `%s').",
              SCHEMA_ERROR,
              $syntax,
              $value);
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
            throw("%s(syntax = `%s', value = `%s').",
                  SCHEMA_ERROR,
                  $syntax,
                  $value);
        }
    }
    elsif ($type =~ m/^[iw]$/)
    {
        my $re;
        my $type_str;
        if ($type eq 'i')
        {
            $re = '[-+]?\d+';
            $type_str = 'integer';
        }
        else
        {
            $re = '\d+';
            $type_str = 'whole';
        }
        if ($arg =~ m/^(?:($re))?(?:,($re))?(?:,($re))?$/)
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
            if ($value =~ m/^$re$/
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
            throw("%s(syntax = `%s', value = `%s').",
                  SCHEMA_ERROR,
                  $syntax,
                  $value);
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
        $result = 1 if ($value =~ m/$arg/);
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
#   Routine      - duration_to_milliseconds
#
#   Description  - Converts the given time duration into milliseconds.
#
#   Data         - $duration    : The time duration that is to be converted
#                                 into milliseconds.
#                  Return Value : The duration in milliseconds.
#
##############################################################################



sub duration_to_milliseconds($)
{

    my $duration = $_[0];

    my $milliseconds = 0;

    if (lc($duration) =~ m/^(\d+)(ms|[smhdw])$/)
    {
        my ($amount, $unit) = ($1, $2);
        if ($unit eq 'ms')
        {
            $milliseconds = $amount;
        }
        else
        {
            $milliseconds = duration_to_seconds($duration) * 1000;
        }
    }
    else
    {
        throw("Invalid duration `%s' detected.", $duration);
    }

    return $milliseconds;

}
#
##############################################################################
#
#   Routine      - duration_to_seconds
#
#   Description  - Converts the given time duration into seconds.
#
#   Data         - $duration    : The time duration that is to be converted
#                                 into seconds.
#                  Return Value : The duration in seconds.
#
##############################################################################



sub duration_to_seconds($)
{

    my $duration = $_[0];

    my $seconds = 0;

    if (lc($duration) =~ m/^(\d+)([smhdw])$/)
    {
        my ($amount, $unit) = ($1, $2);
        $seconds = $amount * $duration_in_seconds{$unit};
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
#   Description  - Register the specified syntax element and pattern.
#
#   Data         - $name        : The name that is to be given to the syntax
#                                 element.
#                  $regex       : The regex specified as a regular string.
#
##############################################################################



sub register_syntax_regex($$)
{

    my ($name, $regex) = @_;

    # The name must be a simple variable like name and the regex pattern must be
    # properly anchored.

    throw("`%s' is not a suitable syntax element name.", $name)
        if ($name !~ m/^[-[:alnum:]_.]+$/);
    throw("`%s' is not anchored to the start and end of the string.", $regex)
        if ($regex !~ m/^\^.*\$$/);

    # Register it.

    $syntax_regexes{$name} = qr/$regex/;

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

    my $label = '[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?';
    my $byte = '25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d';
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
    $ipv6 = ":(:$hex4){0,5}((:$hex4){1,2}|:$ipv4)|$ipv6";
    my $hostname = "($label\\.)*$label";

    my %res = (cidrv4    => "$ipv4/\\d+",
               cidrv6    => "$ipv6/\\d+",
               hostname  => "($label\\.)*$label",
               ipv4_addr => $ipv4,
               ipv6_addr => $ipv6,
               machine   => "($hostname)|($ipv4)|($ipv6)");

    # Make non-capturing, compile and then store the regexes in the main syntax
    # table.

    foreach my $name (keys(%res))
    {
        $res{$name} =~ s/\(/(?:/g;
        $syntax_regexes{$name} = qr/^(?:$res{$name})$/;
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

__END__
#
##############################################################################
#
#   Documentation
#
##############################################################################



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
                {'s:ttl'            => SYNTAX_DURATION,
                 's:purge_interval' => SYNTAX_DURATION},
            's:lowercase_usernames'     => SYNTAX_BOOLEAN,
            's:plugins_directory'       => SYNTAX_PATH,
            's:system_users_cache_file' => SYNTAX_PATH,
            's:use_syslog'              => SYNTAX_BOOLEAN});
  my $data = YAML::XS::LoadFile("my-config.yml");
  my $status = "";
  verify($data, \%settings_syntax_tree, "settings", \$status);
  die("Syntax error detected. The reason given was:\n" . $status)
      if ($status ne "");

=head1 DESCRIPTION

The Config::Verifier module checks the given Perl data structure against the
specific syntax tree. This is particularly useful for when you parse and read in
configuration data from say a YAML file where YAML does not provide any
additional domain specific schema style validation of the data.

=head1 ROUTINES

=over 4

=item B<verify(\%data, \%syntax, $path, \$status)>

Checks the specified structure making sure that the domain specific syntax is
ok.

\%data is a reference to the data structure that is to be checked, typically a
hash, i.e. a record, but it can also be an array. \%syntax is a reference to a
syntax tree that describes what data should be present and its basic
format. Semantic checking is not supported, e.g. numeric range checking for
example. $path is a string containing a descriptive name for the data structure
being checked. This will be used as the base name in any error messages returned
by this function. Lastly $status is a reference to a string that is to contain
any error message resulting from parsing the data. $status should always be
initialised to an empty string. Upon return if there's a problem with the data
structure then the details will be contained within $status, otherwise it will
be an empty string if everything is ok.

=item B<debug([$flag])>

Turns on the output of debug messages to STDERR when $flag is set to true,
otherwise debug messages are turned off. If $flag isn't specified then nothing
changes.

=item B<duration_to_seconds($duration)>

Converts the time duration given in $duration into seconds. A duration takes the
form as described by SYNTAX_DURATION and is a number followed by a time unit
that can be one of s, m, h, d, or w for seconds, minutes, hours, days and weeks
respectively.

=item B<match_syntax_value($yntax, $value[, $error])>

Tests the data in $value against an item in the syntax tree as given by
$syntax. $error is a reference to a string that is to contain any type/value
errors that are detected.

=back

=head1 RETURN VALUES

verify() returns nothing. debug() returns the previous debug message setting as
a boolean. duration_to_seconds() returns the number of seconds that the
specified duration represents. Lastly match_syntax_value() returns true for a
match, otherwise false for no match.

=head1 NOTES

=head2 Import Tags

=over 4

=item B<:syntax_elements>

When this import tag is used the following constants representing common syntax
elements are imported into the calling name space:

    SYNTAX_ANY
    SYNTAX_BOOLEAN
    SYNTAX_CIDR4
    SYNTAX_DURATION
    SYNTAX_FLOAT
    SYNTAX_HOSTNAME
    SYNTAX_INTEGER
    SYNTAX_IP4_ADDR
    SYNTAX_MACHINE
    SYNTAX_NAME
    SYNTAX_NATURAL
    SYNTAX_PATH
    SYNTAX_PLUGIN
    SYNTAX_PRINTABLE
    SYNTAX_STRING
    SYNTAX_USER_NAME
    SYNTAX_VARIABLE

=item B<:common_routines>

When this import tag is used the following routines are imported into the
calling name space:

    verify
    duration_to_seconds
    match_syntax_value

=back

=head2 Syntax Trees

These trees, a container of some sort, typically a hash, describe what should
appear in a given data structure. The hash's key names represent fields that can
be present and their values either refer to further containers, for nested
records or lists, or strings that describe the type of value that should be
present for that field. Key names are strings that consist of a type character
followed by a colon and then the field name. Key and value types are as follows:

    c:     - Custom entries follow, i.e. a key lookup failure isn't an
             error. This is used to cater for parts of a syntax tree that
             need to be dynamic and need to be handled separately.
    m:     - A mandatory field, case sensitive.
    r:     - A regular expression.
    s:     - A plain string, typically an optional field, case sensitive.
    Arrays - These represent not only that a list of items should be present
             but also that there can be a choice in the different types of
             items, e.g scalar, list or hash.
    Hashes - These represent records with named fields.

Typically keys can be anything other than containers and values are regular
expressions or containers. The SYNTAX_ style constants mentioned above provide
regular expressions for the more common syntax elements.

Please see the example under SYNOPSIS.

=head1 SEE ALSO

https://metacpan.org/pod/Config::Validator

=head1 BUGS

This module is certainly not exhaustive and doesn't contain support for parsing
MS-DOS style file paths, although that would be trivial to do. Also not
everything can be checked. Maybe a future enhancement could be to have a code
reference mechanism whereby code snippets could be included in the syntax tree.

=head1 AUTHORS

Anthony Cooper. Currently maintained by Anthony Cooper. Please report all faults
and suggestions to <aecooper@cpan.org>.

=head1 COPYRIGHT

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
