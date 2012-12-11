=head1 NAME

Mail::SpamAssassin::Plugin::WebRedirect		version: 20060211

=head1 SYNOPSIS

 loadplugin Mail::SpamAssassin::Plugin::WebRedirect [/path/to/WebRedirect.pm]

 web_redirect_timeout		3

 web_redirect_max_checks	3

 web_redirect_max_size		50000

 web_redirect_host		geocities.com *.geocities.com

 web_redirect_skip_host		example.com *.example.com

 header     WEB_403   eval:WebRedirect_Status(403)
 score      WEB_403   4.0
 describe   WEB_403   Contains a web link that returns 403
 tflags     WEB_403   net

=head1 DESCRIPTION

Fetches web pages linked to in messages and provides their contents in a
pseudo-header that can be used in custom header rules.

An eval function is also provided to test a link's HTTP status code.

Limited decoding of data contained in pages is also attempted.  The decoded
data is provided in an additional pseudo-header that is made available to
custom header rules.

=head1 AUTHOR

Daryl C. W. O'Shea, DOS Technologies <spamassassin@dostech.ca>

=head1 COPYRIGHT

Copyright (c) 2005 Daryl C. W. O'Shea, DOS Technologies. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 WARNING: PRIVACY AND TECHNICAL ISSUES

There are inherent privacy issues involved in automatically querying a link
found in an email.  Doing so can allow the sender to confirm that the email
may have been accepted.

Spammers could use this info to confirm that an address may be valid or that
it may have gotten through to an end user, etc.

Legitimate senders may see the request in their server logs and believe that
an end user actually saw the email or visited the link queried, which may not
be the case.  In some cases, doing a query make trigger some unknown action by
the sender, such as may be the case when links are used to confirm an action
requested on behalf of the recipient.

To prevent such issues the plugin makes an effort to remove obvious query
strings and login tokens, but cannot possibly be aware of rewriting techniques
that could be used by a sender that controls the HTTP server serving the
resource being linked to.  As such you MUST ONLY INCLUDE THE DOMAINS OF FREE
WEB HOST PROVIDERS THAT YOU KNOW DO NOT ALLOW USERS TO CONTROL ANY ADVANCED
FEATURES.

=cut

# Version History
#
# 2006-02-11
#  - Replaced status code specific eval test with generic eval test that allows
#    the status code to be user configured.
#  - Check to make sure anything that looks like a directory is queried with a
#    trailing slash to avoid 301 responses pointing to the intended resource.
#  - Flag the privileged config settings as privileged.
#  - Fix some config option validation regexes.
#
# 2005-12-15
#  - Initial release

package Mail::SpamAssassin::Plugin::WebRedirect;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Logger;
use strict;
use warnings;
use bytes;

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

use constant HAS_LWP_USERAGENT => eval { require LWP::UserAgent; };

# Load Time::HiRes if it's available
BEGIN {
  use constant HAS_TIME_HIRES => eval { require Time::HiRes };
  if (HAS_TIME_HIRES) {
    Time::HiRes->import( qw(usleep ualarm gettimeofday tv_interval) );
  }
}


sub new {
  my $class = shift;
  my $mailsaobject = shift;

  $class = ref($class) || $class;
  my $self = $class->SUPER::new($mailsaobject);
  bless ($self, $class);

  if ($mailsaobject->{local_tests_only} || !HAS_LWP_USERAGENT) {
    $self->{disabled} = 1;
  } else {
    $self->{disabled} = 0;
  }

  $self->register_eval_rule("WebRedirect_Status");

  unless ($self->{disabled}) {
    $self->{ua} = new LWP::UserAgent;
  }

  $self->set_config($mailsaobject->{conf});

  return $self;
}


