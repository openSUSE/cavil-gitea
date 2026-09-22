# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use CavilGiteaTest;
use Mojolicious::Lite;

app->log->level('error');

get '/requests' => {json => {requests => []}};

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/notifications' => {
  json => [
    {id => 13270, subject => {url => 'https://src.opensuse.org/api/v1/repos/importtest/test/issues/1', type => 'Pull'}}
  ]
};

get '/api/v1/repos/importtest/test/pulls/1' => sub ($c) {
  $c->render(text => 'Error', status => 500);
};

my $test = CavilGiteaTest->new(app);

subtest 'Error from Gitea' => sub {
  eval { $test->run('--review', '--base-priority', '5'); };
  like $@, qr/500 response from Gitea \(GET \/api\/v1\/repos\/importtest\/test\/pulls\/1\): Internal Server Error/,
    'right error';
};

done_testing;
