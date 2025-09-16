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
use Mojo::File qw(curfile);

app->log->level('error');

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/repos/importtest/_ObsPrj/contents' => sub ($c) {
  my $url = $c->url_for('/importtest/nodejs-common.git')->to_abs;
  $c->render(
    json => [
      {
        name              => '.gitmodules',
        type              => 'file',
        submodule_git_url => undef,
        sha               => '867ea1977ee2b36745296eda7e1205ef8597f85e2f26a532af4ca89c2e654ff6'
      },
      {
        name              => 'nodejs-common',
        type              => 'file',
        submodule_git_url => undef,
        sha               => '0e1ded1741457c56d700d4e9eb2efd7c2156c2f28f93e9280d2717ded50fa782'
      }
    ]
  );
};

my @removed_products;
del '/products' => sub ($c) {
  push @removed_products, {name => $c->param('name')};
  $c->render(json => {removed => {}});
};

my $test = CavilGiteaTest->new(app);

subtest 'Product without packages' => sub {
  subtest 'Clean run' => sub {
    my $result
      = $test->run('--sync', curfile->sibling('config')->child('opensuse.yml')->to_string, '--base-priority', '1');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Sync mode \(config: .+opensuse\.yml\)/,               'sync mode';
    like $result->{logs}, qr/\[info\] Connecting to Cavil instance.+http:\/\/127\.0\.0\.1/, 'mock Cavil instance';
    like $result->{logs}, qr/\[info\] Connecting to Gitea instance.+http:\/\/127\.0\.0\.1.+soo.+legaldb/,
      'mock Gitea instance';
    like $result->{logs}, qr/\[info\] Product "importtest" from repo "importtest\/_ObsPrj#main"/, 'found product';
    like $result->{logs}, qr/\[info\] No packages found/,                                         'no packages found';
  };

  subtest 'Cavil state' => sub {
    is scalar @removed_products, 1, 'one product removed';
    is_deeply $removed_products[0], {name => 'importtest'}, 'product removed';
  };
};

done_testing;
