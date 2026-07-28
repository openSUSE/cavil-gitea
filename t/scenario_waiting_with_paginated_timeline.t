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

get '/requests' => {
  json => {
    requests => [
      {
        checkouts     => ['b352a491da106380cf55019f7ac025077537bca5'],
        external_link => 'soo#importtest/test!1',
        packages      => [1]
      }
    ]
  }
};

get '/package/1' => {json => {state => 'new', result => undef, priority => 5, login => 'tester', id => 1}};

my @updated_packages;
patch '/package/1' => sub ($c) {
  push @updated_packages, $c->req->params->to_hash;
  $c->render(json => {updated => {}});
};

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/repos/importtest/test/pulls/1' => {
  json => {
    requested_reviewers => [{login => 'legaldb'}],
    labels              => [],
    head                => {sha => 'b352a491da106380cf55019f7ac025077537bca5'},
    state               => 'open'
  }
};

# Simulate a paginated Gitea timeline: a busy PR with many bots whose
# events bury our previous comment past the first page. The previous
# "Legal review in progress" comment from legaldb is only reachable on
# page 2, so a bot that fetches only page 1 would post a duplicate.
my @timeline_requests;
get '/api/v1/repos/importtest/test/issues/1/timeline' => sub ($c) {
  my $page  = $c->param('page')  // 0;
  my $limit = $c->param('limit') // 0;
  push @timeline_requests, {page => $page, limit => $limit};

  my @events;
  if ($page eq '1') {
    push @events, {type => 'pull_push',      user => {login => 'tester'}};
    push @events, {type => 'review_request', user => {login => 'other-bot'}} for 1 .. ($limit - 1);
  }
  elsif ($page eq '2') {
    push @events, {type => 'comment', user => {login => 'legaldb'}};
  }

  $c->render(json => \@events);
};

my @posted_comments;
post '/api/v1/repos/importtest/test/issues/:id/comments' => sub ($c) {
  my $params = $c->req->json;
  push @posted_comments, {id => $c->param('id'), %$params};
  $c->render(json => {id => 3});
};

get '/api/v1/notifications' => {json => []};

my $test = CavilGiteaTest->new(app);

subtest 'Waiting for review with paginated timeline' => sub {
  subtest 'Clean run' => sub {
    my $result = $test->run('--review');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Found 1 open legal reviews, 1 of them with "soo" external link/,
      'open review in Cavil';
    like $result->{logs}, qr/\[info\] Checking status of package 1 \(importtest\/test!1\)/, 'checking Gitea status';
    unlike $result->{logs}, qr/\[info\] Commenting about package 1 review status/,
      'no duplicate comment posted (previous comment found via pagination)';
  };

  subtest 'Timeline pagination' => sub {
    ok scalar(@timeline_requests) >= 2, 'fetched more than one page';
    is $timeline_requests[0]{page}, '1', 'first request hits page 1';
    is $timeline_requests[1]{page}, '2', 'second request hits page 2';
    ok $timeline_requests[0]{limit} > 0, 'limit parameter supplied';
  };

  subtest 'Gitea state' => sub {
    is $posted_comments[0], undef, 'no new comment posted (bot found its previous comment on page 2)';
  };

  subtest 'Cavil state' => sub {
    is $updated_packages[0]{priority}, 4,     'right priority';
    is $updated_packages[1],           undef, 'no more packages';
  };
};

done_testing;
