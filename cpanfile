requires 'perl', '5.008001';
requires 'DBIx::Inspector', '0.12';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'Test::Requires';
    requires 'DBI';
    requires 'DBD::SQLite';
};

