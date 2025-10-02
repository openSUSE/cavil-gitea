# Copyright (C) 2025 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::Gitea::GiteaClient;
use Mojo::Base -base, -signatures;

use Carp               qw(croak);
use Cavil::Gitea::Util qw(build_markdown_comment parse_git_url);
use Mojo::URL;
use Mojo::UserAgent;

has 'log';
has token       => sub { die 'Gitea token is required' };
has ua          => sub { Mojo::UserAgent->new->inactivity_timeout(3600) };
has url         => sub { die 'Gitea URL is required' };
has workarounds => 0;

sub get_pull_request ($self, $owner, $repo, $number) {
  my $issue = $self->_request('GET', "/api/v1/repos/$owner/$repo/pulls/$number")->json;
  return $issue;
}

sub get_notifications ($self) {
  my $notifications = $self->_request('GET', '/api/v1/notifications')->json;
  my @notifications;
  return $notifications;
}

sub get_packages_for_project ($self, $owner, $repo, $branch) {
  return $self->_scrape_packages_for_project($owner, $repo, $branch) if $self->workarounds;

  my $log  = $self->log;
  my $list = $self->_request('GET', "/api/v1/repos/$owner/$repo/contents", {form => {ref => $branch}})->json;

  my @packages;
  my $host = $self->_host;
  for my $item (@$list) {
    next unless $item->{type} eq 'submodule';

    my $url = $item->{submodule_git_url};
    if (my $info = parse_git_url($url, $host)) {
      push @packages, {owner => $info->{owner}, repo => $info->{repo}, checkout => $info->{checkout} || $item->{sha}};
    }
    else { $log->warn("Ignoring submodule in unknown format: $url") }
  }

  return \@packages;
}

sub get_review_requests ($self) {
  my $log           = $self->log;
  my $notifications = $self->get_notifications;

  my @open;
  for my $notification (@$notifications) {
    my $id   = $notification->{id};
    my $url  = $notification->{subject}{url};
    my $type = $notification->{subject}{type};

    if ($type eq 'Pull' && $url =~ /\/api\/v1\/repos\/([^\/]+)\/([^\/]+)\/issues\/(\d+)/) {
      my ($owner, $repo, $number) = ($1, $2, $3);
      my $info = $self->pr_info($owner, $repo, $number);
      if ($info->{review_requested}) {
        if ($info->{reviewed}) {
          $log->trace("Notification $id: review request for $owner/$repo!$number, but we already reviewed");
          $self->mark_notification_read($id);
        }
        else {
          $log->trace("Notification $id: review request for $owner/$repo!$number");
          my $open = {
            notification => $id,
            owner        => $owner,
            repo         => $repo,
            request      => $number,
            checkout     => $info->{checkout},
            labels       => $info->{labels}
          };
          push @open, $open;
        }
      }
      else {
        $log->trace("Notification $id: review request not for us");
        $self->mark_notification_read($id);
      }
    }
    else {
      $log->trace("Notification $id: not a review request");
      $self->mark_notification_read($id);
    }

  }

  return \@open;
}

sub get_timeline ($self, $owner, $repo, $number) {
  my $timeline = $self->_request('GET', "/api/v1/repos/$owner/$repo/issues/$number/timeline")->json;
  return $timeline;
}

sub get_timeline_info ($self, $owner, $repo, $number) {
  my $user     = $self->whoami;
  my $timeline = $self->get_timeline($owner, $repo, $number);

  my $info = {commented_since_push => 0, reviewed_since_push => 0};
  for my $event (reverse @$timeline) {
    my $type = $event->{type};
    last if $type eq 'pull_push';
    next unless $user->{login} eq $event->{user}{login};
    if    ($type eq 'review')  { $info->{reviewed_since_push}  = 1 }
    elsif ($type eq 'comment') { $info->{commented_since_push} = 1 }
  }

  return $info;
}

sub mark_notification_read ($self, $id) {
  $self->_request('PATCH', "/api/v1/notifications/threads/$id");
}