sub set_config {
  my($self, $conf) = @_;
  my @cmds = ();

=head1 USER PREFERENCES

There are no settings that can be configured by non-privileged users.

=cut

=head1 RULE DEFINITIONS AND PRIVILEGED SETTINGS

Only users running C<spamassassin> from their procmailrc's or forward files,
or sysadmins editing a file in C</etc/mail/spamassassin>, can use these
settings.   C<spamd> users cannot use them in their C<user_prefs> files, for
security and efficiency reasons, unless C<allow_user_rules> is enabled.

=over 4

=item web_redirect_host		geocities.com	(default: none)

A list of hostname patterns to perform HTTP queries against.  Normal shell
wild cards may be used, similar to those used in <C>whilelist_from entries.

Multiple hostname patterns per line are allowed, as are multiple lines.

 Example:
	web_redirect_host	geocities.com	*.geocities.com
	web_redirect_host	geocities.yahoo.com.??

=cut

  push (@cmds, {
    setting => 'web_redirect_host',
    is_priv => 1,
    default => {},
    code => sub {
      my ($self, $key, $value, $line) = @_;
      if ($value =~ /^$/) {
        return $Mail::SpamAssassin::Conf::MISSING_REQUIRED_VALUE;
      }
      if ($value !~ /^[-.*?\w\s]+$/) {
	return $Mail::SpamAssassin::Conf::INVALID_VALUE;
      }
      foreach my $domain (split(/\s+/, $value)) {
	my $pattern = $domain;
	$domain =~ s/\./\\\./g;
	$domain =~ s/\?/\./g;
	$domain =~ s/\*/\.\*/g;
        $self->{web_redirect_host}->{lc $domain} = $pattern;
      }
    }
  });

=item web_redirect_skip_host	example.com	(default: none)

A list of hostname patterns to skip HTTP queries against.  A link will not be
queried against if its hostname pattern is in this list, even if it is listed
in the <C>web_redirect_host list by either of the site configuration or a
user's configuration.

The syntax used is the same as <C>web_redirect_host.

=cut

  push (@cmds, {
    setting => 'web_redirect_skip_host',
    is_priv => 1,
    default => {},
    code => sub {
      my ($self, $key, $value, $line) = @_;
      if ($value =~ /^$/) {
        return $Mail::SpamAssassin::Conf::MISSING_REQUIRED_VALUE;
      }
      if ($value !~ /^[-.*?\w\s]+$/) {
	return $Mail::SpamAssassin::Conf::INVALID_VALUE;
      }
      foreach my $domain (split(/\s+/, $value)) {
	my $pattern = $domain;
	$domain =~ s/\./\\\./g;
	$domain =~ s/\?/\./g;
	$domain =~ s/\*/\.\*/g;
        $self->{web_redirect_skip_host}->{lc $domain} = $pattern;
      }
    }
  });

=item header Web-Redirect =~ /pattern/modifiers

The <C>Web-Redirect pseudo-header contains the contents of the web pages
queried and can be used in custom header rules as defined in SpamAssassin's
<C>Mail::SpamAssassin::Conf documentation.

=cut

=item header Web-Redirect-Encoded =~ /pattern/modifiers

The <C>Web-Redirect-Encoded pseudo-header contains the decoded contents of one
common encoding method spotted in most (as of mid to late 2005) web redirect
pages found on popular free web hosts.

Its use is identical to that of the <C>Web-Redirect pseudo-header.  When
scoring rules based on this pseudo-header keep in mind that somebody went to
the effort of encoding the contents, possibly to obscure it.

=cut

=head1 ADMINISTRATOR SETTINGS

These settings differ from the ones above, in that they are considered 'more
privileged' -- even more than the ones in the B<PRIVILEGED SETTINGS> section.
No matter what C<allow_user_rules> is set to, these can never be set from a
user's C<user_prefs> file when spamc/spamd is being used.  However, all
settings can be used by local programs run directly by the user.

=over 4

=item web_redirect_timeout	n.nn		(default: 3)

The amount of time in seconds to wait for a response to an HTTP GET request.

=cut

  push(@cmds, {
    setting => 'web_redirect_timeout',
    is_admin => 1,
    default => 3,
    type => $Mail::SpamAssassin::Conf::CONF_TYPE_NUMERIC
  });

=item web_redirect_max_checks	n		(default: 3)

The maximum number of links to send HTTP GET requests for.

=cut

  push(@cmds, {
    setting => 'web_redirect_max_checks',
    is_admin => 1,
    default => 3,
    type => $Mail::SpamAssassin::Conf::CONF_TYPE_NUMERIC
  });

=item web_redirect_max_size	n		(default: 50000)

The maximum data size to request in an HTTP GET request.  This is a maximum
per request, so multiply by the value of <C>web_redirect_max_checks to get the
maximum amount that may be requested.

When considering a value for this setting, keep in mind that the data received
in the body of each HTTP response will be added to the <C>Web-Redirect
pseudo-header.  Additionally, any encoded data found and decoded will be added
to the <C>Web-Redirect-Encoded pseudo-header.

=cut

  push(@cmds, {
    setting => 'web_redirect_max_size',
    is_admin => 1,
    default => 50000,
    type => $Mail::SpamAssassin::Conf::CONF_TYPE_NUMERIC
  });

  $conf->{parser}->register_commands(\@cmds);
}


