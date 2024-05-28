##############################################################################
#
#   File Name    - SyntaxChecker.pm
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
##############################################################################
#
##############################################################################
#
#   Package      - Data::SyntaxChecker
#
#   Description  - See above.
#
##############################################################################



# ***** PACKAGE DECLARATION *****

package Data::SyntaxChecker;

# ***** DIRECTIVES *****

require 5.0.12000;

use strict;
use warnings;

# ***** REQUIRED PACKAGES *****

# Modules specific to this application.

use Logger qw(:log_levels :common_routines);

# ***** GLOBAL DATA DECLARATIONS *****

# Constants used in settings syntax tree for common elements.

use constant SYNTAX_ANY       => 'r:.+';
use constant SYNTAX_BOOLEAN   => 'r:^(?i:true|yes|on|1|false|no|off|0|(?!.))$';
use constant SYNTAX_CIDR4     => 'r:^\d+(?:\.\d+){3}(?:/\d+)?$';
use constant SYNTAX_DURATION  => 'r:^(?i:\d+[smhdw])$';
use constant SYNTAX_FLOAT     => 'r:^\d+(?:\.\d+)?$';
use constant SYNTAX_HOSTNAME  => 'r:^[-_[:alnum:]]+(?:\.[-_[:alnum:]]+)*$';
use constant SYNTAX_INTEGER   => 'r:^[-+]?\d+$';
use constant SYNTAX_IP4_ADDR  => 'r:^\d+(?:\.\d+){3}$';
use constant SYNTAX_MACHINE   => 'r:^(?:(?:[-_[:alnum:]]+(?:\.[-_[:alnum:]]+)*)'
                                     . '|(?:\d+(?:\.\d+){3}))$';
use constant SYNTAX_NAME      => 'r:^[-_.\'"()\[\] [:alnum:]]+$';
use constant SYNTAX_NATURAL   => 'r:^\d+$';
use constant SYNTAX_PATH      => 'r:^[[:alnum:][:punct:] ]+$';
use constant SYNTAX_PLUGIN    => 'r:^[-_.[:alnum:]]+$';
use constant SYNTAX_PRINTABLE => 'r:^[[:print:]]+$';
use constant SYNTAX_STRING    => 'r:^[-_. [:alnum:]]+$';
use constant SYNTAX_USER_NAME => 'r:^[-_ [:alnum:]]+$';
use constant SYNTAX_VARIABLE  => 'r:^[[:alnum:]_]+$';

# Whether debug messages should be logged or not.

my $debug = 0;

# A lookup hash for converting assorted durations into seconds.

my %duration_in_seconds = ("s" => 1,
                           "m" => 60,
                           "h" => 3600,
                           "d" => 86400,
                           "w" => 604800);

# ***** FUNCTIONAL PROTOTYPES *****

# Public routines.

sub check_syntax($$$$);
sub duration_to_seconds($);
sub match_syntax_value($$);

# Public setters and getters.

sub debug(;$)
{
    $debug = $_[0] if (defined($_[0]));
    return $debug;
}

# ***** PACKAGE INFORMATION *****

# We are just a procedural module that exports stuff.

use base qw(Exporter);

our %EXPORT_TAGS = (syntax_elements => [qw(SYNTAX_ANY
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
                                           SYNTAX_VARIABLE)],
                    common_routines => [qw(check_syntax
                                           duration_to_seconds
                                           match_syntax_value)]);
our @EXPORT = qw();
our @EXPORT_OK = qw(debug);
Exporter::export_ok_tags(qw(syntax_elements common_routines));
our $VERSION = "1.0";
#
##############################################################################
#
#   Routine      - check_syntax
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



