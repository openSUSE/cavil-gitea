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

get '/requests' => {json => {requests => []}};

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

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/notifications' => {
  json => [
    {id => 13270, subject => {url => 'https://src.opensuse.org/api/v1/repos/importtest/test/issues/1', type => 'Pull'}}
  ]
};

# The pull request head is a brand new commit that has *not* been reviewed yet.
get '/api/v1/repos/importtest/test/pulls/1' => {
  json => {
    requested_reviewers => [{login => 'legaldb'}],
    labels              => [],
    head                => {sha => '0ca9946090315955e5a7c2533748269d551eaeb56ec3efb93caa9f094a9cec31'},
    state               => 'open'
  }
};

# Regression test for a missing review caused by Gitea timeline pagination.
#
# Gitea filters some event types out of each timeline page *after* applying the
# limit, so a page can contain fewer than "limit" events while more (newer)
# pages still exist. Here page 1 is short and ends with our review of an *older*
# push, while the newest push (the one we still need to review) only shows up on
# page 2. A bot that treated the short page 1 as the last page would conclude it
# had "already reviewed" and silently drop the review request.
my @timeline_requests;
get '/api/v1/repos/importtest/test/issues/1/timeline' => sub ($c) {
  my $page  = $c->param('page')  // 0;
  my $limit = $c->param('limit') // 0;
  push @timeline_requests, {page => $page, limit => $limit};

  my @events;
  if ($page eq '1') {
    push @events, {type => 'pull_push', user => {login => 'tester'}};
    push @events, {type => 'review',    user => {login => 'legaldb'}};
  }
  elsif ($page eq '2') {
    push @events, {type => 'pull_push', user => {login => 'tester'}};
  }

  $c->render(json => \@events);
};

my @read_notifications;
patch '/api/v1/notifications/threads/:id' => sub ($c) {
  my $id = $c->param('id');
  push @read_notifications, $c->param('id');
  $c->render(json => {id => $id});
};

my $test = CavilGiteaTest->new(app);

subtest 'New request hidden behind a short timeline page' => sub {
  subtest 'Clean run' => sub {
    my $result = $test->run('--review', '--base-priority', '5');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[trace\] Notification 13270: review request for importtest\/test\!1/,
      'notification received';
    unlike $result->{logs}, qr/but we already reviewed/, 'not mistaken for an already reviewed pull request';
    like $result->{logs},
      qr/\[info\] Opening legal review for importtest\/test\!1 \(0ca9946090315955e5a7c2533748269d551eaeb56ec3efb93caa9f094a9cec31\)/,
      'opening review for the new commit';
    like $result->{logs}, qr/\[info\] Review request tracked as package 1/, 'request tracked';
  };

  subtest 'Timeline pagination' => sub {
    ok scalar(@timeline_requests) >= 2, 'fetched more than one page';
    is $timeline_requests[0]{page}, '1', 'first request hits page 1';
    is $timeline_requests[1]{page}, '2', 'second request hits page 2 despite page 1 being short';
    ok $timeline_requests[0]{limit} > 0, 'limit parameter supplied';
  };

  subtest 'Cavil state' => sub {
    is $submitted_packages[0]{package}, 'test', 'new review submitted for the pull request';
    is $submitted_packages[0]{rev},     '0ca9946090315955e5a7c2533748269d551eaeb56ec3efb93caa9f094a9cec31', 'right rev';
    is $submitted_packages[1],          undef, 'no more packages';

    is $submitted_requests[0]{external_link}, 'soo#importtest/test!1', 'right external link';
    is $submitted_requests[1],                undef,                   'no more requests';
  };

  subtest 'Gitea state' => sub {
    is $read_notifications[0], 13270, 'notification read after review was opened';
    is $read_notifications[1], undef, 'no more notifications read';
  };
};

done_testing;