=item eval:WebRedirect_Status_Line('statuscode')

A function provided for use in eval rules to test the HTTP status of the links
queried.  A file glob style 'status' parameter MUST be included.  The 'status'
parameter will be matched against the HTTP status returned by the remote
server.

Examples:

  header   WEB_404   eval:WebRedirect_Status('404')

=cut 

sub WebRedirect_Status {
  my ($self, $pms, $status) = @_;
  return 0 if $self->{disabled};

  my $eval_name = $pms->get_current_eval_rule_name();

  # validate the eval call and complain if it was done wrong
  unless (defined $status && $status =~ /^\d{3}$/) {
    warn ("rules: eval rule: ". $eval_name 
	." requires a 3 digit status code parameter\n");

    dbg ("config: eval rule: ". $eval_name
	." requires a parameter such as: header "
	. $eval_name ." eval:WebRedirect_Status\(404\)");

    $pms->{rule_errors}++; # flag to --lint that there was an error ...
    return 0;
  }

  $self->_log_hit($pms, $status, $eval_name);
  return 0;
}


# this is the best place to hold up processing since it is usually called just
# after DNS checks are sent out
sub parsed_metadata {
  my ($self, $opts) = @_;
  my $pms = $opts->{permsgstatus};
  my $msg = $opts->{msg};

  return if $self->{disabled};

  my %uris = $self->_get_domains($pms);

  # set maximum page size
  $self->{ua}->max_size(($pms->{main}->{conf}->{web_redirect_max_size} | 50000));

  # set timeout per request
  $self->{ua}->timeout(($pms->{main}->{conf}->{web_redirect_timeout} | 15));

  # array of requested pages text
  my @pagetext = ();
  my @ciphertext = ();

  my $count = 0;
  my $max = $pms->{main}->{conf}->{web_redirect_max_checks};
  foreach my $uri (keys %uris) {
    $count++;
    if ($count > $max) {
      dbg("rules: maximum web_redirect checks reached, skipping remaining domains");
      last;
    }
    dbg("rules: checking uri: $uri");

    my $page = $self->_get_page($pms, $uri);

    if (defined $page) {
      # keep each page's plain-text
      push @pagetext, $page;

      # keep each page's cipher-text
      push @ciphertext, $self->_decode_page($page);
    }
  }

  # add all of the pages to the message's metadata
  $pms->{msg}->put_metadata('Web-Redirect', join('---new-page---', @pagetext));
  $pms->{msg}->put_metadata('Web-Redirect-Encoded', join('---new-page---', @ciphertext));

  dbg("rules: WebRedirect page text: start>>".
	$pms->{msg}->get_metadata('Web-Redirect') ."<<end");
  dbg("rules: WebRedirect decoded text: start>>".
	$pms->{msg}->get_metadata('Web-Redirect-Encoded') ."<<end");

  return;
}


sub _get_page {
  my ($self, $pms, $uri) = @_;

  my $request = new HTTP::Request('GET', $uri);

  # measure elapsed time while getting page
  my $t0 = (HAS_TIME_HIRES ? [gettimeofday] : time());
  my $response = $self->{ua}->simple_request($request);
  my $t1 = (HAS_TIME_HIRES ? [gettimeofday] : time());

  # track status codes
  $self->_track_hit($pms, $1, $uri) if ($response->status_line =~ /^(\d{3})/);

  # debug status line
  dbg("rules: request status: " . $response->status_line);

  # check the outcome of the response
  if ($response->is_success) {
    dbg("rules: got response to request in "
	. (HAS_TIME_HIRES ? (tv_interval $t0, $t1) : $t1 - $t0) . " seconds");
    return $response->content;
  }
  return;
}


