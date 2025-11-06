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
use Mojo::Util qw(b64_encode);

app->log->level('error');

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

get '/api/v1/repos/importtest/_ObsPrj/git/trees/main' => sub ($c) {
  $c->render(
    json => {
      tree => [
        {path => '.gitea', type => 'tree', sha => '6f77d12df59cff0e2ca8cc82508b1b66242da7269823a9f6a07f9e9d5883cdb8'},
        {path => '.gitmodules', type => 'blob'},
        {
          path => 'nodejs-common',
          type => 'commit',
          sha  => '0e1ded1741457c56d700d4e9eb2efd7c2156c2f28f93e9280d2717ded50fa782'
        }
      ]
    }
  );
};

my $branch;
get '/api/v1/repos/importtest/_ObsPrj/contents/.gitmodules' => sub ($c) {
  $branch = $c->param('ref');
  $c->render(
    json => {content => b64_encode("[submodule \"nodejs-common\"]\n\turl = ../../importtest/nodejs-common\n\n")});
};

my @posted_packages;
post '/packages' => sub ($c) {
  my $info = {
    api           => $c->param('api'),
    external_link => $c->param('external_link'),
    package       => $c->param('package'),
    priority      => $c->param('priority'),
    rev           => $c->param('rev'),
    type          => $c->param('type')
  };
  push @posted_packages, $info;
  $c->render(json => {saved => {id => 28}});
};

my @patched_products;
patch '/products/:name' => sub ($c) {
  push @patched_products, {name => $c->param('name'), ids => $c->every_param('id')};
  $c->render(json => {updated => 3});
};

my $test = CavilGiteaTest->new(app);

subtest 'Product with new package' => sub {
  subtest 'Clean run' => sub {
    my $result
      = $test->run('--sync', curfile->sibling('config')->child('opensuse.yml')->to_string, '--base-priority', '1');
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Sync mode \(config: .+opensuse\.yml\)/,               'sync mode';
    like $result->{logs}, qr/\[info\] Connecting to Cavil instance.+http:\/\/127\.0\.0\.1/, 'mock Cavil instance';
    like $result->{logs}, qr/\[info\] Connecting to Gitea instance.+http:\/\/127\.0\.0\.1.+soo.+legaldb/,
      'mock Gitea instance';
    like $result->{logs}, qr/\[info\] Product "importtest" from repo "importtest\/_ObsPrj#main"/, 'found product';
    like $result->{logs}, qr/\[info\] - importtest\/nodejs-common#0e1ded.+: 28/,                  'found package';
  };

  subtest 'Cavil state' => sub {
    is scalar @posted_packages, 1, 'one package posted';
    like $posted_packages[0]{api}, qr{^http://127\.0\.0\.1:\d+/importtest/nodejs-common\.git$}, 'git repo';
    is $posted_packages[0]{external_link}, 'importtest',                                              'external link';
    is $posted_packages[0]{package},       'nodejs-common',                                           'package name';
    is $posted_packages[0]{priority},      '1',                                                       'priority';
    is $posted_packages[0]{rev},  '0e1ded1741457c56d700d4e9eb2efd7c2156c2f28f93e9280d2717ded50fa782', 'revision';
    is $posted_packages[0]{type}, 'git',                                                              'type';

    is scalar @patched_products, 1, 'one product patched';
    is_deeply $patched_products[0], {name => 'importtest', ids => [28]}, 'product updated';
  };

  subtest 'Gitea state' => sub {
    is $branch, 'main', 'correct branch';
  };
};

done_testing;
