#========================================================================
#
# Template::Latex::Driver
#
# DESCRIPTION
#   Internal class to perform the LaTeX filtering process 
#
# AUTHOR
#   Andrew Ford    <a.ford@ford-mason.co.uk>  (current maintainer)
#
# COPYRIGHT
#   Copyright (C) 2006-2007 Andrew Ford.   All Rights Reserved.
#   Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# HISTORY
#   * Extracted from the Template::Latex module (AF, 2007-09-10)
#
#========================================================================

package Template::Latex::Driver;

use strict;
use warnings;

use base 'Class::Accessor';
use File::Copy;
use File::Compare;
use File::Path;
use File::Spec;
use Template::Exception;
use Cwd;

__PACKAGE__->mk_accessors( qw(context config
                              tmpdir basename
                              formatter postprocs status texinput_path
                              undefined_citations undefined_references
                              labels_changed rerun_required) );

our $DIR      = 'tt2latex';     # temporary directory name
our $DOC      = 'tt2latex';     # temporary file name
our $THROW    = 'latex';        # exception type
our $DEBUG    = 0 unless defined $DEBUG;

our $FORMATS  = {               # valid output formats and program alias
    pdf    => 'pdflatex',
    ps     => 'latex',
    ps2pdf => 'latex',
    dvi    => 'latex',
};

# LaTeX (and family) statuses

our $STATUS_UNDEF_REFS  = 1;	# undefined references (re-run latex)
our $STATUS_LABELS_CHGD = 2;	# labels have changed (re-run latex)
our $STATUS_NEW_TOC     = 4;    # new toc (re-run latex)
our $STATUS_NEW_CITN    = 8;    # new citations (run bibtex)
our $STATUS_NEW_INDEX   = 16;   # new index (run makeindex)


#------------------------------------------------------------------------
# run($context, $config)
#
# Constructor for the Latex filter processor
#------------------------------------------------------------------------

sub run {
    my ($class, $text, $context, $config) = @_;

    # Sanity checks first
    # check we're running on a supported OS 
    $class->throw("not available on $^O")
        if $^O =~ /^(MacOS|os2|VMS)$/i;

    # output specified but no OUTPUT_PATH defined 
    $class->throw('OUTPUT_PATH is not set')
        if (defined($config->{output}) and $config->{output} =~ /\.(\w+)$/ and ! $context->config->{ OUTPUT_PATH });


    $DEBUG = $config->{DEBUG};

    # Create an object for the duration of the processing
    my $self = $class->SUPER::new({ context   => $context,
                                    config    => $config,
                                    postprocs => [],
                                    basename  => $DOC });

    my $maxruns = $self->config->{maxruns} || 10;

    # Setup the environment for the filter

    $self->setup_formatter;
    $self->setup_tmpdir;
    $self->setup_texinput_paths;
    $self->create_latex_file($text);


    # Run LaTeX and friends until an error occurs, the document
    # stabilizes, or the maximum number of runs is reached.

  RUN:
    foreach my $run (1 .. $maxruns) {

        if ($self->latex_required) {
            $self->latex;
        }
        else {
            if ($self->bibtex_required) {
                $self->bibtex;
            }
            elsif ($self->makeindex_required) {
                $self->makeindex;
            }
            else {
                last RUN;
            }
            $run--;
        }
    }


    # Run any postprocessors (e.g.: dvips, ps2pdf, etc).

    map { $self->$_ } @{$self->postprocs};


    # Return any output 

    return $self->output;
}


#------------------------------------------------------------------------
# latex()
#
# Run the latex processor (latex or pdflatex depending on what is configured).
#------------------------------------------------------------------------

