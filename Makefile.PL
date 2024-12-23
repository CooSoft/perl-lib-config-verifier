use 5.036;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Config::Verifier',
    VERSION_FROM      => 'lib/Config/Verifier.pm',
    PREREQ_PM         => {},
    'dist'            => { COMPRESS => 'gzip -9f', SUFFIX => '.gz' },
    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'lib/Config/Verifier.pm',
       AUTHOR         => 'Anthony E Cooper <aecooper@cpan.org>') : ()),
);