sub _decode_page {
  my ($self, $plaintext, $iter) = @_;

  # deep-recursion protection
  $iter ||= 0;
  dbg("rules: _decode_page() iteration $iter");
  return $plaintext if ($iter > 3);

  my $decoded = '';

  # unescape this iteration of plaintext
  while ($plaintext =~ /\bunescape\s*\(\"(.*?)\"\)/ig) {
    my $escaped = $1;

    $escaped =~ s/\\x([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    $escaped =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

    $decoded .= $escaped;

    dbg("rules: decoded layer \#". ($iter+1) ." of encoding");
  }

  # recurse
  if ($decoded ne '') {
    $decoded .= ' ' . $self->_decode_page($decoded, ++$iter);
  }

  return $decoded;
}


sub _track_hit {
  my ($self, $pms, $rule, $uri) = @_;

  $pms->{WebRedirect}->{$rule}++;

  if (!defined $pms->{WebRedirect}->{hits}->{$rule}) {
    $pms->{WebRedirect}->{hits}->{$rule} = { };
  };
  $pms->{WebRedirect}->{hits}->{$rule}->{$uri} = 1;
}


sub _log_hit {
  my ($self, $pms, $rule, $rulename) = @_;

  if ($pms->{WebRedirect}->{hits}->{$rule}) {
    my $uris = join (' ', keys %{$pms->{WebRedirect}->{hits}->{$rule}});
    $pms->test_log ("URIs: $uris");
    $pms->got_hit ($rulename, "");
  }
}


sub _get_domains {
  my ($self, $pms) = @_;

  my %wanted_uris = ();

  # don't keep dereferencing
  my $domains      = $pms->{main}->{conf}->{web_redirect_host};
  my $skip_domains = $pms->{main}->{conf}->{web_redirect_skip_host};

  # get the full list of parsed domains
  my $uris = $pms->get_uri_detail_list();

  # go from uri => info to uri_ordered
  # 0: a
  # 1: form
  # 2: img
  # 3: !a_empty
  # 4: parsed
  # 5: a_empty
  while (my($uri, $info) = each %{$uris}) {
    # skip if uri doesn't have a type since it'll be in the list again with one
    # or isn't a type we want
    next unless $uri =~ /^http:\/\//i;

    # no domains were found via this uri, so skip
    next unless ($info->{domains});

    my $entry = 3;

    if ($info->{types}->{a}) {
      $entry = 5;

      # determine a vs a_empty
      foreach my $at (@{$info->{anchor_text}}) {
        if (length $at) {
          $entry = 0;
          last;
        }
      }
    }
    elsif ($info->{types}->{parsed} && (keys %{$info->{types}} == 1)) {
      $entry = 4;
    }

    # only use links to web pages, not images, etc.
    if ($entry == 0 || $entry == 4) {

      # check to see if it's a domain we want to check, first get hostname
      # making sure we omit any username@
      my $uri_host;
      $uri =~ /^.{3,4}:\/\/(?:[^\/]*\@)?(.+?)(?:\/|:|$)/;
      if (defined $1) {
	$uri_host = lc($1);
      } else {
        dbg("rules: couldn't determine hostname, skipping uri: $uri");
	next;
      }

      my $check_it = 0;
      # check to see if it's in the list of domains to check
      while (my ($regexp, $simple) = each (%{$domains})) {
	if ($uri_host =~ /^$regexp$/) {	# both already lc
	  dbg("rules: hostname: $uri_host matches check pattern: $simple");
	  $check_it = 1;
#	  last;
        }
      }
      next unless $check_it;

      # check to see if it's in the list of domains to skip
      while (my ($regexp, $simple) = each (%{$skip_domains})) {
	if ($uri_host =~ /^$regexp$/) {	# both already lc
	  dbg("rules: hostname: $uri_host matches skip pattern: $simple");
	  $check_it = 0;
#	  last;
	}
      }
      next unless $check_it;

      # lowercase the domain part
      # (to avoid duplicate lookups of the same differently cased domain)
      if ($uri =~ /^(.{8,}?)(\/.*)$/) {
	$uri = lc($1) . $2;
      } else {
	$uri = lc($uri) . "/";
      }

      # chop off any VISIBLE(!) query string to avoid user id keying
      # this isn't sure fire though... a little ModRewrite voodoo and you're
      # screwed
      $uri =~ s/\?.+$//;

      # add a trailing slash to avoid 301 MOVED when querying a directory
      if ($uri !~ /(?:\/|\.[^\/]{2,4})$/) {
	$uri .= "/";
	dbg("rules: added trailing slash to: $uri");
      }

      $wanted_uris{$uri} = 1;
    }
  }

  return %wanted_uris;
}


1;
