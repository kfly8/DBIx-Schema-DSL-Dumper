use strict;
use warnings;
use Test::More;
use Test::Requires 'DBD::mysql';
use Test::mysqld;
use DBI;
use DBIx::Schema::DSL::Dumper;


package Foo::DSL;
use warnings;
use strict;
use DBIx::Schema::DSL;

database 'MySQL';

create_table 'user' => columns {
    integer 'id',   primary_key, auto_increment;
    varchar 'name', null;
};

create_table 'book' => columns {
    integer 'id',   primary_key, auto_increment;
    varchar 'name', null;
    integer 'author_id';
    decimal 'price', 'size' => [4,2];

    add_index 'author_id_idx' => ['author_id'];

    belongs_to 'author';
};

create_table 'author' => columns {
    primary_key 'id';
    varchar 'name';
    decimal 'height', 'precision' => 4, 'scale' => 1;

    add_index 'height_idx' => ['height'];

    has_many 'book';
};


package main;

my $mysqld = Test::mysqld->new(
    my_cnf => {
        'skip-networking' => '', # no TCP socket
    }
) or plan skip_all => $Test::mysqld::errstr;

my $dbh = DBI->connect($mysqld->dsn(dbname => 'test'), {RaiseError => 1}) or die 'cannot connect to db';

# initialize
my $output = Foo::DSL->output;

$dbh->do($_) for grep { $_ !~ /^\s+$/ } split /;/, $output;

subtest "dump all tables" => sub {

    # generate schema and eval.
    my $code = DBIx::Schema::DSL::Dumper->dump(
        dbh => $dbh,
        pkg => 'Bar::DSL',
    );

    note $code;
    my $schema = eval $code;
    ::ok !$@, 'no syntax error';
    diag $@ if $@;

    is Bar::DSL->context->db, 'MySQL';
    ok !Bar::DSL->context->default_not_null;
    ok !Bar::DSL->context->default_unsigned;

    for my $table (Foo::DSL->context->schema->get_tables) {
        my $other = Bar::DSL->context->schema->get_table($table->name);
        TODO: {
            local $TODO = 'wip';
            is $table->equals($other), 1;
        }
    }
};

subtest "dump single table" => sub {
    my $code = DBIx::Schema::DSL::Dumper->dump(
        dbh    => $dbh,
        tables => 'user',
    );
    #note $code;
    like $code, qr/user/;
    unlike $code, qr/author/;
    unlike $code, qr/book/;
};

subtest "dump multiple tables" => sub {
    my $code = DBIx::Schema::DSL::Dumper->dump(
        dbh    => $dbh,
        tables => [qw/author book/],
    );
    #note $code;
    unlike $code, qr/user/;
    like $code, qr/book/;
    like $code, qr/author/;
};

subtest "default_unsigned" => sub {

    my $code = DBIx::Schema::DSL::Dumper->dump(
        dbh    => $dbh,
        pkg    => 'Bar::Unsigned::DSL',
        default_unsigned => 1,
    );

    my $schema = eval $code;
    ok !!Bar::Unsigned::DSL->context->default_unsigned;
    unlike $code, qr/ unsigned/;
};

subtest "default_not_null" => sub {

    my $code = DBIx::Schema::DSL::Dumper->dump(
        dbh    => $dbh,
        pkg    => 'Bar::NotNull::DSL',
        default_not_null => 1,
    );

    my $schema = eval $code;
    ok !!Bar::NotNull::DSL->context->default_not_null;
    unlike $code, qr/ not_null/;
};

subtest "table_options" => sub {

    my $code = DBIx::Schema::DSL::Dumper->dump(
        dbh => $dbh,
        pkg => 'Bar::TableOptions::DSL',
        table_options => +{
            'mysql_table_type' => 'MyISAM',
            'mysql_charset'    => 'latin1',
        },
    );

    my $schema = eval $code;
    is Bar::TableOptions::DSL->context->table_extra->{mysql_table_type} ,'MyISAM';
    is Bar::TableOptions::DSL->context->table_extra->{mysql_charset} ,'latin1';
};


done_testing;
