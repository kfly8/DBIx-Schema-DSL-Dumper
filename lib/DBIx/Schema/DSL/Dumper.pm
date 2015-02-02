package DBIx::Schema::DSL::Dumper;
use 5.008001;
use strict;
use warnings;
use DBIx::Inspector;
use DBIx::Inspector::Iterator;
use Carp ();

our $VERSION = "0.03";

# XXX copy from SQL::Translator::Parser::DBI-1.59
use constant DRIVERS => {
    mysql            => 'MySQL',
    odbc             => 'SQLServer',
    oracle           => 'Oracle',
    pg               => 'PostgreSQL',
    sqlite           => 'SQLite',
    sybase           => 'Sybase',
    pg               => 'PostgreSQL',
    db2              => 'DB2',
};

sub dump {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;

    my $dbh = $args{dbh} or Carp::croak("missing mandatory parameter 'dbh'");

    my $inspector = DBIx::Inspector->new(dbh => $dbh);

    my $ret = "";

    if ( ref $args{tables} eq "ARRAY" ) {
        for my $table_name (@{ $args{tables} }) {
            $ret .= _render_table($inspector->table($table_name), \%args);
        }
    }
    elsif ( $args{tables} ) {
        $ret .= _render_table($inspector->table($args{tables}), \%args);
    }
    else {
        my $pkg = $args{pkg} or Carp::croak("missing mandatory parameter 'pkg'");

        $ret .= "package ${pkg};\n";
        $ret .= "use strict;\n";
        $ret .= "use warnings;\n";
        $ret .= "use DBIx::Schema::DSL;\n";
        $ret .= "\n";

        my $db_type = $dbh->{'Driver'}{'Name'} or die 'Cannot determine DBI type';
        my $driver  = DRIVERS->{ lc $db_type } or warn "$db_type not supported";
        $ret .= sprintf("database '%s';\n", $driver) if $driver;
        $ret .= "default_unsigned;\n" if $args{default_unsigned};
        $ret .= "default_not_null;\n" if $args{default_not_null};
        $ret .= "\n";

        if ($args{table_options}) {
            $ret .= "add_table_options\n";
            my @table_options;
            for my $key (keys %{$args{table_options}}) {
                push @table_options => sprintf("    '%s' => '%s'", $key, $args{table_options}->{$key})
            }
            $ret .= join ",\n", @table_options;
            $ret .= ";\n\n";
        }

        for my $table_info (sort { $a->name cmp $b->name } $inspector->tables) {
            $ret .= _render_table($table_info, \%args);
        }
        $ret .= "1;\n";
    }

    return $ret;
}


sub _render_table {
    my ($table_info, $args) = @_;

    my $ret = "";

    $ret .= sprintf("create_table '%s' => columns {\n", $table_info->name);

    for my $col ($table_info->columns) {
        $ret .= _render_column($col, $table_info, $args);
    }

    $ret .= _render_index($table_info, $args);

    $ret .= "};\n\n";

    return $ret;
}

sub _render_column {
    my ($column_info, $table_info, $args) = @_;

    my $ret = "";
    $ret .= sprintf("    column '%s'", $column_info->name);

    my ($type, @opt) = split / /, $column_info->type_name;

    $ret .= sprintf(", '%s'", $type);

    my %opt = map { lc($_) => 1 } @opt;

    if (lc($type) =~ /^(enum|set)$/) {
        # XXX
        $ret .= sprintf(" => ['%s']", join "','", @{$column_info->{MYSQL_VALUES}});
    }

    $ret .= ", signed"   if $opt{signed};
    $ret .= ", unsigned" if $opt{unsigned} && !$args->{default_unsigned};

    if (defined $column_info->column_size) {
        my $column_size = $column_info->column_size;
        if (lc($type) eq 'decimal') {
            # XXX
            $column_size = sprintf("[%d, %d]", $column_info->column_size, $column_info->{DECIMAL_DIGITS});
        }
        elsif (lc($type) =~ /^(enum|set)$/) {
            undef $column_size;
        }

        $ret .= sprintf(", size => %s", $column_size) if $column_size;
    }

    $ret .= ", null"     if $column_info->nullable;
    $ret .= ", not_null" if !$column_info->nullable && !$args->{default_not_null};

    if (defined $column_info->column_def) {
        my $column_def = $column_info->column_def;

        ## XXX workaround for SQLite ??
        #$column_def =~ s/^'//;
        #$column_def =~ s/'$//;

        $ret .= sprintf(", default => '%s'", $column_def)
    }

    if (
        $opt{auto_increment} or
        # XXX
        ($args->{dbh}->{'Driver'}{'Name'} eq 'mysql' && $column_info->{MYSQL_IS_AUTO_INCREMENT})
    ) {
        $ret .= ", auto_increment"
    }

    $ret .= ";\n";

    return $ret;
}

