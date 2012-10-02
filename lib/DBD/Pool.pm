package DBD::Pool;

use strict;
use warnings;

our $VERSION = '0.01';

=head1 NAME

DBD::Pool - driver for wrapped DBIx::Pool connections

=head1 SYNOPSIS

  use DBI;
  my $pooled_dbh = DBI->connect(
      'DBD:Pool:', undef, undef,
      { dbh => $dbh },
  );

=cut

use base qw(DBD::File);

use vars qw($err $errstr $sqlstate $drh);

sub DESTROY {
    shift->STORE(Active => 0);
}

$err      = 0;  # DBI::err
$errstr   = ""; # DBI::errstr
$sqlstate = ""; # DBI::state
$drh      = undef;

sub driver {
    my ($class, $attr) = @_;
    return $drh if $drh;

    DBI->setup_driver($class);

    my $self = $class->SUPER::driver({
        Name        => 'Pool',
        Version     => $DBD::Pool::VERSION,
        Err         => \$DBD::Pool::err,
        Errstr      => \$DBD::Pool::errstr,
        State       => \$DBD::Pool::sqlstate,
        Attribution => 'DBD::Pool',
    });
    return $self;
}

sub CLONE {
    undef $drh;
}

#######################################################################
package DBD::Pool::dr;

use strict;
use warnings;

$DBD::Pool::dr::imp_data_size = 0;
use DBD::File;
use DBI qw();
use base qw(DBD::File::dr);

sub connect {
    my($drh, $dbname, $user, $auth, $attr) = @_;

    for (qw/ dbh name pool /) {
        die "$_ not defined" unless $attr->{$_};
    }

    my $dbh = DBI::_new_dbh(
      $drh => {
               Name         => 'pooldb',
               USER         => $user,
               CURRENT_USER => $user,
              },
    );
    $dbh->STORE(Active => 1);

    for (qw/ dbh name pool /) {
        $dbh->STORE("x_pool_$_" => $attr->{$_});
    }

    return $dbh;
}

#######################################################################
package DBD::Pool::db;

use strict;
use warnings;

$DBD::Pool::db::imp_data_size = 0;

my $LOCAL_ATTRIBUTES = {
    PrintError => 1,
    RaiseError => 1,
    Active     => 1,
    AutoCommit => 1,
    x_pool_dbh => 1,
    x_pool_selfaddr => 1, # see DBIx::Pool code
    x_pool_name => 1,
    x_pool_pool => 1,
};

use vars qw($AUTOLOAD);

sub prepare {
    my $dbh = shift;
    my @args = @_;

    # create a 'blank' sth
    my ($outer, $sth) = DBI::_new_sth($dbh, { Statement => $args[0] });

    my $real_dbh = $dbh->{x_pool_dbh};
    my $real_sth = $real_dbh->prepare(@args);

    $outer->STORE('x_pool_real_sth', $real_sth);

    # statements carry the link to dbh inside them, so we don't return dbh to the pool prematurely
    $outer->STORE('x_pool_dbh', $dbh);

    return $outer;
}

sub _proxy_method {
    my ($method, $dbh, @args) = @_;
    my $real_dbh = $dbh->{x_pool_dbh};
    return $real_dbh->$method(@args);
}

# TODO: take a more accurate logic from DBD::Proxy
sub AUTOLOAD {
    my $method = $AUTOLOAD;
    $method =~ s/(.*::(.*)):://;

    my $s = sub {
        return _proxy_method($method, @_) # goto &_proxy_method ?
    };

    no strict 'refs';
    *{$AUTOLOAD} = $s;
    goto &$s;
}

sub STORE {
    my ($dbh, $attr, $val) = @_;

    if ($LOCAL_ATTRIBUTES->{$attr}) {
        $dbh->{$attr} = $val;

        # because of some old DBI bug
        # copy-pasted from DBD::Safe
        # is this a cargo-cult?
        if ($attr eq 'Active') {
            my $v = $dbh->FETCH($attr);
        }
    }
    else {
        $dbh->{x_pool_dbh}->STORE($attr => $val);
    }
}

sub FETCH {
    my ($dbh, $attr) = @_;

    if ($LOCAL_ATTRIBUTES->{$attr}) {
        return $dbh->{$attr};
    }
    else {
        return $dbh->{x_pool_dbh}->FETCH($attr);
    }
}

1;

package DBD::Pool::st;

use strict;
use warnings;

$DBD::Pool::st::imp_data_size = 0;

use vars qw($AUTOLOAD);

sub bind_param;
sub bind_param_inout;
sub bind_param_array;
sub execute;
sub execute_array;
sub execute_for_fetch;
sub fetchrow_arrayref;
sub fetchrow_array;
sub fetchrow_hashref;
sub fetchall_arrayref;
sub fetchall_hashref;
sub rows;
sub bind_col;
sub bind_columns;
sub dump_results;

sub FETCH {
    my ($sth, $key) = @_;
    if ($key =~ /^x_pool/) {
        return $sth->{$key};
    }
    else {
        my $real_sth = $sth->{x_pool_real_sth};
        return $real_sth->FETCH($key);
    }
}

sub STORE {
    my ($sth, $key, $value) = @_;
    if ($key =~ /^x_pool/) {
        $sth->{$key} = $value;
    } else {
        my $real_sth = $sth->FETCH('x_pool_real_sth');
        return $real_sth->STORE($key, $value);
    }
}

sub AUTOLOAD {
    my $method = $AUTOLOAD;
    $method =~ s/(.*::(.*)):://;

    my $s = sub {
        my $sth = shift;
        return $sth->{x_pool_real_sth}->$method(@_);
    };

    no strict 'refs';
    *{$AUTOLOAD} = $s;
    goto &$s;
}

1;
