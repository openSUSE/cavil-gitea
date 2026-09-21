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

post '/requests' => {json => {created => 'soo#importtest/test!1'}};

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/notifications' => {
  json => [
    {id => 13270, subject => {url => 'https://src.opensuse.org/api/v1/repos/importtest/test/issues/1', type => 'Pull'}}
  ]
};

# Mixed-case and multiple CVE ids in one weird body must still yield a single 'CVE' tag
get '/api/v1/repos/importtest/test/pulls/1' => {
  json => {
    requested_reviewers => [{login => 'legaldb'}],
    labels              => [],
    body                => "## Security fix\n\nBackports fix for cve-2024-0001 and `CVE-2025-99999`.\n",
    head                => {sha => 'b352a491da106380cf55019f7ac025077537bca5'},
    state               => 'open'
  }
};

get '/api/v1/repos/importtest/test/issues/1/timeline' => {json => [{type => 'pull_push', user => {login => 'tester'}}]};

patch '/api/v1/notifications/threads/:id' => sub ($c) { $c->render(json => {id => $c->param('id')}) };

my $test = CavilGiteaTest->new(app);

subtest 'PR body mentioning CVE ids gets a CVE tag' => sub {
  my $result = $test->run('--review');
  is $result->{stdout}, '', 'no output';
  like $result->{logs}, qr/\[info\] Review request tracked as package 1/, 'request tracked';

  is $submitted_packages[0]{package}, 'test', 'right package';
  is $submitted_packages[0]{tags},    'CVE',  'single CVE tag despite mixed case and multiple ids';
  is $submitted_packages[1],          undef,  'no more packages';
};

done_testing;
