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
use Cavil::Gitea::Util qw(build_external_link build_git_url build_markdown_comment label_priority parse_external_link);

subtest 'build_external_link' => sub {
  is build_external_link({apinick => 'soo', owner => 'foo', repo => 'bar', request => '123'}), 'soo#foo/bar!123',
    'right link';
};

subtest 'build_git_url' => sub {
  is_deeply build_git_url({api => 'https://src.opensuse.org', owner => 'foo', repo => 'bar'}),
    'https://src.opensuse.org/foo/bar.git', 'right URL';
};

subtest 'build_markdown_comment' => sub {
  my $result1 = {
    url      => 'https://src.opensuse.org/reviews/details/1',
    state    => 'acceptable',
    result   => 'Reviewed good',
    reviewer => 'tester'
  };
  is build_markdown_comment($result1),
    "Legal reviewed by *tester* as [acceptable](https://src.opensuse.org/reviews/details/1):\n```\nReviewed good\n```",
    'right comment';

  my $result2 = {
    url      => 'https://src.opensuse.org/reviews/details/2',
    state    => 'unacceptable',
    result   => 'Reviewed bad',
    reviewer => 'tester2'
  };
  is build_markdown_comment($result2),
    "Legal reviewed by *tester2* as [unacceptable](https://src.opensuse.org/reviews/details/2):\n```\nReviewed bad\n```",
    'right comment';

  my $result3 = {
    url      => 'https://src.opensuse.org/reviews/details/3',
    state    => 'whatever',
    result   => 'Reviewed bad',
    reviewer => 'tester3'
  };
  is build_markdown_comment($result3), 'Unknown error during legal review.', 'right comment';

  my $result4 = {
    url      => 'https://src.opensuse.org/reviews/details/4',
    state    => 'acceptable_by_lawyer',
    result   => 'OK',
    reviewer => 'tester4'
  };
  is build_markdown_comment($result4),
    "Legal reviewed by *tester4* as [acceptable_by_lawyer](https://src.opensuse.org/reviews/details/4):\n```\nOK\n```",
    'right comment';
};

subtest 'label_priority' => sub {
  is label_priority(4, {'High Priority' => 2, 'Critical Priority' => 4}, []),                    4, 'right priority';
  is label_priority(5, {'High Priority' => 2, 'Critical Priority' => 4}, []),                    5, 'right priority';
  is label_priority(5, {'High Priority' => 2, 'Critical Priority' => 4}, ['unknown']),           5, 'right priority';
  is label_priority(5, {'High Priority' => 2, 'Critical Priority' => 4}, ['High Priority']),     7, 'right priority';
  is label_priority(5, {'High Priority' => 2, 'Critical Priority' => 4}, ['Critical Priority']), 9, 'right priority';
  is label_priority(5, {'High Priority' => 2, 'Critical Priority' => 4}, ['High Priority', 'Critical Priority']), 9,
    'right priority';
  is label_priority(5, {'High Priority' => 2, 'Critical Priority' => 4}, ['Critical Priority', 'High Priority']), 9,
    'right priority';
};

subtest 'parse_external_link' => sub {
  is_deeply parse_external_link(''),        {apinick => ''},                      'invalid external link';
  is_deeply parse_external_link('foo'),     {apinick => ''},                      'invalid external link';
  is_deeply parse_external_link('obs#123'), {apinick => 'obs', request => '123'}, 'right data';
  is_deeply parse_external_link('soo#foo/bar!123'),
    {apinick => 'soo', owner => 'foo', repo => 'bar', request => '123'}, 'right data';
};

done_testing;