sub latex {
    my $self = shift;
    
    my $basename = $self->basename;
    my $exitcode = $self->run_command($self->formatter =>
                                      "\\nonstopmode\\def\\TTLATEX{1}\\input{$basename}");


    # If an error occurred attempt to extract the interesting lines
    # from the log file.  Even without errors the log file may contain
    # interesting warnings indicating that LaTeX or one of its friends
    # must be rerun.

    my $errors = "";
    my $logfile = $self->basepath . ".log";

    if (open(FH, "<$logfile") ) {
        $self->reset_latex_required;
        my $matched = 0;
        while ( <FH> ) {
            # TeX errors start with a "!" at the start of the
            # line, and followed several lines later by a line
            # designator of the form "l.nnn" where nnn is the line
            # number.  We make sure we pick up every /^!/ line,
            # and the first /^l.\d/ line after each /^!/ line.
            if ( /^(!.*)/ ) {
                $errors .= $1 . "\n";
                $matched = 1;
            }
            elsif ( $matched && /^(l\.\d.*)/ ) {
                $errors .= $1 . "\n";
                $matched = 0;
            }
            elsif ( /^LaTeX Warning: Citation .* on page \d+ undefined/ ) {
                debug('undefined citations detected') if $DEBUG;
                $self->undefined_citations(1);
            }
            elsif (/LaTeX Warning: There were undefined references./) {
                debug('undefined reference detected') if $DEBUG;
                $self->undefined_references(1)
                    unless $self->undefined_citations;
            }
            elsif (/No file $basename\.(toc|lof|lot)/) {
                debug("missing $1 file") if $DEBUG;
                $self->undefined_references(1);
            }
            elsif ( /^LaTeX Warning: Label(s) may have changed./ ) {
                debug('labels have changed') if $DEBUG;
                $self->labels_changed(1);
            }
        }
        close(FH);
    } 
    else {
        $errors = "failed to open $logfile for input";
    }

    if ($exitcode or $errors) {
        $self->throw($self->formatter . " exited with errors:\n$errors");
    }
}

sub reset_latex_required {
    my $self = shift;
    $self->rerun_required(0);
    $self->undefined_references(0);
    $self->labels_changed(0);
}

sub latex_required {
    my $self = shift;

    my $auxfile = $self->basepath . '.aux';
    return 1
        if $self->undefined_references
        || $self->labels_changed
        || $self->rerun_required
        || ! -f $auxfile;
}


#------------------------------------------------------------------------
# run_bibtex()
#
# Run bibtex to generate the bibliography
# bibtex reads references from the .aux file.
# It looks for .bib file in BIBINPUTS and TEXBIB
# It looks for .bst file in BSTINPUTS
#------------------------------------------------------------------------

sub bibtex {
    my $self = shift;
    
    my $basename = $self->basename;
    my $exitcode = $self->run_command(bibtex => $basename, 'BIBINPUTS');

    # TODO: extract meaningful error message from .blg file

    $self->throw("bibtex $basename failed ($exitcode)")
        if $exitcode;

    # Make a backup of the citations file for future comparison, reset
    # the undefined citations flag and mark the driver as needing to
    # re-run the formatter.

    my $basepath = $self->basepath;
    copy("$basepath.cit", "$basepath.cbk");
    
    $self->undefined_citations(0);
    $self->rerun_required(1);
}


#------------------------------------------------------------------------
# $self->bibtex_required
#
# LaTeX reports 'Citation ... undefined' if it sees a citation
# (\cite{xxx}, etc) and hasn't read a \bibcite{xxx}{yyy} from the aux
# file.  Those commands are written by parsing the bbl file, but will
# not be seen on the run after bibtex is run as the citations tend to
# come before the \bibliography.
#
# The latex driver sets undefined_citations if it sees the message,
# but we need to look at the .aux file and check whether the \citation
# lines match those seen before the last time bibtex was run.  We
# store the citation commands in a .cit file, this is copied to a cbk
# file by the bibtex method once bibtex has been run.  Doing this
# check saves an extra run of bibtex and latex.
#------------------------------------------------------------------------

sub bibtex_required {
    my $self = shift;
    
    if ($self->undefined_citations) {
        my $auxfile = $self->basepath . ".aux";
        my $citfile = $self->basepath . ".cit";
        my $cbkfile = $self->basepath . ".cbk";
        local(*AUXFH);
        local(*CITFH);

        open(AUXFH, "<$auxfile") || return;
        open(CITFH, ">$citfile") 
            or $self->throw("failed to open $citfile for output: $!");

        while ( <AUXFH> ) {
            print(CITFH $_) if /^\\citation/;
        }
        close(AUXFH);
        close(CITFH);

        return if -e $cbkfile and (compare($citfile, $cbkfile) == 0);
        return 1;
    }
    return;
}


#------------------------------------------------------------------------
# $self->makeindex()
#
# Run makeindex to generate the index
#
# makeindex has a '-s style' option which specifies the style file.
# The environment variable INDEXSTYLE defines the path where the style
# file should be found.
#------------------------------------------------------------------------

