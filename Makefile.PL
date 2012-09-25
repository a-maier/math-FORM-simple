use warnings;
use strict;
use 5.010001;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'Math::FORM',
    VERSION_FROM => 'lib/Math/FORM.pm',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker'     => '0',
    },
    PREREQ_PM => {
	 'IO::Handle' => 0,
	 'Fcntl' => 0,
	 'Carp' => 0,
	 'Time::HiRes' => 0
    },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Math/FORM.pm',
       AUTHOR         => 'Andreas Maier <maier@to.infn.it>') : ())
    );