sub _render_index {
    my ($table_info, $args) = @_;

    my @primary_key_names = map { $_->name } $table_info->primary_key;
    my @fk_list           = $table_info->fk_foreign_keys;

    my $ret = "";

    # primary key
    if (@primary_key_names) {
        $ret .= "\n";
        $ret .= sprintf("    set_primary_key('%s');\n", join "','", @primary_key_names);
    }


    # index
    {
        my $itr = _statistics_info($args->{dbh}, $table_info);
        my %pk_name = map { $_ => 1 } @primary_key_names;
        my %fk_name = map { $_->fkcolumn_name => 1 } @fk_list;

        my %index_info;
        while (my $index_key = $itr->next) {
            next if $pk_name{$index_key->column_name};
            next if $fk_name{$index_key->column_name};

            push @{$index_info{$index_key->index_name}} => $index_key;
        }

        $ret .= "\n" if %index_info;
        for my $index_name (sort keys %index_info) {
            my @index_keys = @{$index_info{$index_name}};
            my @column_names = map { $_->column_name } @index_keys;

            $ret .= sprintf("    add_%sindex('%s' => [%s]%s);\n",
                        $index_keys[0]->non_unique ? '' : 'unique_',
                        $index_name,
                        (join ",", (map { q{'}.$_.q{'} } @column_names)),
                        $index_keys[0]->non_unique && $index_keys[0]->type ? sprintf(", '%s'", $index_keys[0]->type) : '',
                    );
        }
    }

    # foreign key
    if (@fk_list) {
        $ret .= "\n";
        for my $fk (@fk_list) {
            if ($fk->fkcolumn_name eq sprintf('%s_id', $fk->pktable_name)) {
                $ret .= sprintf("    belongs_to('%s')\n", $fk->pktable_name)
            }
            else {
                $ret .= sprintf("    foreign_key('%s','%s','%s')\n", $fk->fkcolumn_name, $fk->pktable_name, $fk->pkcolumn_name);
            }
        }
    }

    return $ret;
}

# EXPERIMENTAL: https://metacpan.org/pod/DBI#statistics_info
sub _statistics_info {
    my ($dbh, $table_info) = @_;

    my $sth;
    if ($dbh->{'Driver'}{'Name'} eq 'mysql') {
        # TODO p-r DBD::mysqld ??
        $sth = $dbh->prepare(q/
                SELECT * FROM INFORMATION_SCHEMA.STATISTICS WHERE table_schema = ? AND table_name = ?
              /);
        $sth->execute($table_info->schema, $table_info->name);
    }
    else {
        $sth = $dbh->statistics_info(undef, undef, $table_info->name, undef, undef);
    }

    DBIx::Inspector::Iterator->new(
        sth => $sth,
        callback => sub {
            # TODO p-r DBIx::Inspector ??
            my $row = shift;
            DBIx::Inspector::Statics->new($row);
        },
    );
}

package # hide from PAUSE
    DBIx::Inspector::Statics;

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{ $_[0] } : @_;
    bless {%args}, $class;
}

{
    no strict 'refs';
    for my $k (
        qw/
            TABLE_CAT
            TABLE_SCHEM
            TABLE_NAME
            NON_UNIQUE
            INDEX_QUALIFIER
            INDEX_NAME
            TYPE
            ORDINAL_POSITION
            COLUMN_NAME
            ASC_OR_DESC
            CARDINALITY
            PAGES
            FILTER_CONDITION
        /
      )
    {
        *{ __PACKAGE__ . "::" . lc($k) } = sub { $_[0]->{$k} };
    }
}


1;
__END__

=encoding utf-8

=head1 NAME

DBIx::Schema::DSL::Dumper - DBIx::Schema::DSL generator

=head1 SYNOPSIS

    use DBIx::Schema::DSL::Dumper;

    print DBIx::Schema::DSL::Dumper->dump(
        dbh => $dbh,
        pkg => 'Foo::DSL',
        default_not_null => 1,
        default_unsigned => 1,
    );


=head1 DESCRIPTION

This module generates the Perl code to generate DBIx::Schema::DSL.

=head1 WARNING

IT'S STILL IN DEVELOPMENT PHASE.
I haven't written document and test script yet.

=head1 SEE ALSO

L<DBIx::Schema::DSL>, L<Teng::Schema::Dumper>

=head1 LICENSE

Copyright (C) Kenta, Kobayashi.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kenta, Kobayashi E<lt>kentafly88@gmail.comE<gt>

=cut