sub makeindex {
    my $self = shift;
    
    my $basename = $self->basename;
    my $exitcode = $self->run_command(makeindex => $basename);

    # TODO: extract meaningful error message from .ilg file

    $self->throw("makeindex $basename failed ($exitcode)")
        if $exitcode;


    # Make a backup of the raw index file that was just processed, so
    # that we can determine whether makeindex needs to be rerun later.

    my $basepath = $self->basepath;
    copy("$basepath.idx", "$basepath.ibk");

    $self->rerun_required(1);
}


#------------------------------------------------------------------------
# $self->makeindex_required()
#
# Determine whether makeindex needs to be run.  Checks that there is a
# raw index file and that it differs from the backup file (if that exists).
#------------------------------------------------------------------------

sub makeindex_required {
    my $self = shift;
    
    my $basepath = $self->basepath;
    my $raw_index_file = "$basepath.idx";
    my $backup_file    = "$basepath.ibk";

    return unless -e $raw_index_file;
    return if -e $backup_file and (compare($raw_index_file, $backup_file) == 0);
    return 1;
}


#------------------------------------------------------------------------
# dvips()
#
# Run dvips to generate PostScript output 
#------------------------------------------------------------------------

sub dvips {
    my $self = shift;
    
    my $basename = $self->basename;

    my $exitstatus = $self->run_command(dvips => "$basename -o");

    $self->throw("dvips $basename failed ($exitstatus)")
        if $exitstatus;
    
}


#------------------------------------------------------------------------
# ps2pdf()
#
# Run ps2pdf to generate PDF from PostScript output 
#------------------------------------------------------------------------

sub ps2pdf {
    my $self = shift;
    
    my $basename = $self->basename;

    my $exitstatus = $self->run_command(ps2pdf => $basename);

    $self->throw("ps2pdf $basename failed ($exitstatus)")
        if $exitstatus;
}


#------------------------------------------------------------------------
# run_command($progname, $config, $dir, $args, $env)
#
# Run a command in the specified directory, setting up the environment
# and allowing for the differences between operating systems.
#------------------------------------------------------------------------

sub run_command {
    my ($self, $progname, $args, $envvars) = @_;

    # get the full path to the executable for this output format
    my $program = $self->config->{ $progname }
        || $self->throw("$progname cannot be found, please specify its location");

    my $dir  = $self->tmpdir;
    my $null = File::Spec->devnull();
    my $cmd;

    $args ||= '';

    # Set up environment variables
    $envvars ||= "TEXINPUTS";
    $envvars = [ $envvars ] unless ref $envvars;
    $envvars = join(" ", ( map { sprintf("%s=%s", $_,
                                         join(':', @{$self->texinput_path})) }
                           @$envvars ) );


    # Format the command appropriately for our O/S
    if ($^O eq 'MSWin32') {
        # This doesn't set the environment variables yet - what's the syntax?
        $cmd = "cmd /c \"cd $dir && $program $args\"";
    }
    else {
        $args = "'$args'" if $args =~ /\\/;
        $cmd  = "cd $dir; $envvars $program $args 1>$null 2>$null 0<$null";
    }

    debug("running '$program $args'") if $DEBUG;

    my $exitstatus = system($cmd);
    return $exitstatus;
}


#------------------------------------------------------------------------
# $self->setup_formatter
#
# 
#------------------------------------------------------------------------

sub setup_formatter {
    my $self = shift;

    my $config = $self->config;
    my $output = $config->{ output };
    my $format = $config->{ format };


    if ($format) {
        $self->formatter($FORMATS->{ lc $format })
            || $self->throw("invalid output format: $format");
    }
    else {
        # if the format isn't specified then we auto-detect it from the
        # extension of the output filename or look to see if the output
        # filename indicates the format to support old-skool usage, 
        # e.g. FILTER latex('pdf')
        
        $self->throw('output format not specified')
            unless defined $output;

        if ($output =~ /\.(\w+)$/) {
            $self->config->{format} = $format = $1;
            $self->formatter($FORMATS->{ lc $format })
                || $self->throw("invalid output format: $format");
        }
        elsif ($self->formatter($FORMATS->{ lc $output })) {
            $format = $output;
            delete $config->{ output };
        }
        else {
            $self->throw("cannot determine output format from file name: $output");
        }
    }

    # get the full path to the executable for this output format

    $self->throw($self->formatter . " cannot be found, please specify its location")
        unless $config->{ $self->formatter };


    # we also need dvips and ps2pdf as postprocessors for ps or pdf via ps output
    if ($format =~ /^ps(2pdf)?$/) {
        $config->{format} = 'pdf' if $1;
        $self->throw("dvips cannot be found, please specify its location")
            unless $config->{ dvips };
        push(@{$self->postprocs}, 'dvips');

        if ($format eq 'ps2pdf' or (defined($output) and $output =~ /\.pdf$/)) {
            $self->throw("ps2pdf cannot be found, please specify its location")
                unless $config->{ ps2pdf };
            push(@{$self->postprocs}, 'ps2pdf');
        }
    }
}


