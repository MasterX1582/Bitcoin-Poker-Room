package Room::Controller::User;
use Moose;
use namespace::autoclean;
use DateTime;
use Data::Dumper;
use String::Random;
use POSIX;


BEGIN {extends 'Catalyst::Controller::HTML::FormFu'; }

=head1 NAME

Room::Controller::User - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub auto :Private {
  my ($self, $c) = @_;

  if (!$c->user) {
    $c->res->redirect(
      $c->uri_for('/account/login', '', {'destination' => $c->action,})
    );

    return;
  }

  1;
}


=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;
}



sub edit :Local :Args(0) :FormConfig {
  my ( $self, $c ) = @_;

  my $form = $c->stash->{form};
  
  $form->get_field({ name => 'email' })->default(
    $c->user->email
  );

  $form->get_field({name => 'hide_gravatar'})->default(
    $c->user->hide_gravatar
  );

  $form->get_field({name => 'emergency_address'})->default(
    $c->user->emergency_address
  );

  # If 'Cancel' button pressed - redirect to /user page
  if ($c->req->param('cancel')) {
    $c->res->redirect(
      $c->uri_for('/user')
    );
  }

  if ($form->submitted_and_valid) {

    if (! $c->user->check_password( $form->params->{old_password} )) {
      $form->get_field("old_password")->get_constraint({ type => "Callback" })->force_errors(1);
      $form->process();
      return;
    }
    
    if ($form->params->{email} ne '') {
      my $user_rs = $c->model("PokerNetwork::Users")->search({
        email => $form->params->{email},
        -not => {
          serial => $c->user->serial()
        },
      });
      
      if ( $user_rs->count() > 0 ) {
        $form->get_field("email")->get_constraint({ type => "Callback" })->force_errors(1);
        $form->process();
        return;
      }
    }
    
    $c->user->email(
      $form->params->{email}
    );

    if ($form->params->{password} ne '') {
      $c->user->password(
        $form->params->{password}
      );
    }

    $c->user->hide_gravatar( $form->params->{hide_gravatar} );
    $c->user->emergency_address( $form->params->{emergency_address} );

    $c->user->update();
    $c->user->make_column_dirty('data');

    push @{$c->flash->{messages}}, "Account successfully updated.";

    $c->res->redirect(
      $c->uri_for('/user')
    );
  }
}




sub withdraw_bitcoin :Path('withdraw/bitcoin') :FormConfig {
  my ($self, $c) = @_;
  my $form = $c->stash->{form};
  my $balance = $c->user->balances->search({currency_serial => 1})->first;

  if (! $balance) {
    $balance = $c->user->balances->find_or_create({ currency_serial => 1 });
    $balance->amount(0);
    $balance->update();
  }

  $c->stash->{balance} = $balance;
  $c->stash->{current_balance} = $balance->amount;

  if ($form->submitted_and_valid) {
    my $address = $form->params->{bitcoin_address};
    my $amount = $form->params->{amount};

    if ($balance->amount < $amount || $amount < 0.01 || int($amount * 100) / 100 < $amount)  {
      $form->get_field("amount")->get_constraint({ type => "Callback" })->force_errors(1);
      $form->process();
      return;
    }

    $balance->amount(
      $balance->amount() - $amount
    );
    $balance->update();

    my $result = $c->model("BitcoinServer")->send_to_address($address, $amount);

    # Create withdrawal record for tracking purposes.
    my $withdrawal = $c->user->withdrawals->create({
      currency_serial => 1,
      amount => $amount,
      dest => $address,
      info => "Result: ". $result ."\n\nError: ". Dumper($c->model('BitcoinServer')->api->error),
      created_at => DateTime->now,
    });

    if (! $c->model('BitcoinServer')->api->error) {
      # Mark as processed if successful
      $withdrawal->processed_at( DateTime->now() );
      $withdrawal->processed(1);
      $withdrawal->update();

      push @{$c->flash->{messages}}, "Bitcoins sent.";

    }
    else {
      push @{$c->flash->{errors}}, "We received your withdrawal request and will process it ASAP. If you will not receive bitcoins in 24 hours, please contact us.";
    }
    
    $c->res->redirect(
      $c->uri_for('/user')
    );
  }
}


sub points_cashout :Local :Args(1) {
    my ($self, $c, $currency_serial) = @_;

    # @TODO: this is hardcoded prevention. Should be configurable.
    if ($currency_serial != 1) {
        $c->page_not_found;
    }

    my $balance = $c->user->balance($currency_serial);

    if ($balance->points < $c->config->{points_cashout_limit}) {
        push @{$c->flash->{errors}}, "You need to get at least ". ($c->config->{points_cashout_limit} * 100) .
             " points to be able to cash out them.";
    }
    else {
        my $points = $balance->points;

        if ( $balance->points_cashout($points) ) {
            push @{$c->flash->{messages}}, "Successfuly cashed out ". ($points * 100) ." points.";
        }
        else {
            push @{$c->flash->{errors}}, "Cash-out error happened. Contact support with details if this issue.";
        }
    }

    $c->res->redirect( 
        $c->uri_for('/user') 
    );
}


sub logout :Local :Args(0) {
  my ( $self, $c ) = @_;

  $c->logout;
  
  $c->model("PokerNetwork")->logout(
    $c->session->{pokernetwork_auth}
  );
  $c->session->{pokernetwork_auth} = undef;
  
  push @{$c->flash->{messages}}, "Logged out. Good bye.";

  $c->res->redirect(
    $c->uri_for('/')
  );
}



=head1 AUTHOR

Pavel Karoukin

=head1 LICENSE

Copyright (C) 2010 Pavel A. Karoukin <pavel@yepcorp.com>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


=cut

__PACKAGE__->meta->make_immutable;

