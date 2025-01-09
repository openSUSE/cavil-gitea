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

use Mojo::Base -strict;

use Test::More;
use Cavil::Gitea::Util qw(build_external_link build_git_url parse_external_link);

subtest 'build_external_link' => sub {
  is build_external_link({apinick => 'soo', owner => 'foo', repo => 'bar', request => '123'}), 'soo#foo/bar!123',
    'right link';
};

subtest 'build_git_url' => sub {
  is_deeply build_git_url({api => 'https://src.opensuse.org', owner => 'foo', repo => 'bar'}),
    'https://src.opensuse.org/foo/bar.git', 'right URL';
};

subtest 'parse_external_link' => sub {
  is_deeply parse_external_link(''),        {apinick => ''},                      'invalid external link';
  is_deeply parse_external_link('foo'),     {apinick => ''},                      'invalid external link';
  is_deeply parse_external_link('obs#123'), {apinick => 'obs', request => '123'}, 'right data';
  is_deeply parse_external_link('soo#foo/bar!123'),
    {apinick => 'soo', owner => 'foo', repo => 'bar', request => '123'}, 'right data';
};

done_testing;