#------------------------------------------------------------------------
# $self->setup_texinput_paths
#
# setup the TEXINPUT path environment variables
#------------------------------------------------------------------------

sub setup_texinput_paths {
    my $self = shift;
    my $context = $self->context;
    my $template_name = $context->stash->get('template.name');
    my $include_path  = $context->config->{INCLUDE_PATH} || [];
    $include_path = [ $include_path ] unless ref $include_path;

    my @texinput_paths = ("");
    foreach my $path (@$include_path) {
        my $template_path = File::Spec->catfile($path, $template_name);
        if (-f $template_path) {
            my($volume, $dir) = File::Spec->splitpath($template_path);
            $dir = File::Spec->catfile($volume, $dir);
            unshift @texinput_paths, $dir;
            next if $dir eq $path;
        }
        push @texinput_paths, $path;
    }
    $self->texinput_path(\@texinput_paths);
}


#------------------------------------------------------------------------
# $self->setup_tmpdir
#
# create a temporary directory 
#------------------------------------------------------------------------

sub setup_tmpdir {
    my $self = shift;
    my $tmp  = File::Spec->tmpdir();
    my $dir  = $self->config->{tmpdir};

    if ($dir) {
        $dir = File::Spec->catdir($tmp, $dir);
        eval { mkpath($dir, 0, 0700) } unless -d $dir;
    }
    else {
        my $n = 0;
        do { 
            $dir = File::Spec->catdir($tmp, "$DIR$$" . '_' . $n++);
        } while (-e $dir);
        eval { mkpath($dir, 0, 0700) };
    }
    $self->throw("failed to create temporary directory: $@") 
        if $@;
    $self->tmpdir($dir);
    return;
}


#------------------------------------------------------------------------
# $self->cleanup
#
# cleans up the temporary directory if it exists and was not specified
# as a configuration option
#------------------------------------------------------------------------

sub cleanup {
    my $self = shift;
    return unless ref $self;
    return if $self->config->{tmpdir};
    my $tmpdir = $self->tmpdir;
    rmtree($tmpdir) if defined($tmpdir) and -d $tmpdir;
}


#------------------------------------------------------------------------
# $self->create_latex_file($text)
#
# Create the LaTeX input file in the temporary directory.
#------------------------------------------------------------------------

sub create_latex_file {
    my ($self, $text) = @_;
    local(*FH);

    # open .tex file for output
    my $file = $self->basepath . ".tex";
    unless (open(FH, ">$file")) {
        $self->throw("failed to open $file for output: $!");
    }
    print(FH $text);
    close(FH);
}


#------------------------------------------------------------------------
# $self->output
#
# Create the LaTeX input file in the temporary directory.
#------------------------------------------------------------------------

sub output {
    my $self = shift;
    my ($data, $path, $dest, $ok);
    local(*FH);

    # construct file name of the generated document
    my $config = $self->config;
    my $format = $config->{format};
    my $output = $config->{output};
    my $file = $self->basepath . '.' . ($format || 'dvi');

    if ($output) {
        $path = $self->context->config->{ OUTPUT_PATH }
            || $self->throw('OUTPUT_PATH is not set');
        $dest = File::Spec->catfile($path, $output);

        # see if we can rename the generate file to the desired output 
        # file - this may fail, e.g. across filesystem boundaries (and
        # it's quite common for /tmp to be a separate filesystem
        if (rename($file, $dest)) {
            debug("renamed $file to $dest") if $DEBUG;
            # success!  clean up and return nothing much at all
            $self->cleanup;
            return '';
        }
    }

    # either we can't rename the file or the user hasn't specified
    # an output file, so we load the generated document into memory
    unless (open(FH, $file)) {
        $self->throw("failed to open $file for input");
    }
    local $/ = undef;       # slurp file in one go
    binmode(FH);
    $data = <FH>;
    close(FH);

    # cleanup the temporary directory we created
    $self->cleanup;

    # write the document back out to any destination file specified
    if ($output) {
        debug("writing output to $dest\n") if $DEBUG;
        my $error = Template::_output($dest, \$data, { binmode => 1 });
        $self->throw($error) if $error;
        return '';
    }

    debug("returning ", length($data), " bytes of document data\n")
        if $DEBUG;

    # or just return the data
    return $data;
}


