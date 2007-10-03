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
#   * Totally rewritten by Andrew Ford September 2007
#
#========================================================================
 
package Template::Plugin::Latex;

use strict;
use warnings;
use base 'Template::Plugin';

use File::Spec;
use LaTeX::Driver 0.06;
use LaTeX::Encode;


our $VERSION = "3.00_02";
our $DEBUG   = 0 unless defined $DEBUG;
our $ERROR   = '';
our $FILTER  = 'latex';
our $THROW   = 'latex';        # exception type

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
            # Template::Plugin::Latex::_filter->run($context, $filter_opts, $filter_args, @_);
            _tt_latex_filter($class, $context, $filter_opts, $filter_args, @_);
        };
    };

    # create a closure to generate filters with additional options
    my $encode_filter_factory = sub {
        my $context = shift;
        my $filter_opts = ref $_[-1] eq 'HASH' ? pop : { };
        my $filter_args = [ @_ ];
        @$filter_opts{ keys %$options } = values %$options;
        return sub {
            # Template::Plugin::Latex::_filter->run($context, $filter_opts, $filter_args, @_);
            _tt_latex_encode_filter($class, $context, $filter_opts, $filter_args, @_);
        };
    };

    # and a closure to represent the plugin
    my $plugin = sub {
        my $plugopt = ref $_[-1] eq 'HASH' ? pop : { };
        @$plugopt{ keys %$options } = values %$options;
        # Template::Plugin::Latex::_filter->run($context, $plugopt, @_ );
        _tt_latex_filter($class, $context, $plugopt, {}, @_ );
    };


    # now define the filter and return the plugin
    $context->define_filter('latex_encode', [ $encode_filter_factory => 1 ]);
    $context->define_filter($options->{filter} || $FILTER, [ $filter_factory => 1 ]);
    return $plugin;
}


#------------------------------------------------------------------------
# _tt_latex_encode_filter
#
#
#------------------------------------------------------------------------

sub _tt_latex_encode_filter { 
    my ($class, $context, $options, $filter_args, @text) = @_;
    my $text = join('', @text);
    return latex_encode($text, %{$options});
}


#------------------------------------------------------------------------
# _tt_latex_filter
#
#
#------------------------------------------------------------------------

sub _tt_latex_filter {
    my ($class, $context, $options, $filter_args, @text) = @_;
    my $text = join('', @text);

    # Get the output and format options

#    my $output = $options->{output};
    my $output = delete $options->{ output } || shift(@$filter_args) || '';
    my $format = $options->{format};

    # If the output is just a format specifier then set the format to
    # that and undef the output

    if ($output =~ /^ (?: dvi | ps | pdf(?:\(\w+\))? ) $/x) {
        ($format, $output) = ($output, undef);
    }

    # If the output is a filename then convert to a full pathname in
    # the OUTPUT_PATH directory, outherwise set the output to a
    # reference to a temporary variable.

    if ($output) {
        my $path = $context->config->{ OUTPUT_PATH }
            or $class->throw('OUTPUT_PATH is not set');
        $output = File::Spec->catfile($path, $output);
    }
    else {
        my $temp;
        $output = \$temp;
    }

    # Run the formatter

    eval {
        my $drv = LaTeX::Driver->new( source    => \$text,
                                      output    => $output,
                                      format    => $format,
                                      maxruns   => $options->{maxruns},
                                      extraruns => $options->{extraruns},
                                      texinputs => _setup_texinput_paths($context),
                                    );
        $drv->run;
    };        
    if (my $e = LaTeX::Driver::Exception->caught()) {
        $class->throw("$e");
    }

    # Return the text if it was output to a scalar variable, otherwise
    # return nothing.

    return ref $output ? $$output : '';
}


#------------------------------------------------------------------------
# $self->setup_texinput_paths
#
# setup the TEXINPUT path environment variables
#------------------------------------------------------------------------

sub _setup_texinput_paths {
    my ($context) = @_;
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
    return  \@texinput_paths;
}


sub throw {
    my $self = shift;
    die Template::Exception->new( $THROW => join('', @_) );
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