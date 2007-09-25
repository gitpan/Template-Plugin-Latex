#============================================================= -*-perl-*-
#
# Template::Plugin::Latex
#
# DESCRIPTION
#   Template Toolkit plugin for Latex
#
# AUTHOR
#   Andrew Ford    <a.ford@ford-mason.co.uk>  (current maintainer)
#   Andy Wardley   <abw@wardley.org>          (original author)
#
# COPYRIGHT
#   Copyright (C) 2006-2007 Andrew Ford.   All Rights Reserved.
#   Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# HISTORY
#   * Originally written by Craig Barratt, Apr 28 2001.
#   * Win32 additions by Richard Tietjen.
#   * Extracted into a separate Template::Plugin::Latex module by 
#     Andy Wardley, 27 May 2006
#   * Removed the program pathname options on the FILTER call
#     Andrew Ford, 05 June 2006
#
#========================================================================
 
package Template::Plugin::Latex;

use strict;
use warnings;
use base 'Template::Plugin';

use LaTeX::Driver;

our $VERSION = 3.00_01;
our $DEBUG   = 0 unless defined $DEBUG;
our $ERROR   = '';
our $FILTER  = 'latex';

#------------------------------------------------------------------------
# constructor
#
#------------------------------------------------------------------------

sub new {
    my ($class, $context, $options) = @_;

    # make sure that $options is a hash ref
    $options ||= {};

    # create a closure to generate filters with additional options
    my $filter_factory = sub {
        my $context = shift;
        my $filter_opts = ref $_[-1] eq 'HASH' ? pop : { };
        my $filter_args = [ @_ ];
        @$filter_opts{ keys %$options } = values %$options;
        return sub {
            Template::Plugin::Latex::_filter->run($context, $filter_opts, $filter_args, @_);
        };
    };

    # and a closure to represent the plugin
    my $plugin = sub {
        my $plugopt = ref $_[-1] eq 'HASH' ? pop : { };
        @$plugopt{ keys %$options } = values %$options;
        Template::Plugin::Latex::_filter->run($context, $plugopt, @_ );
    };


    # now define the filter and return the plugin
    $context->define_filter('latex_encode', \&_tt_latex_encode_filter);
    $context->define_filter($options->{filter} || $FILTER, [ $filter_factory => 1 ]);
    return $plugin;
}



our %latex_encoding;

# Greek letters
my $i = 0;
foreach (qw( alpha beta gamma delta epsilon zeta eta theta
             iota kappa lamda mu nu xi omicron pi rho
             final_sigma sigma tau upsilon phi chi psi omega ))
{
    $latex_encoding{chr(0x3b1+$i)} = "\\$_";
    $latex_encoding{chr(0x391+$i)} = "\\\u$_";
    $i++;
}

# Special Characters from http://www.cs.wm.edu/~mliskov/texsymbols.pdf

my %euro = (
    chr(0x2020) => 'dag', # Dagger
    chr(0x2021) => 'ddag', # Double-dagger
    chr(0xa7)   => 'S', # Section mark
    chr(0xb6)   => 'P', # Paragraph
    chr(0xdf)   => 'ss', # German sharp S
    chr(0x152)  => 'OE', # French ligature OE
    chr(0x153)  => 'oe', # French ligature oe
    chr(0x141)  => 'L', # Polish suppressed-l
    chr(0x142)  => 'l', # Polish suppressed-L
    chr(0xd8)   => 'O', # Scandinavian O-with-slash
    chr(0xf8)   => 'o', # Scandinavian o-with-slash
    chr(0xc5)   => 'AA', # Scandinavian A-with-circle
    chr(0xe5)   => 'aa', # Scandinavian a-with-circle
    chr(0x131)  => 'i', # dotless i
    chr(0x237)  => 'j', # dotless j
    );


