#============================================================= -*-perl-*-
#
# Template::Latex::Paths
#
# DESCRIPTION
#   Provides an interface to Latex from the Template Toolkit.
#
# AUTHOR
#   Andrew Ford    <a.ford@ford-mason.co.uk>  (current maintainer)
#   Andy Wardley   <abw@wardley.org>
#
# COPYRIGHT
#   Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# HISTORY
#   * Latex plugin originally written by Craig Barratt, Apr 28 2001.
#   * Win32 additions by Richard Tietjen.
#   * Extracted into a separate Template::Latex module by Andy Wardley,
#     May 2006
#   * Removed the functionality to specify program pathnames on the FILTER call
#     Andrew Ford, 05 June 2006
#
#========================================================================
 
package Template::Latex::Paths;

use strict;
use warnings;

# LaTeX executable paths set at installation time by the Makefile.PL
our $LATEX     = '/usr/bin/latex';
our $PDFLATEX  = '/usr/bin/pdflatex';
our $DVIPS     = '/usr/bin/dvips';
our $PS2PDF    = '/usr/bin/ps2pdf';
our $BIBTEX    = '/usr/bin/bibtex';
our $MAKEINDEX = '/usr/bin/makeindex';

1;
