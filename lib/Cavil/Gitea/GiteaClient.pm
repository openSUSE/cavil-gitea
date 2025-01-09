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

use Mojo::URL;
use Mojo::UserAgent;

has 'log';
has token => sub { die 'Gitea token is required' };
has ua    => sub { Mojo::UserAgent->new };
has url   => sub { die 'Gitea URL is required' };

sub get_pull_request ($self, $owner, $repo, $number) {
  my $issue = $self->_request('GET', "/repos/$owner/$repo/pulls/$number");
  return $issue;
}

sub get_notifications ($self) {
  my $notifications = $self->_request('GET', '/notifications');
  return $notifications;
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
        $log->trace("Notification $id: review request for $owner/$repo!$number");
        push @open,
          {notification => $id, owner => $owner, repo => $repo, request => $number, checkout => $info->{checkout}};
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

sub mark_notification_read ($self, $id) {
  $self->_request('PATCH', "/notifications/threads/$id");
}

sub post_review ($self, $owner, $repo, $number, $result) {
  my $json = {body => 'Unknown error during legal review', event => 'COMMENT'};

  if (($result->{state} eq 'acceptable') || ($result->{state} eq 'acceptable_by_lawyer')) {
    $json->{body}  = $result->{result} || 'Reviewed ok';
    $json->{event} = 'APPROVED';
  }
  elsif ($result->{state} eq 'unacceptable') {
    $json->{body}  = $result->{result} || 'Reviewed not ok';
    $json->{event} = 'REQUEST_CHANGES';
  }

  $self->_request('POST', "/repos/$owner/$repo/pulls/$number/reviews", $json);
}

sub pr_info ($self, $owner, $repo, $number) {
  my $user             = $self->whoami;
  my $issue            = $self->get_pull_request($owner, $repo, $number);
  my $reviewers        = $issue->{requested_reviewers} // [];
  my $review_requested = !!grep { $_->{login} eq $user->{login} } @$reviewers;
  return {checkout => $issue->{head}{sha}, review_requested => $review_requested};

}

sub whoami ($self) {
  my $user = $self->_request('GET', '/user');
  return {id => $user->{id}, login => $user->{login}};
}

sub _headers ($self) {
  return {Authorization => 'token ' . $self->token};
}

sub _request($self, $method, $path, $json = undef) {
  my $ua = $self->ua;
  my $tx = $ua->build_tx($method => $self->_url($path) => $self->_headers, $json ? (json => $json) : ());
  $tx = $ua->start($tx);
  return $tx->result->json;
}

sub _url ($self, $path) {
  return Mojo::URL->new($self->url . "/api/v1$path");
}

1;