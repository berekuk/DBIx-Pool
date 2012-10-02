package DBIx::Pool;

=head1 NAME

DBIx::Pool - pool of DBI connections

=head1 SYNOPSIS

    my $pool = DBIx::Pool->new;

    $pool->get('blah'); # take a connect from pool or create a new one

    $pool = DBIx::Pool->new(
        connector => sub {
            my $name = shift;
            ...
        }
    );

    # named connectors
    # you'd have to register one per DB separately, but it'll probably be more convenient for some users
    $pool->set_connector('blah' => sub {
        ... # return a DBI connect to 'blah' DB
    });

    # fixed-size pool without connectors
    # it'll lack reconnection ability (unless you use DBD::Safe)
    # not sure how useful this case will be, but it's easy to implement
    $pool->add('blah' => DBI->connect(...)) for 1..10;

    # other options:
    $pool = DBIx::Pool->new(
        max_idle_time => 300, # timeout for purging idle connections
        max_size => 100, # throw exceptions if we've got this many connections in pool; do we need separate values per $name?
    );

    # return the connection to the pool
    # internal method; only wrapped connections (DBD::Pool or something) will call it from its destructor
    $pool->give_back($dbh); # $dbh is a wrapped connect; it'll be faster than storing non-wrapped connections and repeating wraps on ->get

    # there's also a case of custom connection options
    # our old code calculated md5(options) and stored the connection in pool under "$name:$md5" key
    # do we need this logic here?

=cut

use Moo;
no warnings; use warnings; # disable fatal warnings

use MooX::Types::MooseLike::Base qw( HashRef ArrayRef );
use MooX::Types::MooseLike::Numeric qw( PositiveInt PositiveNum );

use DBI;
use Scalar::Util qw( weaken refaddr );

has 'max_idle_time' => (
    is => 'ro',
    isa => PositiveNum,
    default => sub { 300 },
);

has 'max_size' => (
    is => 'ro',
    isa => PositiveInt,
    predicate => 1,
);

has '_taken' => (
    is => 'ro',
    isa => HashRef,
    default => sub {
        {}
    },
    clearer => '_clear_taken',
);

has '_pool' => (
    is => 'ro',
    isa => HashRef[ArrayRef],
    default => sub {
        {}
    },
    clearer => '_clear_pool',
);

sub clear {
    my $self = shift;
    $self->_clear_pool;
    $self->_clear_taken;
}

sub add {
    my $self = shift;
    my ($name, $inner_dbh) = @_;

    my $dbh = DBI->connect(
        'DBI:Pool:',
        undef,
        undef,
        {
            dbh => $inner_dbh,
            name => $name,
            pool => $self, # FIXME - circular reference
        }
    );
    $dbh->{x_pool_selfaddr} = refaddr $dbh;
    push @{ $self->_pool->{$name} }, $dbh;
}

sub give_back {
    my $self = shift;
    my ($name, $addr) = @_;

    my $dbh = delete $self->_taken->{$addr};
    unless ($dbh) {
        warn "dbh '$name' with addr '$addr' not found in taken list";
        return;
    }
    push @{ $self->_pool->{$name} }, $dbh;
}

sub get {
    my $self = shift;
    my ($name) = @_;

    my $dbhs = $self->_pool->{$name};
    die "pool is empty and connectors are not implemented yet" unless $dbhs and @$dbhs;

    my $dbh = splice @{$dbhs}, int rand scalar @{$dbhs}, 1;
    $self->_taken->{refaddr $dbh} = $dbh;
    weaken $self->_taken->{refaddr $dbh};
    return $dbh;
}

1;
