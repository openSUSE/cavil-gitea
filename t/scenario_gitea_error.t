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
