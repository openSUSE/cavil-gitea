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

package Cavil::Gitea::CavilClient;
use Mojo::Base -base, -signatures;

use Mojo::URL;
use Mojo::UserAgent;
use Cavil::Gitea::Util qw(build_external_link build_git_url parse_external_link);

has 'log';
has token => sub { die 'Cavil token is required' };
has ua    => sub { Mojo::UserAgent->new };
has url   => sub { die 'Cavil URL is required' };

sub get_open_requests ($self) {
  my $requests = $self->_request('GET', '/requests');

  my @requests;
  for my $r (@{$requests->{requests}}) {
    my $request = {
      external_link => parse_external_link($r->{external_link}),
      checkout      => $r->{checkouts}[0],
      package       => $r->{packages}[0]
    };
    push @requests, $request;
  }

  return \@requests;
}

sub create_request ($self, $info) {
  my $external_link = build_external_link($info);
  my $form          = {
    api           => build_git_url($info),
    package       => $info->{repo},
    rev           => $info->{checkout},
    external_link => $external_link,
    type          => 'git'
  };

  my $data       = $self->_request('POST', '/packages', $form);
  my $package_id = $data->{saved}{id};
  $self->_request('POST', '/requests', {external_link => $external_link, package => $package_id});

  return $package_id;
}

sub remove_request ($self, $info) {
  my $data = $self->_request('DELETE', '/requests', {external_link => build_external_link($info)});
  return !!$data->{removed};
}

sub review_result ($self, $package) {
  my $data = $self->_request('GET', "/package/$package");
  return {state => $data->{state}, result => $data->{result}};
}

sub update_request ($self, $package, $info) {
  my $form = {external_link => build_external_link($info), state => 'new'};
  my $data = $self->_request('POST', "/packages/import/$package", $form);
  return !!$data->{imported};
}

sub _headers ($self) {
  return {Authorization => 'Token ' . $self->token};
}

sub _request($self, $method, $path, $form = undef) {
  my $ua = $self->ua;
  my $tx = $ua->build_tx($method => $self->_url($path) => $self->_headers, $form ? (form => $form) : ());
  $tx = $ua->start($tx);
  return $tx->result->json;
}

sub _url ($self, $path) {
  return Mojo::URL->new($self->url . "$path");
}

1;
