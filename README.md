# NAME

Config::Verifier - Verify the structure and values inside Perl data structures

# VERSION

1.0

# SYNOPSIS

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
                  {'s:ttl'            => 'R:duration_seconds',
                   's:purge_interval' => 'R:duration_seconds'},
              's:lowercase_usernames'     => 'R:boolean',
              's:plugins_directory'       => 'R:path',
              's:system_users_cache_file' => 'R:path',
              's:use_syslog'              => 'R:boolean'});
    my $data = YAML::XS::LoadFile("my-config.yml");
    my $status = "";
    verify($data, \%settings_syntax_tree, "settings", \$status);
    die("Syntax error detected. The reason given was:\n" . $status)
        if ($status ne "");

# DESCRIPTION

The Config::Verifier module checks the given Perl data structure against the
specified syntax tree. Whilst it can be used to verify any textual data ingested
into Perl, its main purpose is to check configuration data. It's also designed
to be lightweight, not having any dependencies beyond the core Perl modules.

When reading in configuration data from a file, it's up to the caller to decide
exactly how this data is read in. Typically one would use some sort of parsing
module like [JSON](https://metacpan.org/pod/JSON) or [YAML::XS](https://metacpan.org/pod/YAML%3A%3AXS) (which I have found to be the more stringent
for YAML files).

Whilst this module could be used to verify data from many sources, like RESTful
API requests, you would invariably be better off with a module that could read
in a proper schema in an officially recognised format. One such module, for
validating both JSON and YAML is [JSON::Validator](https://metacpan.org/pod/JSON%3A%3AValidator). However due to its very
capable nature, it does pull in a lot of dependencies, which can be undesirable
for smaller projects, hence this module.

If this module is not to your liking then another option, which I believe
supports ini style configuration files, is [Config::Validator](https://metacpan.org/pod/Config%3A%3AValidator).

# SUBROUTINES/METHODS

- **verify(\\%data, \\%syntax, $path, \\$status)**

    Checks the specified structure making sure that the domain specific syntax is
    ok.

    `\%data` is a reference to the data structure that is to be checked, typically
    a hash, i.e. a record, but it can also be an array. `\%syntax` is a reference
    to a syntax tree that describes what data should be present and its basic
    format, including numeric ranges for numbers. `$path` is a string containing a
    descriptive name for the data structure being checked. This will be used as the
    base name in any error messages returned by this function. Lastly `$status` is
    a reference to a string that is to contain any error message resulting from
    parsing the data. `$status` should always be initialised to an empty string.
    Upon return if there's a problem with the data structure then the details will
    be contained within `$status`, otherwise it will be an empty string if
    everything is ok.

- **amount\_to\_units($amount)**

    Converts the amount given in `$amount` into units. An amount takes the form as
    described by `'R:amount'` or `'R:amount_data'` and is either a number
    optionally followed K, M, G, or T, or a number followed by KB, Kb, KiB, Kib up
    to up to TB etc respectively. For the data amounts B and b refer to bytes and
    bits, whilst KiB and KB refer to 1024 bytes and 1000 bytes and so on.

- **debug(\[$flag\])**

    Turns on the output of debug messages to `STDERR` when `$flag` is set to true,
    otherwise debug messages are turned off. If `$flag` isn't specified then
    nothing changes.

- **duration\_to\_milliseconds($duration)**

    Converts the time duration given in `$duration` into milliseconds. A duration
    takes the form as described by `'R:duration_milliseconds'` and is a number
    followed by a time unit that can be one of ms, s, m, h, d, or w for
    milliseconds, seconds, minutes, hours, days and weeks respectively.

- **duration\_to\_seconds($duration)**

    As above but for seconds. A duration takes the form as described by
    `'R:duration_seconds'` and is a number followed by a time unit that can be one
    of s, m, h, d, or w for seconds, minutes, hours, days and weeks respectively.

- **match\_syntax\_value($syntax, $value\[, $error\])**

    Tests the data in `$value` against an item in the syntax tree as given by
    `$syntax`. `$error` is an optional reference to a string that is to contain
    any type/value errors that are detected.

- **register\_syntax\_regex($name, $regex)**

    Registers the regular expression string `$regex`, which is not a compiled RE
    object, as a syntax pattern under the name given in `$name`. This is then
    available for use as `'R:<Name`' just like the built in syntax patterns. This
    can be used to replace any built in pattern or extend the list of patterns. The
    regular expression must be anchored, i.e. start and end with ^ and $
    respectively.

- **string\_to\_boolean($string)**

    Converts the amount given in `$string` into a boolean (1 or 0). A string
    representing a boolean takes the form as described by `'R:boolean'` and can be
    one of true, yes, Y, y, or on for true and false, no N, n, off or '' for false.

# RETURN VALUES

`verify()` returns nothing. `amount_to_units()` returns an integer. `debug()`
returns the previous debug message setting as a boolean.
`duration_to_milliseconds()` and `duration_to_seconds()` returns the number of
milliseconds and seconds that the specified duration represents respectively.
`match_syntax_value()` returns true for a match, otherwise false for no
match. `register_syntax_regex()` returns nothing. Lastly `string_to_boolean()`
returns a boolean.

# NOTES

## Import Tags

- **:common\_routines**

    When this import tag is used the following routines are imported into the
    calling name space:

        amount_to_units
        duration_to_milliseconds
        duration_to_seconds
        match_syntax_value
        register_syntax_regex
        string_to_boolean
        verify

## Syntax Patterns

Syntax patterns are used to match against specific values. These are expressed
as anchored regular expressions and can be registered, either built in or
registered by the caller an runtime (denoted by `'R:'`), or simply provided
directly in the syntax tree (denoted by `'r:'`).

The built in registered ones are:

    R:amount
    R:amount_data
    R:anything
    R:boolean
    R:duration_milliseconds
    R:duration_seconds
    R:float
    R:name
    R:path
    R:plugin
    R:printable
    R:string
    R:user_name
    R:variable

One can add to the built in list or replace existing entries by using
`register_syntax_regex()`.

## Syntax Trees

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

Please see the example under ["SYNOPSIS"](#synopsis).

# DIAGNOSTICS

One can generate loads of tracing messages to `STDERR` when debug mode is
turned on via the `debug()` function.

Exceptions are thrown when there is a problem with the supplied syntax tree.

# DEPENDENCIES

None beyond the core Perl modules.

# SEE ALSO

[Config::Validator](https://metacpan.org/pod/Config%3A%3AValidator),
[JSON::Validator](https://metacpan.org/pod/JSON%3A%3AValidator),
[JSON](https://metacpan.org/pod/JSON),
[YAML::XS](https://metacpan.org/pod/YAML%3A%3AXS)

# BUGS AND LIMITATIONS

This module is certainly not exhaustive and doesn't contain support for parsing
non-Linux related items, although that would be trivial to add. Also not
everything can be checked. Maybe a future enhancement could be to have a code
reference mechanism whereby code snippets could be included in the syntax tree.

# AUTHOR

Anthony Edward Cooper. Please report all faults and suggestions to
<aecooper@cpan.org>.

# LICENSE AND COPYRIGHT

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
