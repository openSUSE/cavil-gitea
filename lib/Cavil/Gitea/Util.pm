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

package Cavil::Gitea::Util;
use Mojo::Base -strict, -signatures;

use Exporter   qw(import);
use List::Util qw(max);
use Mojo::URL;

our @EXPORT_OK = qw(build_external_link build_git_url build_markdown_comment label_priority parse_external_link);

sub build_external_link ($info) {
  return "$info->{apinick}#$info->{owner}/$info->{repo}!$info->{request}";
}

sub build_git_url ($info) {
  my $url = Mojo::URL->new($info->{api});
  return "gitea@@{[$url->host]}:$info->{owner}/$info->{repo}.git" if $info->{ssh};
  return $url->path("/$info->{owner}/$info->{repo}.git");
}

sub build_markdown_comment ($result) {
  return 'Unknown error during legal review.'
    if $result->{state} ne 'acceptable'
    && $result->{state} ne 'acceptable_by_lawyer'
    && $result->{state} ne 'unacceptable';

  my $reason = $result->{result} || ($result->{state} eq 'unacceptable' ? 'Reviewed not ok' : 'Reviewed ok');
  return "Legal reviewed as [$result->{state}]($result->{url}):\n```\n$reason\n```" unless $result->{reviewer};
  return "Legal reviewed by *$result->{reviewer}* as [$result->{state}]($result->{url}):\n```\n$reason\n```";
}

sub label_priority ($prio, $map, $labels) {
  return $prio + (max(map { $map->{$_} // 0 } @$labels) // 0);
}

sub parse_external_link ($external_link) {
  if ($external_link =~ /^(\w+)#(\d+)$/) {
    return {apinick => $1, request => $2};
  }
  elsif ($external_link =~ /^(\w+)#([^\/]+)\/([^!]+)!(\d+)$/) {
    return {apinick => $1, owner => $2, repo => $3, request => $4};
  }
  else {
    return {apinick => ''};
  }
}

1;
