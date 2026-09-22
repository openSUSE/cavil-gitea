# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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

get '/package/1' => {json => {state => 'new', result => undef, priority => 4, login => 'tester', id => 1}};

my @updated_packages;
patch '/package/1' => sub ($c) {
  push @updated_packages, $c->req->params->to_hash;
  $c->render(json => {updated => {}});
};

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/repos/importtest/test/pulls/1' => {
  json => {
    requested_reviewers => [{login => 'legaldb'}],
    labels              => [{name  => 'legaldb/High Priority'}],
    head                => {sha => 'b352a491da106380cf55019f7ac025077537bca5'},
    state               => 'open'
  }
};

get '/api/v1/repos/importtest/test/issues/1/timeline' => {json => [{type => 'pull_push', user => {login => 'tester'}}]};

my @posted_comments;
post '/api/v1/repos/importtest/test/issues/:id/comments' => sub ($c) {
  my $params = $c->req->json;
  push @posted_comments, {id => $c->param('id'), %$params};
  $c->render(json => {id => 3});
};

get '/api/v1/notifications' => {json => []};

my $test = CavilGiteaTest->new(app);

subtest 'Updating priority' => sub {
  subtest 'Clean run' => sub {
    my $result = $test->run('--review');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Connecting to Cavil instance.+http:\/\/127\.0\.0\.1/, 'mock Cavil instance';
    like $result->{logs}, qr/\[info\] Connecting to Gitea instance.+http:\/\/127\.0\.0\.1.+soo.+legaldb/,
      'mock Gitea instance';
    like $result->{logs}, qr/\[info\] Found 1 open legal reviews, 1 of them with "soo" external link/,
      'open review in Cavil';
    like $result->{logs}, qr/\[info\] Checking status of package 1 \(importtest\/test!1\)/, 'checking Gitea status';
    like $result->{logs}, qr/\[info\] Updating review priority for package 1 from 4 to 6/,  'updating priority';
  };

  subtest 'Cavil state' => sub {
    is $updated_packages[0]{priority}, 6,     'right priority';
    is $updated_packages[1],           undef, 'no more packages';
  };

  subtest 'Gitea state' => sub {
    my $url = $test->cavil_gitea->cavil->url;
    is_deeply $posted_comments[0], {id => 1, body => "Legal review [in progress]($url/reviews/details/1)."},
      'comment posted';
    is $posted_comments[1], undef, 'no more comments';
  };
};

done_testing;
