# NAME

Config::Verifier - Verify the structure and values inside Perl data structures

# VERSION

1.0

# SYNOPSIS

    use Config::Verifier;
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
              's:use_syslog'              => 'R:boolean'},
         's:allowed_hosts'  =>
             ['R:hostname',
              'R:ipv4_addr',
              'R:ipv4_cidr',
              'R:ipv6_addr',
              'R:ipv6_cidr'],
         's:denied_hosts'  =>
             ['R:hostname',
              'R:ipv4_addr',
              'R:ipv4_cidr',
              'R:ipv6_addr',
              'R:ipv6_cidr']);
    my $data = YAML::XS::LoadFile('my-config.yml');
    my $verifier = Config::Verifier->new(\%settings_syntax_tree);
    my $status = $verifier->check($data);
    die("Syntax error detected. The reason given was:\n" . $status)
        if ($status ne '');

# DESCRIPTION

The Config::Verifier class checks the given Perl data structure against the
specified syntax tree. Whilst it can be used to verify any structured data
ingested into Perl, its main purpose is to check human generated configuration
data as the error messages are designed to be informative and helpful. It's also
designed to be lightweight, not having any dependencies beyond the core Perl
modules.

When reading in configuration data from a file, it's up to the caller to decide
exactly how this is done. Typically one would use some sort of parsing module
like [JSON](https://metacpan.org/pod/JSON) or [YAML::XS](https://metacpan.org/pod/YAML%3A%3AXS) (which I have found to be the more stringent for
YAML files).

