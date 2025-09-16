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

use Carp       qw(croak);
use Exporter   qw(import);
use List::Util qw(max);
use Mojo::URL;
use YAML::XS qw(LoadFile);

our @EXPORT_OK = (
  qw(build_external_link build_git_url build_markdown_comment label_priority),
  qw(parse_external_link parse_git_url parse_product_file)
);

sub build_external_link ($info) {
  return "$info->{apinick}#$info->{owner}/$info->{repo}!$info->{request}";
}

sub build_git_url ($info) {
  my $url = Mojo::URL->new($info->{api});
  return "gitea@@{[$url->host]}:$info->{owner}/$info->{repo}.git" if $info->{ssh};
  return $url->path("/$info->{owner}/$info->{repo}.git");
}

sub build_markdown_comment ($result) {
  return "Legal review [in progress]($result->{url})."
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

sub parse_git_url ($git, $base_host) {
  return {host => $base_host, owner => $1, repo => $2} if $git =~ /^\.\.\/\.\.\/([^\/]+)\/(.+)$/;

  my $url = Mojo::URL->new($git);
  return undef unless ($url->scheme // '') =~ /^https?$/;
  return undef unless my $host = $url->host_port;
  return undef unless $base_host eq $host;
  return undef unless $url->path =~ m{^/([^/]+)/(.+?)\.git$};
  return {host => $host, owner => $1, repo => $2};
}

sub parse_product_file ($path) {
  my $data = LoadFile($path);
  return [] unless $data->{products} && ref $data->{products} eq 'ARRAY';

  my @products;
  for my $product (@{$data->{products}}) {
    next unless $product->{name};
    next unless ($product->{repo} // '') =~ m{^([^/]+)/([^#]+)#(.+)$};
    push @products, {name => $product->{name}, owner => $1, repo => $2, branch => $3};
  }

  return \@products;
}

1;
