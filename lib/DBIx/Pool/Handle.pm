package DBIx::Pool::Handle;

use strict;
use warnings;

use DBI;
use base qw(DBI::db);

use Devel::GlobalDestruction;

sub DESTROY {
    local $@;
    my $self = shift;

    return if in_global_destruction;

    my $pool = $self->{x_pool_pool};
    return unless $pool; # pool can be undef if pool was destroyed, since it's a weakref

    $pool->give_back($self->{x_pool_name} => $self);
}

1;
