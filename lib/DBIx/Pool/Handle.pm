package DBIx::Pool::Handle;

use strict;
use warnings;

use DBI;
use base qw(DBI::db);

use Devel::GlobalDestruction;

use Scalar::Util qw( refaddr weaken );
our %HANDLE_TO_POOL;

sub register_pool {
    my $self = shift;
    my ($name, $pool) = @_;

    weaken $pool;
    $HANDLE_TO_POOL{ refaddr $self } = [ $name, $pool ];
}

sub DESTROY {
    local $@;
    my $self = shift;

    return if in_global_destruction;

    if (my $pool_info = delete $HANDLE_TO_POOL{ refaddr $self }) {
        my ($name, $pool) = @$pool_info;
        $pool->_give_back($name, $self) if defined $pool;
    }
}

1;
