Summary:	The WebRedirect plugin for SpamAssassin
Name:		perl-Mail-SpamAssassin-Plugin-WebRedirect
Version:	0
Release:	7
License:	Apache License
Group:		Development/Perl
URL:		https://people.apache.org/~dos/sa-plugins/3.1/
Source0:	http://people.apache.org/~dos/sa-plugins/3.1/WebRedirect.cf
Source1:	http://people.apache.org/~dos/sa-plugins/3.1/WebRedirect.pm
Requires(pre): rpm-helper
Requires(postun): rpm-helper
Requires(pre):  spamassassin-spamd >= 3.1.1
Requires:	spamassassin-spamd >= 3.1.1
BuildRequires:	perl-doc
BuildArch:	noarch
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-buildroot

%description
Fetches web pages linked to in messages and provides their contents in a
pseudo-header that can be used in custom header rules.

An eval function is also provided to test a link's HTTP status code.

Limited decoding of data contained in pages is also attempted.  The decoded
data is provided in an additional pseudo-header that is made available to
custom header rules.

%prep

%setup -q -T -c -n %{name}-%{version}

cp %{SOURCE0} WebRedirect.cf
cp %{SOURCE1} WebRedirect.pm

# fix path
perl -pi -e "s|/etc/mail/spamassassin/WebRedirect\.pm|%{perl_vendorlib}/Mail/SpamAssassin/Plugin/WebRedirect\.pm|g" WebRedirect.cf

%build

perldoc WebRedirect.pm > Mail::SpamAssassin::Plugin::WebRedirect.3pm

%install
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

install -d %{buildroot}%{_sysconfdir}/mail/spamassassin/
install -d %{buildroot}%{perl_vendorlib}/Mail/SpamAssassin/Plugin
install -d %{buildroot}%{_mandir}/man3

install -m0644 WebRedirect.cf %{buildroot}%{_sysconfdir}/mail/spamassassin/
install -m0644 WebRedirect.pm %{buildroot}%{perl_vendorlib}/Mail/SpamAssassin/Plugin/
install -m0644 Mail::SpamAssassin::Plugin::WebRedirect.3pm %{buildroot}%{_mandir}/man3/

%post
if [ -f %{_var}/lock/subsys/spamd ]; then
    %{_initrddir}/spamd restart 1>&2;
fi
    
%postun
if [ "$1" = "0" ]; then
    if [ -f %{_var}/lock/subsys/spamd ]; then
        %{_initrddir}/spamd restart 1>&2
    fi
fi

%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

%files
%defattr(644,root,root,755)
%attr(0644,root,root) %config(noreplace) %{_sysconfdir}/mail/spamassassin/WebRedirect.cf
%{perl_vendorlib}/Mail/SpamAssassin/Plugin/WebRedirect.pm
%{_mandir}/man3/Mail::SpamAssassin::Plugin::WebRedirect.3pm*


%changelog
* Fri Sep 04 2009 Thierry Vignaud <tvignaud@mandriva.com> 0-5mdv2010.0
+ Revision: 430496
- rebuild

* Sun Jul 20 2008 Oden Eriksson <oeriksson@mandriva.com> 0-4mdv2009.0
+ Revision: 239111
- rebuild

  + Olivier Blin <oblin@mandriva.com>
    - restore BuildRoot

  + Thierry Vignaud <tvignaud@mandriva.com>
    - kill re-definition of %%buildroot on Pixel's request

* Sun Jul 01 2007 Oden Eriksson <oeriksson@mandriva.com> 0-3mdv2008.0
+ Revision: 46366
- misc fixes


* Sat Nov 25 2006 Emmanuel Andry <eandry@mandriva.org> 0-2mdv2007.0
+ Revision: 87293
- patch to fix perl module path
- Import perl-Mail-SpamAssassin-Plugin-WebRedirect