sub check_syntax($$$$)
{

    my ($data, $syntax, $path, $status) = @_;

    my $logger_context = Logger::Context->new("Syntax");

    # Check arrays, these are not only lists but also branch points.

    if (ref($data) eq "ARRAY" and ref($syntax) eq "ARRAY")
    {

        # Scan through the array looking for a match based upon scalar values
        # and container types.

        array_element: foreach my $i (0 .. $#$data)
        {

            # We are comparing scalar values.

            if (ref($data->[$i]) eq "")
            {
                foreach my $syn_el (@$syntax)
                {
                    if (ref($syn_el) eq "")
                    {
                        logger(DEBUG, "Comparing `%s->[%u]:%s' against `%s'.",
                               $path,
                               $i,
                               $data->[$i],
                               $syn_el)
                            if ($debug);
                        next array_element
                            if (match_syntax_value($syn_el, $data->[$i]));
                    }
                }
                $$status .= sprintf("Unexpected %s found at %s->[%u]. It "
                                        . "either doesn't match the expected "
                                        . "value format, or a list or record "
                                        . "was expected instead.\n",
                                    defined($data->[$i])
                                        ? "value `" . $data->[$i] . "'"
                                        : "undefined value",
                                    $path,
                                    $i);
            }

            # We are comparing arrays.

            elsif (ref($data->[$i]) eq "ARRAY")
            {

                my $hash_in_syntax_tree;
                my $local_status = "";

                # As we are going off piste into the unknown (arrays don't
                # really give us much clue as to what we are looking at nor
                # where decisively to go), we may need to backtrack, so use a
                # local status string and then only report anything wrong if we
                # don't find a match at all.

                foreach my $j (0 .. $#$syntax)
                {
                    if (ref($syntax->[$j]) eq "ARRAY")
                    {
                        logger(DEBUG,
                               "Comparing `%s->[%u]:(ARRAY)' against "
                                   . "`(ARRAY)'.",
                               $path,
                               $i)
                            if ($debug);
                        $local_status = "";
                        check_syntax($data->[$i],
                                     $syntax->[$j],
                                     $path . "->[" . $i . "]",
                                     \$local_status);
                        next array_element if ($local_status eq "");
                    }
                    elsif (ref($syntax->[$j]) eq "HASH")
                    {
                        $hash_in_syntax_tree = 1;
                    }
                }

                # Only report an error once for each route taken through the
                # syntax tree.

                if ($local_status eq "")
                {
                    $$status .= sprintf("Unexpected list found at %s->[%u]. ",
                                        $path,
                                        $i);
                    if ($hash_in_syntax_tree)
                    {
                        $$status .=
                            "Either a value or record was expected instead.\n";
                    }
                    else
                    {
                        $$status .= "A simple value was expected instead.\n";
                    }
                }

                $$status .= $local_status;

            }

            # We are comparing hashes, records, so look to see if there is a
            # common field in one of the hashes. If so then take that branch.

            elsif (ref($data->[$i]) eq "HASH")
            {

                my $a_field = (keys(%{$data->[$i]}))[0];

                foreach my $syn_el (@$syntax)
                {
                    if (ref($syn_el) eq "HASH")
                    {

                        logger(DEBUG, "Comparing `%s->[%u]:%s' against `%s'.",
                               $path,
                               $i,
                               join("|", keys(%{$data->[$i]})),
                               join("|", keys(%$syn_el)))
                            if ($debug);

                        # First check for records with custom fields in them and
                        # simple direct key name matches.

                        if (grep(/^c\:$/, keys(%$syn_el))
                            or exists($syn_el->{"m:" . $a_field})
                            or exists($syn_el->{"s:" . $a_field}))
                        {
                            check_syntax($data->[$i],
                                         $syn_el,
                                         $path . "->[" . $i . "]",
                                         $status);
                            next array_element;
                        }

                        # No luck so far so now try regex a `lookup'.

                        else
                        {
                            foreach my $key (keys(%$syn_el))
                            {
                                if (match_syntax_value($key, $a_field))
                                {
                                    check_syntax($data->[$i],
                                                 $syn_el,
                                                 $path . "->[" . $i . "]",
                                                 $status);
                                    next array_element;
                                }
                            }
                        }

                    }
                }

                # If we have got here then we can't find a match for the current
                # data item in all the record entries.

                $$status .=
                    sprintf("Unexpected record `%s' found at %s->[%u].\n",
                            $a_field,
                            $path,
                            $i);

            }

        }

        # Unlikely but just check for empty arrays.

        if (@$data == 0)
        {
            $$status .= sprintf("Empty array found at %s. These are not "
                                    . "allowed.\n",
                                $path);
        }

    }

    # Check records.

    elsif (ref($data) eq "HASH" and ref($syntax) eq "HASH")
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
                $$status .= sprintf("The %s record does not contain the "
                                        . "mandatory field `%s'.\n",
                                    $path,
                                    $mandatory_field);
            }
        }

        # Check each field.

        hash_key: foreach my $field (keys(%$data))
        {

            my $syn_el;

            # Locate the matching field in the syntax tree.

            if (exists($syntax->{"m:" . $field}))
            {
                $syn_el = $syntax->{"m:" . $field};
            }
            elsif (exists($syntax->{"s:" . $field}))
            {
                $syn_el = $syntax->{"s:" . $field};
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

            # Deal with unknown fields, which are ok if we have custom fields in
            # the record.

            if (not defined($syn_el))
            {
                $$status .= sprintf("The %s record contains an invalid field "
                                        . "`%s'.\n",
                                    $path,
                                    $field)
                    unless (grep(/^c\:$/, keys(%$syntax)));
                next hash_key;
            }

            logger(DEBUG, "Comparing `%s->%s:%s' against `%s'.",
                   $path,
                   $field,
                   (ref($data->{$field}) eq "")
                       ? $data->{$field} : "(" . ref($data->{$field}) . ")",
                   (ref($syn_el) eq "") ? $syn_el : "(" . ref($syn_el) . ")")
                if ($debug);

            # Ok now check that the value is correct and process it.

            if (ref($syn_el) eq "" and ref($data->{$field}) eq "")
            {
                if (not match_syntax_value($syn_el, $data->{$field}))
                {
                    $$status .= sprintf("Unexpected %s found at %s. It doesn't "
                                            . "match the expected value "
                                            . "format.\n",
                                        defined($data->{$field})
                                            ? "value `" . $data->{$field} . "'"
                                            : "undefined value",
                                        $path . "->" . $field)
                }
            }
            elsif ((ref($syn_el) eq "ARRAY" and ref($data->{$field}) eq "ARRAY")
                   or (ref($syn_el) eq "HASH"
                       and ref($data->{$field}) eq "HASH"))
            {
                check_syntax($data->{$field},
                             $syn_el,
                             $path . "->" . $field,
                             $status);
            }
            elsif (ref($syn_el) eq "")
            {
                $$status .= sprintf("The %s field does not contain a simple "
                                        . "value.\n",
                                    $path . "->" . $field);
            }
            elsif (ref($syn_el) eq "ARRAY")
            {
                $$status .= sprintf("The %s field is not an array.\n",
                                    $path . "->" . $field);
            }
            elsif (ref($syn_el) eq "HASH")
            {
                $$status .= sprintf("The %s field is not a record.\n",
                                    $path . "->" . $field);
            }

        }

    }

    # We whould should never see any other types as scalars are dealt with on
    # the spot.

    else
    {
        throw("Settings syntax parser, internal state error detected.");
    }

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
#                  Return Value : True for a match, otherwise false.
#
##############################################################################



sub match_syntax_value($$)
{

    my ($syntax, $value) = @_;

    # We don't allow undefined values.

    return unless(defined($value));

    my ($pattern,
        $result,
        $type);
    my $logger_context = Logger::Context->new("Syntax");

    # Decide what to do based upon the header.

    if ($syntax =~ m/^([cmrs]):(.*)/)
    {
        $type = $1;
        $pattern = $2;
    }
    else
    {
        throw("Illegal syntax element found in syntax tree (syntax = `%s', "
                  . "value = `%s'.",
              $syntax,
              $value);
    }
    if ($type eq "c")
    {
        $result = 1;
    }
    elsif ($type eq "r")
    {
        $result = 1 if ($value =~ m/$pattern/);
    }
    else
    {
        $result = 1 if ($pattern eq $value);
    }

    logger(DEBUG, "Comparing `%s' against `%s'. Match: %s.",
           $syntax,
           $value,
           ($result) ? "Yes" : "No")
        if ($debug);

    return $result;

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

    my $logger_context = Logger::Context->new("Syntax");
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

Data::SyntaxChecker - Check the syntax of Perl data structures

=head1 VERSION

1.0

=head1 SYNOPSIS

  use Data::SyntaxChecker qw(:syntax_elements :common_routines);
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
  check_syntax($data, \%settings_syntax_tree, "settings", \$status);
  die("Syntax error detected. The reason given was:\n" . $status)
      if ($status ne "");

=head1 DESCRIPTION

The Data::SyntaxChecker module checks the given Perl data structure against the
specific syntax tree. This is particularly useful for when you parse and read in
configuration data from say a YAML file where YAML does not provide any
additional domain specific schema style validation of the data.

=head1 ROUTINES

=over 4

=item B<check_syntax(\%data, \%syntax, $path, \$status)>

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

=item B<match_syntax_value($yntax, $value)>

Tests the data in $value against an item in the syntax tree as given by $syntax.

=back

=head1 RETURN VALUES

check_syntax() returns nothing. debug() returns the previous debug message
setting as a boolean. duration_to_seconds() returns the number of seconds that
the specified duration represents. Lastly match_syntax_value() returns true for
a match, otherwise false for no match.

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

    check_syntax
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

=head1 BUGS

This module is certainly not exhaustive and doesn't contain support for parsing
MS-DOS style file paths, although that would be trivial to do. Also not
everything can be checked. Maybe a future enhancement could be to have a code
reference mechanism whereby code snippets could be included in the syntax tree.

=cut
