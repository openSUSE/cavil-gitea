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

package Cavil::Gitea;
use Mojo::Base -base, -signatures;

use Cavil::Gitea::CavilClient;
use Cavil::Gitea::GiteaClient;
use Cavil::Gitea::Util qw(label_priority);
use Mojo::Log;
use Mojo::Util qw(extract_usage getopt);

has apinick          => 'soo';
has base_priority    => 4;
has cavil            => sub ($self) { Cavil::Gitea::CavilClient->new(log => $self->log) };
has gitea            => sub ($self) { Cavil::Gitea::GiteaClient->new(log => $self->log) };
has label_priorities => sub { {'High Priority' => 2, 'Critical Priority' => 4} };
has log              => sub { Mojo::Log->new };

sub check_open_requests ($self) {
  my $log   = $self->log;
  my $gitea = $self->gitea;
  my $cavil = $self->cavil;

  my $open_requests = $cavil->get_open_requests;
  my $nick          = $self->apinick;
  my $our_requests  = [grep { $_->{external_link}{apinick} eq $nick } @$open_requests];

  my $num_open = @$open_requests;
  my $num_ours = @$our_requests;
  $log->info(qq{Found $num_open open legal reviews, $num_ours of them with "$nick" external link});

  for my $request (@$our_requests) {
    my $package    = $request->{package};
    my $checkout   = $request->{checkout};
    my $link       = $request->{external_link};
    my $owner      = $link->{owner};
    my $repo       = $link->{repo};
    my $request_id = $link->{request};

    $log->info(qq{Checking status of package $package ($owner/$repo!$request_id)});
    my $info   = $gitea->pr_info($owner, $repo, $request_id);
    my $result = $cavil->review_result($package);

    # Request is obsolete (no longer requested or new commit)
    if (($info->{checkout} ne $checkout) || !$info->{review_requested} || $info->{state} ne 'open') {
      $log->info(qq{Review request for package $package is obsolete, removing});
      $cavil->remove_request($link);
    }

    # Probably re-opened review
    elsif ($result->{state} eq 'obsolete') {
      $log->info(qq{Review request for package $package was obsoleted, re-opening});
      $cavil->update_request($package, $link);
    }

    # Packag was reviewed
    elsif ($result->{state} ne 'new') {
      $log->info(qq{Package $package was reviewed as "$result->{state}"});
      $gitea->post_review($owner, $repo, $request_id, $result);
      $cavil->remove_request($link);
    }

    # Review is still pending
    else {
      $log->info(qq{Review request for package $package is still pending});

      my $cavil_prio = $result->{priority};
      my $gitea_prio = label_priority($self->base_priority, $self->label_priorities, $info->{labels});
      if ($cavil_prio != $gitea_prio) {
        $log->info(qq{Updating review priority for package $package from $cavil_prio to $gitea_prio});
        $cavil->update_package($package, {priority => $gitea_prio});
      }
    }
  }
}

sub open_reviews ($self) {
  my $log   = $self->log;
  my $gitea = $self->gitea;
  my $cavil = $self->cavil;

  my $reviews = $gitea->get_review_requests;
  for my $review (@$reviews) {
    my $owner    = $review->{owner};
    my $repo     = $review->{repo};
    my $request  = $review->{request};
    my $checkout = $review->{checkout};

    $log->info(qq{Opening legal review for $owner/$repo!$request ($checkout)});

    my $package_id = $cavil->create_request(
      {
        api      => $gitea->url,
        apinick  => $self->apinick,
        owner    => $owner,
        repo     => $repo,
        request  => $request,
        checkout => $checkout,
        priority => label_priority($self->base_priority, $self->label_priorities, $review->{labels})
      }
    );

    $log->info("Review request tracked as package $package_id");

    # Mark notification as read late in case of errors (so re-runs will pick it up)
    $gitea->mark_notification_read($review->{notification});
  }
}

sub peer_info ($self) {
  my $log   = $self->log;
  my $cavil = $self->cavil;
  $log->info(qq/Connecting to Cavil instance "@{[$cavil->url]}"/);
  my $gitea = $self->gitea;
  my $user  = $gitea->whoami;
  $log->info(qq/Connecting to Gitea instance "@{[$gitea->url]}" (@{[$self->apinick]}) as user "$user->{login}"/);
}

sub run ($self) {
  getopt
    'api-nick=s'      => sub { $self->apinick($_[1]) },
    'base-priority=i' => sub { $self->base_priority($_[1]) },
    'cavil-url=s'     => sub { $self->cavil->url($_[1]) },
    'cavil-token=s'   => sub { $self->cavil->token($_[1]) },
    'gitea-url=s'     => sub { $self->gitea->url($_[1]) },
    'gitea-token=s'   => sub { $self->gitea->token($_[1]) },
    'r|review'        => \my $review;

  if ($review) {
    $self->peer_info;
    $self->check_open_requests;
    $self->open_reviews;
  }
  else {
    say extract_usage;
  }
}

1;

=head1 NAME

Cavil::Gitea - Gitea legal review bot

=head1 SYNOPSIS

  Usage: cavil-gitea [OPTIONS]

    # Perform legal reviews for open pull requests
    cavil-gitea --cavil-url https://legaldb.suse.de --cavil-token 4321\
      --gitea-url https://src.suse.de --gitea-token 1234 --api-nick ssd\
      --review

  Options:
        --api-nick <nick>       API nickname, defaults to 'soo'
        --base-priority <num>   Base priority for legal reviews, defaults to 4
        --cavil-url <url>       Cavil server URL
        --cavil-token <token>   Cavil API token
        --gitea-url <url>       Gitea server URL
        --gitea-token <token>   Gitea API token
    -h, --help                  Show this summary of available options
    -r, --review                Check notifications for review requests

=head1 DESCRIPTION

A legal review bot for Gitea.

=cut
