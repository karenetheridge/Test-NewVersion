use strict;
use warnings;
package Test::NewVersion;
# ABSTRACT: provides a test interface for checking that you are using a new $VERSION
# KEYWORDS: test distribution release author version unique new
# vim: set ts=8 sw=4 tw=78 et :

our $VERSION = '0.002';

use parent 'Exporter';
our @EXPORT = qw(all_new_version_ok new_version_ok);

use File::Find;
use File::Spec;
use Encode ();
use HTTP::Tiny;
use JSON::MaybeXS;
use version;
use Module::Metadata;
use List::Util 'first';
use CPAN::Meta 2.120920;
use Test::Builder 0.88;
use namespace::clean;

my $no_plan;

sub import
{
    # END block will check for this status
    my @symbols = grep { $_ ne ':no_plan' } @_;
    $no_plan = (@symbols != @_);

    __PACKAGE__->export_to_level(1, @symbols);
}

# for testing this module only!
my $tb;
sub _builder(;$)
{
    if (not @_)
    {
        $tb ||= Test::Builder->new;
        return $tb;
    }

    $tb = shift;
}

END {
    if (not $no_plan
        and not _builder->expected_tests
        # skip this if no tests have been run (e.g. compilation tests of this module!)
        and (_builder->current_test > 0)
    )
    {
        _builder->done_testing;
    }
}


sub all_new_version_ok
{
    # find all files in blib or lib
    my @files;
    my @lib_dirs = grep { -d } qw(blib/lib lib);

    find(
        {
            wanted => sub {
                push @files, File::Spec->no_upwards($File::Find::name)
                    if -r $File::Find::name
                        and $File::Find::name =~ /\.pm$/ or $File::Find::name =~ /\.pod$/;
            },
            no_chdir => 1,
        },
        $lib_dirs[0],
    ) if @lib_dirs;

    # also add .pod, .pm files in the top level directory
    push @files, grep { -f } glob('*.pod'), glob('*.pm');

    new_version_ok($_) foreach sort @files;
}

sub new_version_ok
{
    my $filename = shift;

    my $builder = Test::Builder->new;

    my $module_metadata = Module::Metadata->new_from_file($filename);
    foreach my $pkg ($module_metadata->packages_inside)
    {
        next if $pkg eq 'main';
        my ($bumped, $message) = _version_is_bumped($module_metadata, $pkg);

        local $Test::Builder::Level = $Test::Builder::Level + 1;
        $builder->ok($bumped, $pkg . ' (' . $filename . ') VERSION is ok'
            . ( $message ? (' (' . $message . ')') : '' )
        );
    }
}

# 'provides' field from dist metadata, if needed
my $dist_provides;

# returns bool, detailed message
sub _version_is_bumped
{
    my ($module_metadata, $pkg) = @_;

    my $res = HTTP::Tiny->new->get("http://cpanidx.org/cpanidx/json/mod/$pkg");
    return (0, 'index could not be queried?') if not $res->{success};

    my $data = $res->{content};

    require HTTP::Headers;
    if (my $charset = HTTP::Headers->new(%{ $res->{headers} })->content_type_charset)
    {
        $data = Encode::decode($charset, $data, Encode::FB_CROAK);
    }

    my $payload = decode_json($data);
    return (0, 'invalid payload returned') unless $payload;
    return (1, 'not indexed') if not defined $payload->[0]{mod_vers};
    return (1, 'VERSION is not set in index') if $payload->[0]{mod_vers} eq 'undef';

    my $indexed_version = version->parse($payload->[0]{mod_vers});
    my $current_version = $module_metadata->version($pkg);

    if (not defined $current_version)
    {
        $dist_provides ||= do {
            my $metafile = first { -e $_ } qw(MYMETA.json MYMETA.yml META.json META.yml);
            my $dist_metadata = $metafile ? CPAN::Meta->load_file($metafile) : undef;
            $dist_metadata->provides if $dist_metadata;
        };

        $current_version = $dist_provides->{$pkg}{version};
        return (0, 'VERSION is not set; indexed version is ' . $indexed_version)
            if not $dist_provides or not $current_version;
    }

    return (
        $indexed_version < $current_version,
        'indexed at ' . $indexed_version . '; local version is ' . $current_version,
    );
}

1;
__END__

=pod

=head1 SYNOPSIS

In your distribution's F<xt/release/new_version.t>:

    use Test::NewVersion;
    all_new_version_ok();

=head1 DESCRIPTION

This module provides interfaces that test your distribution is using a new
C<$VERSION>. This is helpful when you are managing your distribution's version
manually, where you might forget to increment the version before release.
It checks the version against the PAUSE index (CPAN), and the test passes only
if the local version is higher than the indexed version, or there is no indexed
version.

=head1 FUNCTIONS

=head2 C<all_new_version_ok()>

Scans all F<.pm> and <.pod> files in F<blib> or F<lib>, calling
C<new_version_ok()> on each.

=head2 C<new_version_ok($filename)>

Tests against the PAUSE index for all C<package> and C<$VERSION> statements
found in the provided file.

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Test-NewVersion>
(or L<bug-Test-NewVersion@rt.cpan.org|mailto:bug-Test-NewVersion@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

=for :list
* L<Dist::Zilla::Plugin::Test::NewVersion>, from which this test module was adapted.

=cut
