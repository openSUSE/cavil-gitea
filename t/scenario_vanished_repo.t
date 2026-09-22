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

get '/api/v1/repos/importtest/test/pulls/1' =>
  {json => {errors => undef, message => "The target couldn't be found."}, status => 404};

my @read_notifications;
patch '/api/v1/notifications/threads/:id' => sub ($c) {
  my $id = $c->param('id');
  push @read_notifications, $c->param('id');
  $c->render(json => {id => $id});
};

my $test = CavilGiteaTest->new(app);

subtest 'New request' => sub {
  subtest 'Clean run' => sub {
    my $result = $test->run('--review', '--base-priority', '5');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Connecting to Cavil instance.+http:\/\/127\.0\.0\.1/, 'mock Cavil instance';
    like $result->{logs}, qr/\[info\] Connecting to Gitea instance.+http:\/\/127\.0\.0\.1.+soo.+legaldb/,
      'mock Gitea instance';
    like $result->{logs}, qr/\[warn\] Notification 13270: pull request importtest\/test\!1 not found, maybe deleted/,
      'notification received';
  };

  subtest 'Gitea state' => sub {
    is $read_notifications[0], 13270, 'notification read';
    is $read_notifications[1], undef, 'no more notifications read';
  };
};

done_testing;
