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

package CavilGiteaTest;
use Mojo::Base -base, -signatures;

use Cavil::Gitea;

has [qw(cavil_url cavil_token gitea_url gitea_token)];
has cavil_gitea => sub { Cavil::Gitea->new };

sub new ($class, $app) {
  my $self = $class->SUPER::new;

  my $cg = $self->cavil_gitea;
  $self->cavil_url('http://127.0.0.1:' . $cg->cavil->ua->server->app($app)->url->port)->cavil_token('cavil-token');
  $self->gitea_url('http://127.0.0.1:' . $cg->gitea->ua->server->app($app)->url->port)->gitea_token('gitea-token');

  return $self;
}

sub run ($self, @args) {
  my $cg = $self->cavil_gitea;

  my $messages = $cg->log->capture('trace');
  my $buffer   = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    local @ARGV   = (
      '--cavil-url',   $self->cavil_url,   '--cavil-token', $self->cavil_token, '--gitea-url', $self->gitea_url,
      '--gitea-token', $self->gitea_token, @args
    );
    $cg->run;
  }

  return {stdout => $buffer, logs => "$messages"};
}

1;