sub post_report ($self, $owner, $repo, $review, $report) {
  my $form = {attachment => {content => $report->{text}, filename => 'report.md', 'Content-Type' => 'text/markdown'}};
  my $res  = $self->_request(
    'POST',
    "/api/v1/repos/$owner/$repo/issues/comments/$review->{comment}/assets?name=report.md",
    {form => $form, ignore_errors => 1}
  );
  return $res->is_success;
}

sub post_comment ($self, $owner, $repo, $number, $result) {
  my $comment = build_markdown_comment($result);
  my $data
    = $self->_request('POST', "/api/v1/repos/$owner/$repo/issues/$number/comments", {json => {body => $comment}})->json;
  return {comment => $data->{id}};
}

sub post_review ($self, $owner, $repo, $number, $result) {
  my $comment = $self->post_comment($owner, $repo, $number, $result);

  my $json = {event => 'COMMENT'};
  if (($result->{state} eq 'acceptable') || ($result->{state} eq 'acceptable_by_lawyer')) {
    $json->{event} = 'APPROVED';
  }
  elsif ($result->{state} eq 'unacceptable') {
    $json->{event} = 'REQUEST_CHANGES';
  }
  $self->_request('POST', "/api/v1/repos/$owner/$repo/pulls/$number/reviews", {json => $json});

  return $comment;
}

sub pr_info ($self, $owner, $repo, $number) {
  my $user             = $self->whoami;
  my $issue            = $self->get_pull_request($owner, $repo, $number);
  my $reviewers        = $issue->{requested_reviewers} // [];
  my $review_requested = !!grep { ($_->{login} // '') eq $user->{login} } @$reviewers;
  my $labels           = [map { $_->{name} } @{$issue->{labels}}];

  my $timeline_info = $self->get_timeline_info($owner, $repo, $number);

  return {
    checkout         => $issue->{head}{sha},
    commented        => $timeline_info->{commented_since_push},
    review_requested => $review_requested,
    reviewed         => $timeline_info->{reviewed_since_push},
    labels           => $labels,
    state            => $issue->{state}
  };
}

sub whoami ($self) {
  my $user = $self->_request('GET', '/api/v1/user')->json;
  return {id => $user->{id}, login => $user->{login}};
}

sub _headers ($self) {
  return {Authorization => 'token ' . $self->token};
}

sub _host ($self) { Mojo::URL->new($self->url)->host_port }

sub _request($self, $method, $path, $options = {}) {
  my $form = $options->{form};
  my $json = $options->{json};

  my $ua = $self->ua;
  my $tx = $ua->build_tx(
    $method => $self->_url($path) => $self->_headers,
    $form ? (form => $form) : ($json ? (json => $json) : ())
  );
  $tx = $ua->start($tx);

  return $tx->result if $options->{ignore_errors} || !(my $err = $tx->error);
  croak "$err->{code} response from Gitea ($method $path): $err->{message}" if $err->{code};
  croak "Connection error from Gitea: $err->{message}";
}

sub _scrape_packages_for_project ($self, $owner, $repo, $branch) {
  my $log = $self->log;
  my $dom = $self->_request('GET', "/$owner/$repo/src/branch/$branch/")->dom;

  my $links = $dom->find('div#repo-files-table div.repo-file-item div.repo-file-cell a.text.primary[href]');
  my $base  = Mojo::URL->new($self->url);
  my $host  = $base->host_port;

  my @packages;
  for my $link ($links->each) {
    my $url = Mojo::URL->new($link->{href})->base($base)->to_abs->to_string;
    if (my $info = parse_git_url($url, $host)) {
      push @packages, {owner => $info->{owner}, repo => $info->{repo}, checkout => $info->{checkout}};
    }
    else { $log->warn("Ignoring submodule link in unknown format: $url") }
  }

  return \@packages;
}

sub _url ($self, $path) { Mojo::URL->new($self->url . $path) }

1;
