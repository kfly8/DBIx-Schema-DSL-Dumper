use strict;
use warnings;
use Test::More;
use Test::Requires 'DBD::SQLite';
use DBI;
use DBIx::Schema::DSL::Dumper;

# TODO mysql
#use Test::mysqld;
#my $mysqld = Test::mysqld->new(
#    my_cnf => {
#        'skip-networking' => '', # no TCP socket
#    }
#) or plan skip_all => $Test::mysqld::errstr;
#my $dbh = DBI->connect($mysqld->dsn) or die 'cannot connect to db';

# initialize
my $dbh = DBI->connect('dbi:SQLite::memory:', '', '', {RaiseError => 1}) or die 'cannot connect to db';
$dbh->do(q{
    CREATE TABLE multi_pk (
        pk1         INTEGER NOT NULL,
        pk2         INTEGER NOT NULL,
        PRIMARY KEY(pk1, pk2)
    );
});

$dbh->do(q{
    CREATE TABLE author (
        id          INTEGER UNSIGNED AUTO_INCREMENT,
        name        VARCHAR(32) NOT NULL,
        type        VARCHAR(255) DEFAULT 'foo',
        description VARCHAR(255),
        created_at  DATETIME,

        PRIMARY KEY (`id`),
        FOREIGN KEY (`id`) REFERENCES `book` (`author_id`)
   );
});

$dbh->do(q{
    CREATE INDEX name_idx ON author (`name`);
});
$dbh->do(q{
    CREATE INDEX type_description_idx ON author (`type`, `description`);
});
$dbh->do(q{
    CREATE UNIQUE INDEX created_at_uniq ON author (`created_at`);
});


$dbh->do(q{
    CREATE TABLE book (
        id          INTEGER UNSIGNED AUTO_INCREMENT,
        author_id   INTEGER,
        name        VARCHAR(32),
        created_at  DATETIME,

        PRIMARY KEY (`id`)
    );
});
        #FOREIGN KEY (`author_id`) REFERENCES `author` (`id`)


subtest "dump all tables" => sub {
    # generate schema and eval.
    my $code = DBIx::Schema::DSL::Dumper->dump(
        dbh => $dbh,
        pkg => 'Foo::DSL',
        default_not_null => 1,
        default_unsigned => 1,
    );
    note $code;
    ok 1;
    my $schema = eval $code;
    ::ok !$@, 'no syntax error';
    diag $@ if $@;

# TODO
#    {
#        package Mock::DB;
#        use parent 'Teng';
#    }
#
#    my $db = Mock::DB->new(dbh => $dbh);
#
#    for my $table_name (qw/user1 user2 user3/) {
#        my $user = $db->schema->get_table($table_name);
#        is($user->name, $table_name);
#        is(join(',', @{$user->primary_keys}), 'user_id');
#        is(join(',', @{$user->columns}), 'user_id,name,email,created_on');
#    }
#
#    my $row_class = $db->schema->get_row_class('user1');
#    isa_ok $row_class, 'Mock::DB::Row::User1';
#
#    my $row = $db->insert('user1', +{name => 'nekokak', email => 'nekokak@gmail.com'});
#    is $row->email, 'nekokak@gmail.com_deflate_inflate';
#    is $row->get_column('email'), 'nekokak@gmail.com_deflate';
};

#subtest "dump single table" => sub {
#    # generate schema and eval.
#    my $code = Teng::Schema::Dumper->dump(
#        dbh       => $dbh,
#        namespace => 'Mock::DB',
#        tables => 'user1',
#    );
#    note $code;
#    like $code, qr/user1/;
#    unlike $code, qr/user2/;
#    unlike $code, qr/user3/;
#};
#
#subtest "dump multiple tables" => sub {
#    # generate schema and eval.
#    my $code = Teng::Schema::Dumper->dump(
#        dbh       => $dbh,
#        namespace => 'Mock::DB',
#        tables => [qw/user1 user2/],
#    );
#    note $code;
#    like $code, qr/user1/;
#    like $code, qr/user2/;
#    unlike $code, qr/user3/;
#};

done_testing;
