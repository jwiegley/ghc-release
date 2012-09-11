#!/usr/bin/perl -w

use strict;

use Cwd;

# Create libraries/*/{ghc.mk,GNUmakefile}
system("/usr/bin/perl", "-w", "boot-pkgs") == 0
    or die "Running boot-pkgs failed: $?";

my $dir;
my $curdir;

$curdir = &cwd();

# Check that we have all boot packages.
open PACKAGES, "< packages";
while (<PACKAGES>) {
    if (/^#/) {
        # Comment; do nothing
    }
    elsif (/^([a-zA-Z0-9\/.-]+) *[^ ]+ *[^ ]+$/) {
        $dir = $1;
        
        # We would like to just check for an _darcs directory here, but in
        # an lndir tree we avoid making _darcs directories, so it doesn't
        # exist. We therefore require that every repo has a LICENSE file
        # instead.
        if (! -f "$dir/LICENSE") {
            print STDERR "Error: $dir/LICENSE doesn't exist.\n";
            die "Maybe you haven't done './darcs-all get'?";
        }
    }
    elsif (/^([a-zA-Z0-9\/.-]+) *[^ ]+ *[^ ]+ *[^ ]+$/) {
        # These are lines which refer to optional repositories, so their
        # absence isn't an error.
    }
    else {
        die "Bad line in packages file: $_";
    }
}
close PACKAGES;

# autoreconf everything that needs it.
foreach $dir (".", glob("libraries/*/")) {
    if (-f "$dir/configure.ac") {
        print "Booting $dir\n";
        chdir $dir;
        system "autoreconf";
        chdir $curdir;
    }
}

# Alas, darcs doesn't handle file permissions, so fix a few of them.
for my $file ("boot", "darcs-all", "push-all", "validate") {
    chmod 0755, $file if -f $file;
}