sub basepath {
    my $self = shift;
    return File::Spec->catfile($self->tmpdir, $self->basename);
}


#------------------------------------------------------------------------
# throw($error)
#
# Throw an error message as a Template::Exception.
#------------------------------------------------------------------------

sub throw {
    my $self = shift;
    $self->cleanup;
    die Template::Exception->new( $THROW => join('', @_) );
}

sub debug {
    print STDERR "[latex] ", @_;
    print STDERR "\n" unless $_[-1] =~ /\n$/;
}


1;

__END__

=head1 NAME

Template::Latex::Driver - Latex driver for the Template Toolkit

=head1 SYNOPSIS

This is an internal package not intended to be used directly.
  
=head1 DESCRIPTION

The Template::Latex::Driver module is an internal package for the
Template Toolkit Latex filter.  It is used by the Template::Latex
package and encapsulates the details of invoking the Latex programs.

=head1 INTERNALS

This section is aimed at a technical audience.  It documents the
internal methods and subroutines as a reference for the module's
developers, maintainers and anyone interesting in understanding how it
works.  You don't need to know anything about them to use the module
and can safely skip this section.


=head1 THE FORMATTING PROCESS

Formatting with LaTeX is complicated; there are potentially many
programs to run and the output of those programs must be monitored to
determine whether processing is complete.

The original C<latex> filter that was part of Template Toolkit prior
to version 2.16 was fairly simplistic.  It created a temporary
directory, copied the source text to a file in that directory, and ran
either C<latex> or C<pdflatex> on the file once, or if postscript
output was requested then it would run C<latex> and then C<dvips>.
This did not cope with documents that contained forward references, a
table of contents, lists of figures or tables, bibliographies, or
indexes.



=head2 Formatting with LaTeX or PDFLaTeX

finds inputs in TEXINPUTS, TEXINPUTS_latex, TEXINPUTS_pdflatex, etc


=head2 Generating indexes

The standard program for generating indexes is C<makeindex>.  

The program makeindex is a general purpose hierarchical index generator; it accepts
one or  more input files (often produced by a text formatter such as TeX (tex(1L))
or troff(1), sorts the entries, and produces an output file which can be formatted.

INDEXSTYLE


=head2 Running BiBTeX

BiBTeX generates a bibliography for a LaTeX document.  It reads the
top-level auxiliary file (.aux) output during the running of latex and
creates a bibliograpy file (.bbl) that will be incorporated into the
document on subsequent runs of latex.  It looks up the entries
specified by \cite and \nocite commands in the bibliographic database
files (.bib) specified by the \bibliography commands.  The entries are
formatted according to instructions in a bibliography style file
(.bst), specified by the \bibliographystyle command.

Bibliography style files are searched for in the path specified by the
C<BSTINPUTS> environment variable; for bibliography files it uses the
C<BIBINPUTS> environment variable.  System defaults are used if these
environment variables are not set.


=head2 Running Dvips 

The C<dvips> program takes a DVI file produced by TeX and converts it
to PostScript.


=head2 Running ps2pdf    


=head2 Misc

kpathsea, web2c

=head2 Running on Windows



=head1 AUTHOR

Andrew Ford E<lt>a.ford@ford-mason.co.ukE<gt>


=head1 COPYRIGHT

Copyright (C) 2006-2007 Andrew Ford.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin::Latex>, L<Template::Latex>, L<makeindex(1)>,
L<bibtex(1)>, L<dvips(1)>, The dvips manual

There are a number of books and other documents that cover LaTeX:

=over 4

=item *

The LaTeX Companion

=item *

Web2c manual

=back

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