Whilst this module could be used to verify data from many sources, like RESTful
API requests, you would invariably be better off with a module that could read
in a proper schema in an officially recognised format. One such module, for
validating both JSON and YAML is [JSON::Validator](https://metacpan.org/pod/JSON%3A%3AValidator). However due to its very
capable nature, it does pull in a lot of dependencies, which can be undesirable
for smaller projects, hence this module.

If this module is not to your liking then another option, which I believe
supports ini style configuration files, is [Config::Validator](https://metacpan.org/pod/Config%3A%3AValidator).

# CONSTRUCTOR

- **new(\[$syntax\_tree\])**

    Creates a new Config::Verifier object. `$syntax_tree` is an optional reference
    to a syntax tree that describes what data should be present and its basic
    format.

# SUBROUTINES/METHODS

- **amount\_to\_units($amount)\[, $want\_bits\]**

    Converts the amount given in `$amount` into units. An amount takes the form as
    described by `'R:amount'` or `'R:amount_data'` and is either a number
    optionally followed K, M, G, or T, or a number followed by KB, Kb, KiB, Kib up
    to up to TB etc respectively. For the data amounts B and b refer to bytes and
    bits, whilst KiB and KB refer to 1024 bytes and 1000 bytes and so on. If
    `$want_bits` is set to true then the returned amount is in bits rather than
    bytes. The default default is false and it only applies to amounts of data.

- **check($data, $name)**

    Checks the specified structure making sure that the domain specific syntax is
    ok.

    `$data` is a reference to the data structure that is to be checked, typically a
    hash, i.e. a record, but it can also be a list. `$name` is a string containing
    a descriptive name for the data structure being checked. This will be used as
    the base name in any error messages returned by this method.

- **debug(\[$flag\])**

    Turns on the output of debug messages to `STDERR` when `$flag` is set to true,
    otherwise debug messages are turned off. If `$flag` isn't specified then
    nothing changes.

    The any new debug setting is either changed globally, which will affect all
    newly created objects, or just changed within the current object, depending upon
    whether this method is called as a class or an instance method.

- **duration\_to\_seconds($duration)**

    As above but for seconds. A duration takes the form as described by
    `'R:duration_seconds'` and is a number followed by a time unit that can be one
    of s, m, h, d, or w for seconds, minutes, hours, days and weeks respectively.

- **match\_syntax\_value($syntax, $value\[, $error\])**

    Tests the data in `$value` against a syntax pattern as given by `$syntax`. A
    syntax pattern is something like `'R:hostname'` or `'i:1,10'`. `$error` is an
    optional reference to a string that is to contain any type/value errors that are
    detected.

- **register\_syntax\_regex($name, $regex)**

    Registers the regular expression string `$regex`, which is not a compiled RE
    object, as a syntax pattern under the name given in `$name`. This is then
    available for use as `'R:name'` just like the built in syntax patterns. This
    can be used to replace most built in patterns or extend the list of patterns.
    The regular expression must be anchored, i.e. start and end with `^` and `$`
    respectively.

    The new regular expression term either goes into the global default table, which
    will affect newly created objects, or the object's own private table, depending
    upon whether this method is called as a class or an instance method.

- **string\_to\_boolean($string)**

    Converts the amount given in `$string` into a boolean (1 or 0). A string
    representing a boolean takes the form as described by `'R:boolean'` and can be
    one of true, yes, Y, y, or on for true and false, no N, n, off or '' for false.

- **syntax\_tree($syntax\_tree)**

    Sets the object's syntax tree reference to the one given in `$syntax_tree`.

# RETURN VALUES

`new()` returns a new Config::Verifier object.

`amount_to_units()` returns an integer.

`check()` returns a string containing the details of the problems encountered
when parsing the data on failure, otherwise an empty string on success.

`debug()` returns the previous debug message setting as a boolean.

`duration_to_seconds()` returns the number of seconds that the specified
duration represents.

`match_syntax_value()` returns true for a match, otherwise false for no match.

`register_syntax_regex()` returns nothing.

`string_to_boolean()` returns a boolean.

`syntax_tree()` returns nothing.

# NOTES

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
    R:duration
    R:hostname
    R:ipv4_addr
    R:ipv4_cidr
    R:ipv6_addr
    R:ipv6_cidr
    R:name
    R:plugin
    R:printable
    R:string
    R:unix_path
    R:user_name
    R:variable
    R:windows_path

One can add to the built in list or replace existing entries by using the
`register_syntax_regex()` method.

## Syntax Trees

These trees, a container of some sort, typically a hash, describe what should
appear in a given data structure. The hash's key names represent fields that can
be present and their values either refer to further containers, for nested
records or lists, or strings that describe the type of value that should be
present for that field. Key names are strings that consist of a type character
followed by a colon and then the field name. Key and value types are as follows:

    c:      - Custom entries follow, i.e. a key lookup failure isn't an
              error. This is used to cater for parts of a syntax tree that
              need to be dynamic and handled separately.
    f:m,M   - A floating point number with optional minimum and Maximum
              qualifiers.
    i:m,M,s - An integer with optional minimum, Maximum and step qualifiers.
    l:type  - The type of list in the syntax tree. This determines how lists
              are treated. There are two types choice_list, the default, and
              choice_value:
              choice_list:  With this type a list is expected in the data,
                            with each element of the syntax list
                            representing one of the allowed types that an
                            entry can take within the data list.
              choice_value: With this type a singular item is expected in
                            the data, with each element of the syntax list
                            representing one of the allowed types that the
                            data item can be. Having said that, should a
                            list or record be specified in the syntax list
                            then this permits the singular data item to also
                            be a list or record. Thus you could use this
                            type of list to have a field that could take a
                            scalar value, a list or a record.
              Each type can also take an additional allow_empty_list
              qualifier (separated by a comma). This permits the list to be
              empty in the data. The default is to treat an empty list as an
              error.
    m:s     - A plain string literal s, representing the name of a mandatory
              field, which is case sensitive.
    R:n     - A built in regular expression with the name n, that is used to
              match against acceptable values. This can also be used to
              match against optional fields that fit that pattern.
    r:reg   - Like R:n but the regular expression is supplied by the caller.
    s:s     - A plain string literal s, representing the the name
              of an optional field or a literal value, both or which are
              which are case sensitive.
    t:s     - Like m: but also signifies a typed field, i.e. a field that
              uniquely identifies the type of the record via its value. Its
              corresponding value must uniquely identify the type of record
              within the list of records at that point in the schema.
    Lists   - These represent not only that a list of items should be
              present but also that there can be a choice in the different
              types of items, e.g scalar, list or hash.
    Hashes  - These represent records with named fields.

Typically keys can be anything other than containers and values are specific
types, regular expressions or containers. The R: style syntax patterns mentioned
above provide regular expressions for the more common syntax elements.

Please see the example under ["SYNOPSIS"](#synopsis).

# DIAGNOSTICS

One can generate lots of tracing messages to `STDERR` when debug mode is turned
on via the `debug()` method.

With the exception of the `debug()` and `string_to_boolean()` methods,
exceptions are thrown when there is a problem with the supplied syntax tree or
value. Since illegal values read in from configuration data will be detected
when it is parsed, exceptions from these methods will most likely indicate a
fault with the calling program. Exceptions from this library are
`Config::Verifier::Exception` objects that can be cast to strings.

Problems with the data being parsed are returned as a string from the `check()`
method. Where possible all parsing errors will be listed, one line per error, in
a form suitable for the end user.

# DEPENDENCIES

None beyond the core Perl modules.

# SEE ALSO

[Config::Validator](https://metacpan.org/pod/Config%3A%3AValidator),
[JSON::Validator](https://metacpan.org/pod/JSON%3A%3AValidator),
[JSON](https://metacpan.org/pod/JSON),
[YAML::XS](https://metacpan.org/pod/YAML%3A%3AXS)

# BUGS AND LIMITATIONS

Whilst this module could be used to validate data conforming to a schema it's
really designed for checking configuration data. If used in high data rate
communications you will probably find other libraries better able to support
standard schema definitions and possibly in a more performant way.

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
