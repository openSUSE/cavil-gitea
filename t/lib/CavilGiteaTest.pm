# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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
