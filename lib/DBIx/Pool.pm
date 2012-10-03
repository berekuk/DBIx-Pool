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

=head1 ATTRIBUTES

=over

=cut

use namespace::autoclean;
use Moo;
no warnings; use warnings; # disable fatal warnings

use MooX::Types::MooseLike::Base qw( HashRef ArrayRef CodeRef Int );
use MooX::Types::MooseLike::Numeric qw( PositiveInt PositiveNum );

use DBI;
use DBIx::Pool::Handle;
use Scalar::Util qw( weaken refaddr );
use List::Util qw( sum );

=item I<max_idle_time>

Connections older than this will be removed from pool.

Measured in seconds.

=cut
has 'max_idle_time' => (
    is => 'ro',
    isa => PositiveNum,
    default => sub { 300 }, # TODO - use this value on garbage-collecting
);

=item I<max_size>

Max pool size. C<get()> and C<add()> will throw an exception if this value is exceeded.

=cut
has 'max_size' => (
    is => 'ro',
    isa => PositiveInt,
    predicate => 1,
);

=item I<connector>

Callback that generates new connections.

This should be a coderef which gets a string name and returns new DBI handle.

If I<connector> is not specified, you'll still be able to populate the pool using C<add()> method.

=cut
has 'connector' => (
    is => 'ro',
    isa => CodeRef,
    predicate => 1,
);

has '_pool' => (
    is => 'ro',
    isa => HashRef[ArrayRef],
    lazy => 1,
    default => sub {
        {}
    },
    clearer => '_clear_pool',
);

has '_taken_stat' => (
    is => 'ro',
    isa => HashRef[Int],
    lazy => 1,
    default => sub {
        {}
    },
);

=back

=head1 METHODS

=over

=item C<add($name, $dbh)>

Add a new DBI handle to the pool.

=cut
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
    bless $dbh => 'DBIx::Pool::Handle';
    push @{ $self->_pool->{$name} }, $dbh;
    return;
}

sub _add_from_connector {
    my $self = shift;
    my ($name) = @_;

    die "pool is empty and connector is not configured" unless $self->has_connector;
    my $dbh = $self->connector->($name);
    $self->add($name => $dbh);
}

sub _give_back {
    my $self = shift;
    my ($name, $dbh) = @_;

    $self->_taken_stat->{$name}--;
    push @{ $self->_pool->{$name} }, $dbh;
}

=item C<get($name)>

Get a free connection from the pool.

New connection will be created using I<connector> if pool is empty.

=cut
sub get {
    my $self = shift;
    my ($name) = @_;

    my $dbh;

    # TODO - check max_size

    my $dbhs = $self->_pool->{$name};
    unless ($dbhs and @$dbhs) {
        $self->_add_from_connector($name);
        $dbhs = $self->_pool->{$name};
    }
    $dbh = splice @{$dbhs}, int rand scalar @{$dbhs}, 1;

    $self->_taken_stat->{$name}++;
    return $dbh;
}

=item C<size()>

Get a total number of connections, both free and taken.

=cut
sub size {
    my $self = shift;

    my $size = sum(
        (map { scalar @$_ } values %{ $self->_pool }),
        values %{ $self->_taken_stat },
    );
    return $size || 0;
}

# TODO - implement clear() method
# It won't be as easy as clearing '_pool' attribute, because some taken connection can be returned back to pool after clearing.
# So, we'll need to keep some "generation_id" counter and ignore handles in give_back() if it doesn't match.

=back

=cut

1;
