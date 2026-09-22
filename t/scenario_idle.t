# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use CavilGiteaTest;
use Mojolicious::Lite;

app->log->level('error');

get '/requests' => {json => {requests => []}};

get '/api/v1/user' => {json => {id => 1, login => 'gitea-tester'}};

get '/api/v1/notifications' => {json => []};

my $test = CavilGiteaTest->new(app);

subtest 'Clean run' => sub {
  subtest 'Usage' => sub {
    my $result = $test->run;
    like $result->{stdout}, qr/Usage: cavil-gitea \[OPTIONS\]/, 'usage message';
  };

  subtest 'Nothing to do' => sub {
    my $result = $test->run('--review');
    is $result->{stdout}, '', 'no output';
    like $result->{logs}, qr/\[info\] Connecting to Cavil instance.+http:\/\/127\.0\.0\.1/, 'mock Cavil instance';
    like $result->{logs}, qr/\[info\] Connecting to Gitea instance.+http:\/\/127\.0\.0\.1.+soo.+gitea-tester/,
      'mock Gitea instance';
    like $result->{logs}, qr/\[info\] Found 0 open legal reviews, 0 of them with "soo" external link/,
      'no open requests';
  };
};

done_testing;
