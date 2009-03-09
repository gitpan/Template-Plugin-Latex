#!/usr/bin/perl --  ========================================== -*-perl-*-
#
# t/11-plugin.t
#
# THIS TEST SCRIPT DOES NOT YET PASS - THE ERRORS ARE IN THE SCRIPT ITSELF
#
# Test the Template::Plugin::Latex module.
#
# Written by Andy Wardley <abw@wardley.org>
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use lib qw( ./lib ../lib );

use Test::More skip_all => "need to reallign the tests here with the diagnostics from LaTeX::Driver";


use Template;
use Template::Test;
#$Template::Latex::DEBUG = grep(/-d/, @ARGV);

my $ttcfg = {
    OUTPUT_PATH => 'output',
    FILTERS => {
        head => [ \&head_factory, 1],
    },
};

# Read in the tests from the DATA section and add a test to check that
# the latex filter isn't installed if we the plugin is not loaded.
# The test is not added if the TT2 version is less than 2.16 as up to
# that point the latex filter was included in Template::Filters.

my $tests = join '', <DATA>;

if ($Template::VERSION > 2.15) {
    $tests = join "\n", ("-- test --",
			 "[% TRY; ",
			 "     hello | latex;",
			 "   CATCH undef;",
			 "     error;",
			 "   END",
			 "-%]",
			 "-- expect --",
			 "undef error - latex: filter not found",
			 $tests);
}

test_expect($tests, $ttcfg);


# Grab just the first $len bytes of the input, and optionally convert
# to a hex string if $hex is set

sub head_factory {
    my($context, $len, $hex) = @_;
    $len ||= 72;
    return sub {
        my $text = shift;
        return $text if length $text < $len;
        $text = substr($text, 0, $len);
        $text =~ s/(.)/sprintf("%02x", ord($1))/eg if $hex;
        return $text;
    }
}

__END__

# 1. USE, but then no FILTER - should work
-- test -- 
[[% USE Latex %]]
-- expect --
[]


#------------------------------------------------------------------------
# test error handling
#------------------------------------------------------------------------

# 2. invalid LaTeX source text
-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex;
   CATCH latex;
     error;
   END
%]
-- expect --
latex error - pdflatex exited with errors:
! LaTeX Error: Missing \begin{document}.
l.1 h
! Emergency stop.

# 3. invalid format on USE
-- test --
[% USE Latex format="nonsense"-%]
[% TRY;
     "hello world" FILTER latex;
   CATCH latex;
     error;
   END
%]
-- expect --
latex error - invalid output format: 'nonsense'

# 4. invalid format on FILTER
-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex(format="rubbish");
   CATCH latex;
     error;
   END
%]
-- expect --
latex error - invalid output format: 'rubbish'

# 5. non-existent file
-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("nonsense");
   CATCH latex;
     error;
   END
%]
-- expect --
latex error - cannot determine output format from file name: nonsense


#------------------------------------------------------------------------
# test the ability to grok the format from output argument
#------------------------------------------------------------------------

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("example.pdf");
   CATCH latex;
     error | head(42);
   END
%]
-- expect --
latex error - pdflatex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("EXAMPLE.PDF");
   CATCH latex;
     error | head(42);
   END
%]
-- expect --
latex error - pdflatex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("example.ps");
   CATCH latex;
     error | head(39);
   END
%]
-- expect --
latex error - latex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("example.dvi");
   CATCH latex;
     error | head(39);
   END
%]
-- expect --
latex error - latex exited with errors:


#------------------------------------------------------------------------
# same again with named output/format parameters
#------------------------------------------------------------------------

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex(output="example.pdf");
   CATCH latex;
     error | head(42);
   END
%]
-- expect --
latex error - pdflatex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex(format="pdf");
   CATCH latex;
     error | head(42);
   END
%]
-- expect --
latex error - pdflatex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex(output="example.ps");
   CATCH latex;
     error | head(39);
   END
%]
-- expect --
latex error - latex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex(output="example.ps", format="pdf");
   CATCH latex;
     error | head(42);
   END
%]
-- expect --
latex error - pdflatex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("example.dvi");
   CATCH latex;
     error | head(39);
   END
%]
-- expect --
latex error - latex exited with errors:


#------------------------------------------------------------------------
# test the old-skool usage where the single argument is the format
#------------------------------------------------------------------------

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("pdf");
   CATCH latex;
     error | head(42);
   END
%]
-- expect --
latex error - pdflatex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("ps");
   CATCH latex;
     error | head(39);
   END
%]
-- expect --
latex error - latex exited with errors:

-- test --
[% USE Latex -%]
[% TRY;
     "hello world" FILTER latex("dvi");
   CATCH latex;
     error | head(39);
   END
%]
-- expect --
latex error - latex exited with errors:


#------------------------------------------------------------------------
# try a different filter name
#------------------------------------------------------------------------

-- test --
[% USE Latex filter='pdf' format='pdf' -%]
[% TRY;
     "hello world" FILTER pdf("example.pdf");
   CATCH latex;
     error | head(42);
   END
%]
-- expect --
latex error - pdflatex exited with errors:
