# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use CavilGiteaTest;
use Mojolicious::Lite;
use Mojo::File qw(curfile);

app->log->level('error');

get '/api/v1/user' => {json => {id => 1, login => 'legaldb'}};

my $test = CavilGiteaTest->new(app);

subtest 'Empty product config' => sub {
  subtest 'Clean run' => sub {
    my $result = $test->run('--sync', curfile->sibling('config')->child('empty.yml')->to_string);
    is $result->{stdout}, '', 'no output';

    like $result->{logs}, qr/\[info\] Sync mode \(config: .+empty\.yml\)/,                  'sync mode';
    like $result->{logs}, qr/\[info\] Connecting to Cavil instance.+http:\/\/127\.0\.0\.1/, 'mock Cavil instance';
    like $result->{logs}, qr/\[info\] Connecting to Gitea instance.+http:\/\/127\.0\.0\.1.+soo.+legaldb/,
      'mock Gitea instance';
    unlike $result->{logs}, qr/Product/, 'no products';
  };
};

done_testing;
