use v6;

unit module DBDish;
need DBIish::Common;
need DBDish::Connection;
need DBDish::StatementHandle;

role Driver does DBDish::ErrorHandling {
    has $.Version = ::?CLASS.^ver;
    has Lock $!connections-lock .= new;
    has %!connections;

    method connect(*%params --> DBDish::Connection) { ... };

    method !conn-error(:$errstr!, :$code) is hidden-from-backtrace {
        self!error-dispatch: X::DBDish::ConnectionFailed.new(
            :$code, :native-message($errstr), :$.driver-name
        );
    }

    method register-connection($con) {
        $!connections-lock.protect: {
            %!connections{$con.WHICH} = $con
        }
    }

    method unregister-connection($con) {
        $!connections-lock.protect: {
            %!connections{$con.WHICH}:delete
        }
    }

    method Connections() {
        # Return a defensive copy, since %!connections access must be done
        # while holding the lock
        $!connections-lock.protect: { %!connections.clone }
    }
}

role TypeConverterFromDB does Associative {
    has Callable %!Conversions{Mu:U} handles <AT-KEY EXISTS-KEY>;

    # The role implements the conversion
    method convert (::?CLASS:D: $datum, Mu:U $type) {
        with %!Conversions{$type} -> &converter {
            &converter.signature.params.any ~~ .named
                    ?? converter($datum, :$type)
                    !! converter($datum);
        } elsif $type.^name eq 'Any' {
            # Since there is no type specified, fallback to string.
            # This will apply to most user-defined database types such as enums unless they add a special converter
            $datum.defined ?? Str($datum) !! Str(Nil);
        } else { # Common case
            Str.can($type.^name) ?? $type($datum) !! $type.new($datum);
        }
    }

    method STORE(::?CLASS:D: \to_store) {
        for @(to_store) {
            when Callable { %!Conversions{$_.signature.returns} = $_ }
            when Pair { %!Conversions{::($_.key)} = $_.value }
        }
    }
}

role TypeConverterToDB does Associative {
    has Callable %!Conversions{Mu:U} handles <AT-KEY EXISTS-KEY>;

    # The role implements the conversion:
    method convert (::?CLASS:D: Mu $datum --> Str) {
        my Mu:U $type = $datum.WHAT;

        # Normalize Buf. Due to an implementation quirk, Buf != Buf.new(^256)
        # but whateverable can handle it. Convert to a static term for hash lookup purposes.
        $type = Buf if ($type ~~ Buf);

        with %!Conversions{$type} -> &converter {
            converter($datum);
        } else { # Common case. Convert using simple stringification.
            Str($datum);
        }
    }
    method STORE(::?CLASS:D: \to_store) {
        for @(to_store) {
            when Callable {
                my Mu:U $type = $_.signature.params[0].type;
                $type = Buf if ($type ~~ Buf);
                %!Conversions{$type} = $_;
            }
            when Pair { %!Conversions{::($_.key)} = $_.value }
        }
    }
}

=begin pod
=head1 DESCRIPTION
The DBDish module loads the generic code needed by every DBDish driver of the
Perl6 DBIish Database API

It is the base namespace of all drivers related packages, future drivers extensions
and documentation guidelines for DBDish driver implementors.

It is also an experiment in distributing Pod fragments in and around the
code.

=head1 Roles needed by a DBDish's driver

A proper DBDish driver Foo needs to implement at least three classes:

- class DBDish::Foo does DBDish::Driver
- class DBDish::Foo::Connection does DBDish::Connection
- DBDish::Foo::StatementHandle does DBDish::StatementHandle

Those roles are documented below.

=head2 DBDish::Driver

This role define the minimum interface that a driver should provide to be properly
loaded by DBIish.

The minimal declaration of a driver Foo typically start like:

   use v6;
   need DBDish; # Load all roles

   unit class DBDish::Foo does DBDish::Driver;
   ...

- See L<DBDish::ErrorHandling>

- See L<DBDish::Connection>

- See L<DBDish::StatementHandle>

=head2 DBDish::TypeConverter

This role defines the API for dynamic handling of the types of a DB system

=head1 SEE ALSO

The Perl 5 L<DBI::DBD>.

=end pod
