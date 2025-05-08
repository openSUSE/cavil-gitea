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

get '/api/v1/repos/importtest/test/pulls/1' => {
  json => {
    requested_reviewers => [{login => 'legaldb'}],
    labels              => [{name  => 'Critical Priority'}, {name => 'unknown_label'}],
    head                => {sha => 'b352a491da106380cf55019f7ac025077537bca5'},
    state               => 'open'
  }
};

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
    like $result->{logs}, qr/\[trace\] Notification 13270: review request for importtest\/test\!1/,
      'notification received';
    like $result->{logs},
      qr/\[info\] Opening legal review for importtest\/test\!1 \(b352a491da106380cf55019f7ac025077537bca5\)/,
      'opening review';
    like $result->{logs}, qr/\[info\] Review request tracked as package 1/, 'request tracked';
  };

  subtest 'Cavil state' => sub {
    is $submitted_packages[0]{package},       'test',                                     'right package';
    is $submitted_packages[0]{type},          'git',                                      'right type';
    is $submitted_packages[0]{external_link}, 'soo#importtest/test!1',                    'right external link';
    is $submitted_packages[0]{rev},           'b352a491da106380cf55019f7ac025077537bca5', 'right rev';
    like $submitted_packages[0]{api}, qr/http.+\/importtest\/test\.git/, 'right api';
    is $submitted_packages[0]{priority}, 9,     'right priority';
    is $submitted_packages[1],           undef, 'no more packages';

    is $submitted_requests[0]{package},       1,                       'right package';
    is $submitted_requests[0]{external_link}, 'soo#importtest/test!1', 'right external link';
    is $submitted_requests[1],                undef,                   'no more requests';
  };

  subtest 'Gitea state' => sub {
    is $read_notifications[0], 13270, 'notification read';
    is $read_notifications[1], undef, 'no more notifications read';
  };
};

done_testing;
