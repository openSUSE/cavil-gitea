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

# Gitea repository names are case insensitive and get normalized to lower case,
# but the submodule path in the product keeps the real package name
get '/api/v1/repos/products/SLFO/git/trees/slfo-1.3' => sub ($c) {
  $c->render(
    json => {
      tree => [
        {path => '.gitmodules', type => 'blob'},
        {
          path => 'MozillaFirefox',
          type => 'commit',
          sha  => '0e1ded1741457c56d700d4e9eb2efd7c2156c2f28f93e9280d2717ded50fa782'
        },
        {
          path => 'libXfont2',
          type => 'commit',
          sha  => '1e1ded1741457c56d700d4e9eb2efd7c2156c2f28f93e9280d2717ded50fa783'
        },
        {
          path => 'libdbus-c++',
          type => 'commit',
          sha  => '2e1ded1741457c56d700d4e9eb2efd7c2156c2f28f93e9280d2717ded50fa784'
        }
      ]
    }
  );
};

get '/api/v1/repos/products/SLFO/contents/.gitmodules' => sub ($c) {
  $c->render(
    json => {
      content => b64_encode(<<'EOF')
[submodule "MozillaFirefox"]
	path = MozillaFirefox
	url = ../../pool/mozillafirefox
	branch = slfo-main
[submodule "libXfont2"]
	path = libXfont2
	url = ../../pool/libxfont2
	branch = slfo-main
[submodule "some arbitrary config space name"]
	path = libdbus-c++
	url = ../../pool/libdbus-c__
	branch = slfo-main
EOF
    }
  );
};

my $id = 28;
my @posted_packages;
post '/packages' => sub ($c) {
  push @posted_packages, {api => $c->param('api'), package => $c->param('package')};
  $c->render(json => {saved => {id => $id++}});
};

my @patched_products;
patch '/products/*name' => sub ($c) {
  push @patched_products, {name => $c->param('name'), ids => $c->every_param('id')};
  $c->render(json => {updated => 3});
};

my $test = CavilGiteaTest->new(app);

subtest 'Package names differ from repository names' => sub {
  subtest 'Clean run' => sub {
    my $result = $test->run('--sync', curfile->sibling('config')->child('slfo.yml')->to_string);
    is $result->{stdout}, '', 'no output';

    like $result->{logs},   qr/\[info\] Product "SLFO-1\.3" from repo "products\/SLFO#slfo-1\.3"/, 'found product';
    like $result->{logs},   qr/\[info\] - MozillaFirefox from pool\/mozillafirefox#0e1ded.+: 28/,  'first package';
    like $result->{logs},   qr/\[info\] - libXfont2 from pool\/libxfont2#1e1ded.+: 29/,            'second package';
    like $result->{logs},   qr/\[info\] - libdbus-c\+\+ from pool\/libdbus-c__#2e1ded.+: 30/,      'third package';
    unlike $result->{logs}, qr/unknown format/, 'no submodule skipped';
  };

  subtest 'Cavil state' => sub {
    is scalar @posted_packages, 3, 'three packages posted';

    # Package name comes from the submodule path, the checkout URL from the submodule URL
    is $posted_packages[0]{package}, 'MozillaFirefox', 'capitalized package name';
    like $posted_packages[0]{api}, qr{/pool/mozillafirefox\.git$}, 'lower case repository';
    is $posted_packages[1]{package}, 'libXfont2', 'capitalized package name';
    like $posted_packages[1]{api}, qr{/pool/libxfont2\.git$}, 'lower case repository';
    is $posted_packages[2]{package}, 'libdbus-c++', 'package name with special characters';
    like $posted_packages[2]{api}, qr{/pool/libdbus-c__\.git$}, 'escaped repository name';

    is_deeply $patched_products[0], {name => 'SLFO-1.3', ids => [28, 29, 30]}, 'product updated';
  };
};

done_testing;
