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
use Cavil::Gitea;
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

my @removed_requests;
del '/requests' => sub ($c) {
  push @removed_requests, $c->req->params->to_hash;
  $c->render(json => {removed => [1]});
};

get '/package/1' => {json => {state => 'unacceptable', result => 'Wrong package license'}};

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/repos/importtest/test/pulls/1' =>
  {json => {requested_reviewers => [{login => 'legaldb'}], head => {sha => 'b352a491da106380cf55019f7ac025077537bca5'}}
  };

my @posted_results;
post '/api/v1/repos/importtest/test/pulls/:id/reviews' => sub ($c) {
  my $params = $c->req->json;
  push @posted_results, {id => $c->param('id'), %$params};
  $c->render(json => {});
};

get '/api/v1/notifications' => {json => []};

my $test = CavilGiteaTest->new(app);

subtest 'Unacceptable' => sub {
  subtest 'Clean run' => sub {
    my $result = $test->run('--review');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Connecting to Cavil instance.+http:\/\/127\.0\.0\.1/, 'mock Cavil instance';
    like $result->{logs}, qr/\[info\] Connecting to Gitea instance.+http:\/\/127\.0\.0\.1.+soo.+legaldb/,
      'mock Gitea instance';
    like $result->{logs}, qr/\[info\] Found 1 open legal reviews, 1 of them with "soo" external link/,
      'open review in Cavil';
    like $result->{logs}, qr/\[info\] Checking status of package 1 \(importtest\/test!1\)/, 'checking Gitea status';
    like $result->{logs}, qr/\[info\] Package 1 was reviewed as "unacceptable"/,            'was reviewed';
  };

  subtest 'Cavil state' => sub {
    is_deeply $removed_requests[0], {external_link => 'soo#importtest/test!1'}, 'request removed';
    is $removed_requests[1], undef, 'no more requests';
  };

  subtest 'Gitea state' => sub {
    is_deeply $posted_results[0], {id => 1, body => 'Wrong package license', event => 'REQUEST_CHANGES'},
      'result posted';
    is $posted_results[1], undef, 'no more results';
  };
};

done_testing;
