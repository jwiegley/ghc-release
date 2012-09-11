# This is an RPM spec file that specifies how to package
# haddock for Red Hat Linux and, possibly, similar systems.
# It has been tested on Red Hat Linux 7.2 and SuSE Linux 9.1.
#
# If this file is part of a tarball, you can build RPMs directly from
# the tarball by using the following command:
#
#    rpm -ta haddock-(VERSION).tar.gz
#
# The resulting package will be placed in the RPMS/(arch) subdirectory
# of your RPM build directory (usually /usr/src/redhat or ~/rpm), with
# the name haddock-(VERSION)-(RELEASE).noarch.rpm.  A corresponding
# source RPM package will be in the SRPMS subdirectory.
#
# NOTE TO HADDOCK MAINTAINERS: When you release a new version of
# Haskell mode, update the version definition below to match the
# version label of your release tarball.

%define name    haddock
%define version 2.6.1
%define release 1

Name:           %{name}
Version:        %{version}
Release:        %{release}
License:        BSD-like
Group:          Development/Languages/Haskell
URL:            http://haskell.org/haddock/
Source:         http://haskell.org/haddock/haddock-%{version}.tar.gz
Packager:       Sven Panne <sven.panne@aedion.de>
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Prefix:         %{_prefix}
BuildRequires:  ghc, docbook-dtd, docbook-xsl-stylesheets, libxslt, libxml2, fop, xmltex, dvips
Summary:        A documentation tool for annotated Haskell source code

%description
Haddock is a tool for automatically generating documentation from
annotated Haskell source code. It is primary intended for documenting
libraries, but it should be useful for any kind of Haskell code.

Haddock lets you write documentation annotations next to the
definitions of functions and types in the source code, in a syntax
that is easy on the eye when writing the source code (no heavyweight
mark-up). The documentation generated by Haddock is fully hyperlinked
-- click on a type name in a type signature to go straight to the
definition, and documentation, for that type.

Haddock can generate documentation in multiple formats; currently HTML
is implemented, and there is partial support for generating DocBook.
The generated HTML uses stylesheets, so you need a fairly up-to-date
browser to view it properly (Mozilla, Konqueror, Opera, and IE 6
should all be ok).

%prep
%setup

%build
runhaskell Setup.lhs configure --prefix=%{_prefix} --docdir=%{_datadir}/doc/packages/%{name}
runhaskell Setup.lhs build
cd doc
test -f configure || autoreconf
./configure
make html

%install
runhaskell Setup.lhs copy --destdir=${RPM_BUILD_ROOT}

%clean
rm -rf ${RPM_BUILD_ROOT}

%files
%defattr(-,root,root)
%doc CHANGES
%doc LICENSE
%doc README
%doc TODO
%doc doc/haddock
%doc examples
%doc haskell.vim
%{prefix}/bin/haddock
%{prefix}/share/haddock-%{version}
