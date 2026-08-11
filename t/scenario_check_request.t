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

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use CavilGiteaTest;
use Mojolicious::Lite;

app->log->level('error');

# --check is a manual trigger alternative to a notification, so it runs the same
# pipeline as --review: first the lifecycle check for already tracked reviews,
# then the (here manually triggered) review request handling. The set of tracked
# reviews is mutable so we can exercise both an untracked and a tracked pull
# request in the same app.
my $open_requests = [];
get '/requests' => sub ($c) { $c->render(json => {requests => $open_requests}) };

my @removed_requests;
del '/requests' => sub ($c) {
  push @removed_requests, $c->req->params->to_hash;
  $c->render(json => {removed => [1]});
};

my @submitted_packages;
post '/packages' => sub ($c) {
  push @submitted_packages, $c->req->params->to_hash;
  $c->render(json => {saved => {id => 1}});
};

my @submitted_requests;
post '/requests' => sub ($c) {
  push @submitted_requests, $c->req->params->to_hash;
  $c->render(json => {created => 'soo#importtest/test!1'});
};

# Cavil's view of the package (state is mutable across subtests)
my $package_state = 'new';
get '/package/1' => sub ($c) {
  $c->render(json => {state => $package_state, result => 'Test accept', priority => 9, login => 'tester', id => 1});
};

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/repos/importtest/test/pulls/1' => {
  json => {
    requested_reviewers => [{login => 'legaldb'}],
    labels              => [{name  => 'Critical Priority'}],
    head                => {sha => 'b352a491da106380cf55019f7ac025077537bca5'},
    state               => 'open'
  }
};

# Timeline is mutable so we can simulate a review that has already been posted
my $timeline = [{type => 'pull_push', user => {login => 'tester'}}];
get '/api/v1/repos/importtest/test/issues/1/timeline' => sub ($c) { $c->render(json => $timeline) };

my @posted_reviews;
post '/api/v1/repos/importtest/test/pulls/:id/reviews' => sub ($c) {
  push @posted_reviews, {id => $c->param('id'), %{$c->req->json}};
  $c->render(json => {});
};

my @read_notifications;
patch '/api/v1/notifications/threads/:id' => sub ($c) {
  push @read_notifications, $c->param('id');
  $c->render(json => {});
};

my $test = CavilGiteaTest->new(app);

subtest 'Trigger a review for an untracked pull request' => sub {
  $open_requests = [];

  subtest 'Clean run' => sub {
    my $result = $test->run('--check', 'importtest/test!1', '--base-priority', '5');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Check mode \(pull request: importtest\/test\!1\)/, 'check mode';
    like $result->{logs}, qr/\[info\] Found 0 open legal reviews/,                       'lifecycle check runs first';
    like $result->{logs}, qr/\[trace\] Check importtest\/test\!1: review request for importtest\/test\!1/,
      'review request triggered for the pull request';
    like $result->{logs},
      qr/\[info\] Opening legal review for importtest\/test\!1 \(b352a491da106380cf55019f7ac025077537bca5\)/,
      'opening review';
    like $result->{logs}, qr/\[info\] Review request tracked as package 1/, 'request tracked';
  };

  subtest 'Cavil state' => sub {
    is $submitted_packages[0]{package},  'test',                                     'right package';
    is $submitted_packages[0]{rev},      'b352a491da106380cf55019f7ac025077537bca5', 'right rev';
    is $submitted_packages[0]{priority}, 9,                                          'right priority';
    is $submitted_packages[1],           undef,                                      'no more packages';

    is $submitted_requests[0]{external_link}, 'soo#importtest/test!1', 'right external link';
    is $submitted_requests[1],                undef,                   'no more requests';
  };

  subtest 'Gitea state' => sub {
    is $read_notifications[0], undef, 'no notification marked read (there was none)';
  };
};

subtest 'Trigger picks up a tracked review later in its lifecycle' => sub {
  $open_requests = [
    {
      checkouts     => ['b352a491da106380cf55019f7ac025077537bca5'],
      external_link => 'soo#importtest/test!1',
      packages      => [1]
    }
  ];
  $package_state = 'acceptable';
  $timeline = [{type => 'pull_push', user => {login => 'tester'}}, {type => 'review', user => {login => 'legaldb'}}];

  my $result = $test->run('--check', 'importtest/test!1');
  is $result->{stdout}, '', 'no output';

  # The already tracked review is advanced by the normal lifecycle check
  like $result->{logs}, qr/\[info\] Checking status of package 1 \(importtest\/test!1\)/, 'lifecycle check runs';
  like $result->{logs}, qr/\[info\] Package 1 was reviewed as "acceptable"/,              'review result seen';
  like $result->{logs}, qr/\[info\] Review was already posted, skipping/,                 'not posted twice';
  is_deeply $removed_requests[0], {external_link => 'soo#importtest/test!1'}, 'completed request removed';

  # The manual trigger goes through the same checks and does not force a re-open
  like $result->{logs},
    qr/\[trace\] Check importtest\/test\!1: review request for importtest\/test\!1, but we already reviewed/,
    'trigger respects the already reviewed state';
  is $posted_reviews[0], undef, 'no review posted to Gitea';
};

subtest 'Invalid pull request specification' => sub {
  my $result = $test->run('--check', 'not-a-pull-request');
  like $result->{logs}, qr/\[error\] Invalid pull request "not-a-pull-request", expected "owner\/repo!number"/,
    'helpful error';
};

done_testing;
