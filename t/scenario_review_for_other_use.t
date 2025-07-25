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

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/notifications' => {
  json => [
    {id => 13270, subject => {url => 'https://src.opensuse.org/api/v1/repos/importtest/test/issues/1', type => 'Pull'}}
  ]
};

get '/api/v1/repos/importtest/test/pulls/1' => {
  json => {
    requested_reviewers => [{login => 'kraih'}],
    labels              => [],
    head                => {sha => 'b352a491da106380cf55019f7ac025077537bca5'},
    state               => 'open'
  }
};

get '/api/v1/repos/importtest/test/issues/1/timeline' => {json => [{type => 'pull_push', user => {login => 'tester'}}]};

my @read_notifications;
patch '/api/v1/notifications/threads/:id' => sub ($c) {
  my $id = $c->param('id');
  push @read_notifications, $c->param('id');
  $c->render(json => {id => $id});
};

my $test = CavilGiteaTest->new(app);

subtest 'New request for another user' => sub {
  subtest 'Clean run' => sub {
    my $result = $test->run('--review');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Connecting to Cavil instance.+http:\/\/127\.0\.0\.1/, 'mock Cavil instance';
    like $result->{logs}, qr/\[info\] Connecting to Gitea instance.+http:\/\/127\.0\.0\.1.+soo.+legaldb/,
      'mock Gitea instance';
    like $result->{logs}, qr/\[trace\] Notification 13270: review request not for us/, 'notification received';
  };

  subtest 'Gitea state' => sub {
    is $read_notifications[0], 13270, 'notification read';
    is $read_notifications[1], undef, 'no more notifications read';
  };
};

done_testing;