sub _tt_latex_encode_filter { 
    my $options = ref $_[-1] eq 'HASH' ? pop : { };
    my $text = shift;
    $text =~ s/\x{01}/\x{01}\x{02}/g;
    $text =~ s/\\/\x{01}\x{03}/g;
    $text =~ s/([{}&_%#^\$])/\\$1/g;
    if (!exists $options->{use_textcomp} or !$options->{use_textcomp}) {
        $text =~ s/([^\x00-\x80])(?![A-Za-z0-9])/$latex_encoding{$1}/sg;
        $text =~ s/([^\x00-\x80])/$latex_encoding{$1}\{\}/sg;
    }
    $text =~ s/\x{01}\x{03}/\\textbackslash{}/g;
    $text =~ s/\x{01}\x{02}/\x{01}/g;
    return $text;
}




#------------------------------------------------------------------------
#  Internal package in which to run the filter
#------------------------------------------------------------------------

package Template::Plugin::Latex::_filter;

use strict;
use warnings;
use base 'Class::Accessor';

use File::Spec;
use File::Copy;
use File::Path;

__PACKAGE__->mk_accessors( qw(tmpdir basename basepath context options) );

our $TMP_DIRNAME = 'tt2latex';     # temporary directory name
our $TMP_DOCNAME = 'tt2latex';     # temporary file name
our $THROW       = 'latex';        # exception type
our $DEBUG;

sub run {
    my ($class, $context, $options, $filter_args, $text) = @_;

    # Make a copy of the options hash.
    $options = { %$options };

    my $self = $class->SUPER::new({ context => $context,
                                    options => $options });


    my $output   = delete $options->{ output } || shift(@$filter_args) || '';
    my $basename = $output || $TMP_DOCNAME;
    if ($basename =~ s/(?:(.*?)\.)?(dvi|ps|pdf(?:\(dvi\)|\(ps\))?)$/$1/) {
        $options->{format} = $2;
    }

    $basename =~ s/\.\w+$//;
    $self->options->{basename} = $self->basename($basename);

    $self->setup_tmpdir;
    $self->setup_texinput_paths;
    $self->create_latex_file($text);
    
    my $drv = LaTeX::Driver->new($options);

    eval { $drv->run; };
    
    if (my $e = LaTeX::Driver::Exception->caught()) {
        $self->throw("$e");
    }

    $output = $self->copy_output($output);
    $self->cleanup;
    return $output;
}


#------------------------------------------------------------------------
# $self->_setup_tmpdir
#
# create a temporary directory 
#------------------------------------------------------------------------

sub setup_tmpdir {
    my $self = shift;

    my $tmp  = File::Spec->tmpdir();
    my $dir  = $self->options->{tmpdir};

    if ($dir) {
        $dir = File::Spec->catdir($tmp, $dir);
        eval { mkpath($dir, 0, 0700) } unless -d $dir;
    }
    else {
        my $n = 0;
        do { 
            $dir = File::Spec->catdir($tmp, "$TMP_DIRNAME$$" . '_' . $n++);
        } while (-e $dir);
        eval { mkpath($dir, 0, 0700) };
    }
    $self->throw("failed to create temporary directory: $@") 
        if $@;
    $self->options->{basedir} = $self->tmpdir($dir);
    return;
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
    $self->options->{TEXINPUTS} = \@texinput_paths;
}

#------------------------------------------------------------------------
# $self->output
#
# Create the LaTeX input file in the temporary directory.
#------------------------------------------------------------------------

sub copy_output {
    my ($self, $output) = @_;
    my ($data, $path, $dest, $ok);
    local(*FH);

    # construct file name of the generated document
    my $options = $self->options;
    my $format  = $options->{format} || '';
    $format =~ s/\(.*\)//;

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


#------------------------------------------------------------------------
# $self->cleanup
#
# cleans up the temporary directory if it exists and was not specified
# as a configuration option
#------------------------------------------------------------------------

sub cleanup {
    my $self = shift;
    return unless ref $self;
    return if $self->options->{tmpdir};
    my $tmpdir = $self->tmpdir;
    rmtree($tmpdir) if defined($tmpdir) and -d $tmpdir;
}

sub throw {
    my $self = shift;
    $self->cleanup;
    die Template::Exception->new( $THROW => join('', @_) );
}

sub debug {
    print STDERR "[latex] ", @_;
    print STDERR "\n" unless $_[-1] =~ /\n$/;
}

sub basepath {
    my $self = shift;
    return File::Spec->catfile($self->tmpdir, $self->basename);
}


1;

__END__

=head1 NAME

Template::Plugin::Latex - Template Toolkit plugin for Latex

=head1 VERSION

This documentation refers to C<Template::Plugin::Latex> version 3.00_01

=head1 SYNOPSIS

    [%  # sample Template Toolkit code

        USE Latex;

        mystr = "a, b & c" FILTER latex_encode;

        mydoc = BLOCK %]

    \documentclass{article}
    \begin{document}
      This is a PDF document generated by 
      LaTeX and the Template Toolkit, with some 
      interpolated data: [% mystr %]
    \end{document}

    [%  END;

        mydoc FILTER latex("pdf");

        # eat all whitespace 

     -%]

=head1 DESCRIPTION

This plugin allows you to use LaTeX to generate PDF, PostScript and
DVI output files from the Template Toolkit.  

The C<latex> filter was distributed as part of the core Template
Toolkit until version 2.15 released in May 2006 when it was moved into
the separate Template-Latex distribution.  It should now be loaded as
a plugin to enable the C<latex> filter:

=head1 SUBROUTINES/METHODS

=head2 C<USE Latex(options)>

This statement loads the plugin (note that prior to version 2.15 the
filter was built in to Template Toolkit so this statement was
unnecessary; it is now required).


=head2 The C<latex> Filter

The C<latex> filter accepts a number of options, which may be
specified on the USE statement or on the filter invocation.

=over 4

=item C<format>

specifies the format of the output; one of C<dvi> (TeX device
independent format), C<ps> (PostScript) or C<pdf> (Adobe Portable
Document Format).  The follow special values are also accepted:
C<pdf(ps)> (generates PDF via PostScript, using C<dvips> and
C<ps2pdf>), C<pdf(dvi)> (generates PDF via dvi, using C<dvipdfm>)

=item C<output>

the name of the output file, or just the output format

=item C<indexstyle>

the name of the C<makeindex> style file to use (this is passed with
the C<-s> option to C<makeindex>)

=item C<indexoptions>

options to be passed to C<makeindex>.  Useful options are C<-l> for
letter ordering of index terms (rather than the default word
ordering), C<-r> to disable implicit page range formation, and C<-c>
to compress intermediate blanks in index keys. Refer to L<makeindex(1)>
for full details.

=item C<maxruns>

The maximum number of runs of the formatter program (defaults to 10).

=item C<extraruns>

The number of additional runs of the formatter program after it seems
that the formatting of the document has stabilized (default 0).  Note
that the setting of C<maxruns> takes precedence, so if C<maxruns> is
set to 10 and C<extraruns> is set to 3, and formatting stabilizes
after 8 runs then only 2 extra runs will be performed.

=back


=head2 The C<latex_encode> filter

The C<latex_encode> filter encodes LaTeX special characters in its
input into their LaTeX encoded representations.  It also encodes other characters that have

The special characters are: C<\> (command character), C<{> (open
group), C<}> (end group), C<&> (table column separator), C<#>
(parameter specifier), C<%> (comment character), C<_> (subscript),
C<^> (superscript), C<~> (non-breakable space), C<$> (mathematics mode).


=over 4

=item C<except>

Lists the characters that should be excluded from encoding.  By
default no special characters are excluded, but it may be useful to
specify C<except = "\\{}"> to allow the input string to contain LaTeX
commands such as C<"this is \\textbf{bold} text">.

=item C<use_textcomp>

By default the C<latex_encode> filter will encode characters with the
encodings provided by the C<textcomp> LaTeX package (for example the
Pounds Sterling symbol is encoded as C<\\textsterling{}>).  Setting
C<use_textcomp = 0> turns off these encodings.

=back



=head1 OLD DOCUMENTATION


    [% USE Latex -%]
    [% FILTER latex %]
    ...LaTeX document...
    [% END %] 

You can specify a different filter name using the C<filter> parameter.

    [% USE Latex(filter='pdf') -%]
    [% FILTER pdf %]
    ...LaTeX document...
    [% END %] 

You can also specify the default output format.  This value can be
C<latex>, C<pdf> or C<dvi>.

    [% USE Latex(format='pdf') %]

With the plugin loaded and a default format defined, you can now use
the C<latex> filter.

    [% FILTER latex -%]
    \documentclass{article}
    \begin{document}
    This is a PDF document generated by 
    Latex and the Template Toolkit.
    \end{document}
    [% END %]

You can pass additional arguments when you invoke the filter to 
specify the output format.

    [% FILTER latex(format='pdf') -%]
       ...LaTeX document...
    [% END %]

The template content between the C<FILTER> and C<END> directives will
be piped to the appropriate program(s) to generate the document
output.  This is fine if you're generating a document directly from a
template.  For example:

F<example.pdf>:

    [% USE Latex(format='pdf') -%]
    [% FILTER latex %]
    ...LaTeX document...
    [% END -%]

The output will be a binary format PDF, PostScript or DVI file.  You
should be careful not to prepend or append any extraneous characters
or text outside the FILTER block as this text will be included in the
file output.  Notice in the above example how we use the post-chomp
flags ('-') at the end of the C<USE> and C<END> directives to remove
the trailing newline characters.

If you're redirecting the output to a file via the third argument of
the Template module's C<process()> method then you should also pass
the C<binmode> parameter set to a true value to indicate that it is a
binary file.

    use Template;
    
    my $tt = Template->new({
        INCLUDE_PATH => '/path/to/templates',
        OUTPUT_PATH  => '/path/to/pdf/output',
    });
    my $vars = {
        title => 'Hello World',
    }
    $tt->process('example.tt2', $vars, 'example.pdf', binmode => 1)
        || die $tt->error();

If you want to capture the output to a template variable, you can do
so like this:

    [% output = FILTER latex %]
    ...LaTeX document...
    [% END %]

If you want to write the output to a file then you can specify an 
C<output> parameter.

    [% FILTER latex(output='example.pdf') %]
    ...LaTeX document...
    [% END %]

If you don't explicity specify an output format then the filename
extension (e.g. 'pdf' in the above example) will be used to determine
the correct format.



=head1 DEPENDENCIES

=head1 BUGS AND LIMITATIONS

The paths to the F<latex>, F<pdflatex> and F<dvips> should be
pre-defined as part of the installation process (i.e. when you run
C<perl Makefile.PL>).  You can specify alternate values as
configuration options to the C<Template> constructor in the Perl
inteface, but there are no option to specify these paths in template code as this 

=head1 AUTHOR

Andrew Ford E<lt>a.ford@ford-mason.co.ukE<gt> (current maintainer)

Andy Wardley E<lt>abw@wardley.orgE<gt> L<http://wardley.org/>

The original Latex plugin on which this is based was written by Craig
Barratt with additions for Win32 by Richard Tietjen.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2006-2007 Andrew Ford.  All Rights Reserved.

Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

This software is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=head1 SEE ALSO

L<Template::Latex>, L<LaTeX::Driver>

=cut




# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
