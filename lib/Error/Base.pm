package Error::Base;
#=========# MODULE USAGE
#~ use Error::Base;               # Simple structured errors with full backtrace
#~ 

use 5.008008;
use strict;
use warnings;
use version 0.94; our $VERSION = qv('0.0.3');

# Core modules
use overload                    # Overload Perl operations
    '""'    => \&_stringify,
    ;
use Scalar::Util;               # General-utility scalar subroutines

# CPAN modules

# Alternate uses
#~ use Devel::Comments '#####', ({ -file => 'debug.log' });                 #~

## use
#============================================================================#

# Pseudo-globals

# Compiled regexes
our $QRFALSE      = qr/\A0?\z/            ;
our $QRTRUE       = qr/\A(?!$QRFALSE)/    ;

#----------------------------------------------------------------------------#

#=========# OPERATOR OVERLOADING
#
#   _stringify();     # short
#       
# Purpose   : Overloads stringification.
# Parms     : ____
# Reads     : ____
# Returns   : ____
# Writes    : ____
# Throws    : ____
# See also  : ____
# 
# ____
# 
sub _stringify {
#   my ($self, $other, $swap) = @_;
    my ($self, undef,  undef) = @_;
    
    no warnings 'uninitialized';
    return join qq{\n}, @{ $self->{-lines} }, q{};
}; ## _stringify

#=========# INTERNAL ROUTINE
#
#    @lines      = $self->_trace(               # dump full backtrace
#                    -top      => 2,            # starting stack frame
#                );
#       
# Purpose   : Full backtrace dump.
# Parms     : -top  : integer   : usually set at init-time
# Returns   : ____
# Writes    : $self->{-frames}  : unformatted backtrace
# Throws    : 'excessive backtrace'
# See also  : _fuss(), _paired()
# 
# ____
# 
sub _trace {
    my $self        = shift;
    my %args        = _paired(@_);
    my $i           = defined $args{-top} ? $args{-top} : 1;
    
    my $bottomed    ;
    my @maxlen      = ( 1, 1, 1 );  # starting length of each field
    my @f           = (             # order in which keys will be dumped
        '-sub',
        '-line',
        '-file',
    );
    my $pad         = q{ };         # padding for better formatting
    my $in          ;               # usually 'in '
    
    my @frames      ;               # unformatted AoH
    my @lines       ;               # formatted array of strings
    
    # Get each stack frame.
    while ( not $bottomed ) {
        my $frame           ;
        
        # Get info for current frame.
        ( 
            $frame->{-package}, 
            $frame->{-file}, 
            $frame->{-line}, 
            undef, 
            undef, 
            undef, 
            $frame->{-eval} 
        )                   = caller( $i );
        
        # caller returns this from the "wrong" viewpoint
        ( 
            undef, 
            undef, 
            undef, 
            $frame->{-sub}, 
            undef, 
            undef, 
            undef, 
        )                   = caller( $i + 1 );
        
        # Normal exit from while loop.
        if ( not $frame->{-package} ) {
            $bottomed++;
            last;
        };
        
        # Clean up bottom frame.
        if ( not $frame->{-sub} ) {
            $frame->{-sub}      = q{};
            $frame->{-bottom}   = 1;
        };
        
        # Get maximum length of each field.
        for my $fc ( 0..$#f ) {
            $maxlen[$fc]    = $maxlen[$fc] > length $frame->{$f[$fc]}
                            ? $maxlen[$fc]
                            : length $frame->{$f[$fc]}
                            ;
        };
        
        # Clean up any eval text.
        if ($frame->{-eval}) {
            # fake newlines for hard newlines
            $frame->{-eval}     =~ s/\n/\\n/g;
        };
        push @frames, $frame;
        
        # Safety exit from while loop.
        $i++;
        die 'Error::Base internal error: excessive backtrace: ', $!
            if $i > 99;
#~ last if $i > 9;                                             # DEBUG ONLY #~
        
    }; ## while not bottomed
    
    # Stash unformatted stack frames.
    $self->{-frames}    = \@frames;
    
    # Format each stack frame. 
    for my $frame (@frames) {
        
        # Pad each field to maximum length (found in while)
        for my $fc ( 0..$#f ) {
            my $diff            = $maxlen[$fc] - length $frame->{$f[$fc]};
            $frame->{$f[$fc]}   = $frame->{$f[$fc]} . ($pad x $diff);
        };
        
        # Fix up bottom.
        if ( $frame->{-bottom} ) {
            $frame->{-sub} =~ s/ /_/g;      # all underbars
            $in         = q{___};           # *THREE* underbars
        }
        else {
            $in         = q{in };           # a three-char string
        };
        
        # Format printable line.
        my $line    = qq*$in$frame->{-sub} at line $frame->{-line}*
                    . qq*    [$frame->{-file}]*
                    ;
        
        # Append any eval text.
        if ($frame->{-eval}) {
            # hard newlines so number of frames doesn't change
            $line           = $line
                            . qq{\n}
                            . qq*    string eval: "$frame->{-eval}"*
                            . qq{\n}
                            ;
        };
        
        push @lines, $line;
    }; ## for each frame
    
    return @lines;
}; ## _trace

#=========# CLASS OR OBJECT METHOD
#
#    Error::Base->crash( $text );    # class method; error text required
#    $err->crash;                    # object method
#    $err->crash( $text );           # object method; error text optional
#    $err->crash( -base => $base );  # named argument okay
#    $err->crash( -key  => '42'  );  # expand into -type
#    $err->crash( -foo  => 'bar' );  # set Error::Base options now
#    $err->crash( mybit => 'baz' );  # set your private stuff now
#
# Purpose   : Fatal out of your program's errors
# Parms     : $text     : string    : final   part of error message [odd arg]
#           : -type     : string    : middle  part of error message
#           : -base     : string    : initial part of error message
#           : -top      : integer   : starting backtrace frame
#           : -quiet    : boolean   : TRUE for no backtrace at all
#           : -$"       : string    : local list separator
# Returns   : never
# Throws    : $self     : die will stringify
# See also  : _fuss(), crank(), cuss(), init()
# 
# The first arg is tested to see if it's a class or object reference.
# Then the next test is to see if an odd number of args remain.
#   If so, then the next arg is shifted off and considered -base.
# All remaining args are considered key/value pairs and passed to new().
#   
sub crash{
    my $self    = _fuss(@_);
    
    die $self;
}; ## crash

#=========# INTERNAL FUNCTION
#
# This does all the work for crash(), crank(), and cuss().
# See crash() for more info.
#
sub _fuss {
    my $self        = shift;
    if ( Scalar::Util::blessed $self ) {        # called on existing object
        $self->init(@_);                        # initialize or overwrite
    } 
    else {                                      # called as class method
        $self       = $self->new(@_);
    };
    my $max         = 78;                       # maximum line length
    
    # Optionally expand one of some stored texts.
    if ( defined $self->{-key} ) {
        $self->{-type}  = $self->{ $self->{-key} };
    };
    
##### _fuss() before:
##### $self
    
    # Collect all the texts into one message.
    $self->{-msg}   = $self->_join_local(
                        $self->{-base},
                        $self->{-type},
                        $self->{-pronto},
                    );
    
    
##### _fuss() after:
##### $self
    
    # If still no text in there, finally default.
    if    ( not $self->{-msg}   ) {
        $self->{-msg}   = 'Undefined error.';
    }; 
    
    # Optionally prepend some stuff.
    my $prepend     = q{};                      # prepended to first line
    my $indent      = q{};                      # prepended to all others
    
    if    ( defined $self->{-prepend} ) {
        $prepend        = $self->{-prepend};
    };
    if    ( defined $self->{-indent} ) {
        $indent         = $self->{-indent};
    };
    if    ( defined $self->{-prepend_all} ) {
        $prepend        = $self->{-prepend_all};
        $indent         = $prepend;
    }
    elsif ( $prepend and !$indent ) {           # construct $indent
        $indent         = ( substr $prepend, 0, 1           )
                        . ( q{ } x ((length $prepend) - 1)  )
                        ;
    }; 
    
    # First line is basic error text.
    my $msg         = $self->_join_local(
                        $prepend,
                        $self->{-msg},
                    );
    
#~     # Do something to control line length and deal with multi-line $msg.
#~     my @temp        = split /\n/, $msg;         # in case it's multi-line
#~     my $limit       = $max - length $prepend;
#~        @temp        = map { s//\n/ if length > $limit } 
#~                         @temp; # avoid excessive line length
#~     my $infix       = qq{\n} . $indent;
#~        $msg         = join $infix, @temp;
    
    $self->{-lines} = [ $msg ];                 # don't push; clear old @lines
    
    # Stack backtrace by default.
    if ( not $self->{-quiet} ) {
        my @trace       = $self->_trace( -top => $self->{-top} );
        push @{ $self->{-lines} }, map { $indent . $_ } @trace;
    };
    
#~     ##### $self
    return $self;
}; ## _fuss

#=========# CLASS OR OBJECT METHOD
#
# Just like crash() except it warn()-s and does not die().
# See crash() for more info.
sub crank{
    my $self    = _fuss(@_);
    
    warn $self;
}; ## crank

#=========# CLASS OR OBJECT METHOD
#
# Just like crash() except it just returns $self (after expansion).
# See crash() for more info.
sub cuss{
    my $self    = _fuss(@_);
    
    return $self;
}; ## crank

#=========# INTERNAL OBJECT METHOD
#
#   $string = $self->_join_local(@_);     # short
#       
# Purpose   : Like builtin join() but with local list separator.
# Parms     : @_        : strings to join
# Reads     : -$"       : like $"   : $self parm    : default q{ }
# Returns   : $string   : joined strings
# Throws    : ____
# See also  : init()
# 
# Buitin join() does not take $" (or anything else) by default; 
#   and in any case $" eq q{} by default. 
# Caller can set $self->{'-$"'} in any method that invokes init(). 
# 
sub _join_local {
    my $self        = shift;
    local $"        = $self->{'-$"'};
    die 'Error::Base internal error: undefined local list separator: ', $!
        if not defined $";
    my @parts       = @_;
    
    
##### _join_local() before:
##### @parts
    
        # Splice out empty strings. 
       @parts       = grep { $_ ne q** } @parts;
    
##### _join_local() after:
##### @parts
    
    
    return join $", @parts;
}; ## _join_local

#=========# INTERNAL FUNCTION
#
#   my %args    = _paired(@_);     # check for unpaired arguments
#       
# Purpose   : ____
# Parms     : ____
# Reads     : ____
# Returns   : ____
# Writes    : ____
# Throws    : ____
# See also  : ____
# 
# ____
#   
sub _paired {
    if ( scalar @_ % 2 ) {  # an odd number modulo 2 is one: true
        die 'Error::Base internal error: unpaired args: ', $!;
    };
    return @_;
}; ## _paired

#=========# CLASS METHOD
#
#   my $obj     = $class->new();
#   my $obj     = $class->new({ -a  => 'x' });
#       
# Purpose   : Object constructor
# Parms     : $class    : Any subclass of this class
#             anything else will be passed to init()
# Returns   : $self
# Invokes   : init()
# 
# Good old-fashioned hashref-based object constructor. 
# 
sub new {
    my $class   = shift;
    my $self    = {};           # always hashref
    
    bless ($self => $class);
    $self->init(@_);            # init remaining args
    
    return $self;
}; ## new

#=========# OBJECT METHOD
#
#   $err->init(        '-key' => $value, '-foo' => $bar );
#   $err->init( $text, '-key' => $value, '-foo' => $bar );
#
# An object can be init()-ed more than once; all new values overwrite the old.
# This non-standard init() allows an unnamed initial arg. 
#
# See: crash()
#
sub init {
    my $self        = shift;
    if ( scalar @_ % 2 ) {              # an odd number modulo 2 is one: true
        $self->{-pronto}    = shift;    # and now it's even
    };
    
    # Merge all values. Newer values always overwrite. 
    %{$self}        = ( %{$self}, @_ );
    
    # Set some default values, mostly to avoid 'uninitialized' warnings.
    if    ( not defined $self->{-base}  ) {
        $self->{-base}  = q{};
    }; 
    if    ( not defined $self->{-type}  ) {
        $self->{-type}  = q{};
    }; 
    if    ( not defined $self->{-pronto}  ) {
        $self->{-pronto}  = q{};
    }; 
    if    ( not defined $self->{-msg}   ) {
        $self->{-msg}   = q{};
    }; 
    if    ( not defined $self->{-top}   ) {
        $self->{-top}   = 2;                # skip frames internal to E::B
    }; 
    if    ( not defined $self->{q'-$"'} ) {
        $self->{q'-$"'} = q{ };             # local list separator
    }; 
        
    return $self;
}; ## init


## END MODULE
1;
#============================================================================#
__END__

=head1 NAME

Error::Base - Simple structured errors with full backtrace

=head1 VERSION

This document describes Error::Base version 0.0.3

=head1 SYNOPSIS

    use Error::Base;
    Error::Base->crash('Sanity check failed');  # die() with backtrace
    
    my $err     = Error::Base->new('Foo');      # construct object first
        yourcodehere(...);                  # ... do other stuff
    $err->crash;                                # as object method
    
    my $err     = Error::Base->new(
                    'Foo error',                # odd arg is error text
                    -quiet    => 1,             # no backtrace
                    grink     => 'grunt',       # store somethings
                    puppy     => 'dog',         # your keys, no leading dash 
                );
    $err->crash;
    
    $err->crank;                    # get cranky: warn() but don't die()
    my $err = Error::Base->crank('Me!');        # also a constructor
    
    eval{ Error::Base->crash( 'car', -foo => 'bar' ) }; 
    my $err     = $@ if $@;         # catch and examine the object
    

=head1 DESCRIPTION

=over

I<J'avais cru plus difficile de mourir.> 
-- Louis XIV

=back

Die early, die often. Make frequent sanity checks and die when a check fails. 
See neat dumps of the caller stack with each error. Construct a group of 
error messages in one object or write error text I<ad hoc>. Trap an error 
object and examine the contents; or let it tell its sad tale and end it. 

Error::Base usage can be simple or complex. For quick sanity checks, 
construct and throw a simple fatal error in one line. At the other extreme, 
you can override methods in your own error subclasses. 

Error::Base is lightweight. It defines no global variables, uses no non-core 
modules (and few of those), exports no symbols, and is purely object-oriented.
I hope you will be able to use it commonly instead of a simple C<die()>. 
You are not required to subclass it. 

=head1 METHODS 

=head2 new()

    my $err     = Error::Base->new('Foo');      # constructor
    my $err     = Error::Base->new(             # with named args
                    -base       => 'Bar error:',
                    -quiet      => 1,
                    -top        => 3,
                    -prepend    => '@! Globalcorpcoapp:',
                    -indent     => '@!                 ',
                    foo         => bar,
                );
    my $err     = Error::Base->new(             # okay to pass both
                        'bartender:'            # lone string...
                    -base   => 'Bar error:',    # ... and named args
                    -type   => 'last call',     # be more specific
                    _beer   => 'out of beer',   # your private attribute(s)
                );

The constructor must be called as a class method; there is no mutator 
returning a new object based on an old one. You do have some freedom in how 
you call, though. 

Called with an even number of args, they are all considered key/value pairs. 
Keys with leading dash (C<'-'>) are reserved for use by Error::Base; 
all others are free to use as you see fit. Error message text is constructed 
as a single string.

Called with an odd number of args, the first arg is shifted off and appended
to the error message text. This shorthand may be offensive to some; in which 
case, don't do that. Instead, pass -base, -type, or both. 

You may stash any arbitrary data inside the returned object (during 
construction or later) and do whatever you like with it. You might choose to 
supply additional optional texts for later access. 

See L<PARAMETERS>.

=head2 crash()

    Error::Base->crash('Sanity check failed');  # as class method
    my $err = Error::Base->crash('Flat tire:'); # also a constructor
    $err->crash;                                # as object method
    $err->crash(        # all the same args are okay in crash() as in new()
                'bartender: '
            -base   => 'Bar error:',
            -key    => '_beer',                 # instert additional text
        );
    eval{ $err->crash }; 
    my $err     = $@ if $@;         # catch and examine the object

C<crash()> and other public methods may be called as class or object methods. 
If called as a class method, then C<new()> is called internally. Call C<new()>
yourself first if you want to call C<crash()> as an object method. 

C<crash()> is a very thin wrapper, easy to subclass. It differs from similar 
methods in that instead of returning its object, it C<die()>-s with it. 
If uncaught, the error will stringify; if caught, the entire object is yours. 

=head2 crank()

    Error::Base->crank('More gruel!');          # as class method
    $err->crank;                                # as object method
    my $err = Error::Base->crank('Me!');        # also a constructor

This is exactly like C<crash()> except that it C<warn()>s instead of 
C<die()>-ing. Therefore it can also usefully be used as a constructor of an 
object for later use. 

C<crank()> is also a very thin wrapper. You may subclass it; you may trap 
the entire object or let it stringify to STDERR.

=head2 cuss()

    my $err = Error::Base->cuss('x%@#*!');      # also a constructor

Again, exactly like C<crash()> or C<crank()> except that it neither 
C<die()>-s nor C<warn()>s; it I<only> returns the object. 

The difference between C<new()> and the other methods is that C<new()> returns 
the constructed object containing only what was passed in as arguments. 
C<crash()>, C<crank()>, and C<cuss()> perform a full stack backtrace 
(if not passed -quiet) and format the result for stringified display.

You may find C<cuss()> useful in testing your subclass or to see how your 
error will be thrown without the bother of actually catching C<crash()>.

=head2 init()

    $err->init(@args);

Probably, it is not useful to call this object method directly. Perhaps you 
might subclass it or call it from within your subclass constructor. 
The calling conventions are exactly the same as for the other public methods. 

C<init()>, is called on a newly constructed object, as is conventional. 
If you call it a second time on an existing object, new C<@args> will 
overwrite previous values. Internally, when called on an existing object,
C<crash()>, C<crank()>, and C<cuss()> each call C<init()>. 

Therefore, the chief distinction between calling as class or object method is 
that if you call new() first then you can separate the definition of your 
error text from the actual throw. 

=head1 PARAMETERS

All public methods accept the same arguments, with the same conventions. 
All parameter names begin with a leading dash (C<'-'>); please choose other 
names for your private keys. 

If the same parameter is set multiple times, the most recent argument 
completely overwrites the previous: 

    my $err     = Error::Base->new( -top    => 3, );
        # -top is now 3
    $err->cuss(  -top    => 0, );
        # -top is now 0
    $err->crank( -top    => 1, );
        # -top is now 1

You are cautioned that deleting keys may be unwise. 

=head2 -base

I<scalar string>

    $err->crash;                        # emits 'Undefined error'
    $err->crash( -base => 'Bar');       # emits 'Bar'

The value of C<< -base >> is printed in the first line of the stringified 
error object after a call to C<crash()>, C<crank()>, or C<cuss()>. 

=head2 -type

I<scalar string>

    $err->crash( 
            -type   => 'last call'
        );                              # emits 'last call'
    $err->crash(
            -base   => 'Bar',
            -type   => 'last call',
        );                              # emits 'Bar last call'
    $err->crash(
            -base   => 'Bar',
            -type   => 'last call',
            zap     => 'tab',
            zing    => 'cash',
            -key    => 'zing',
        );                              # emits 'Bar cash'

This parameter is provided as a way to express a subtype of error. It will be 
overwritten by any value provided indirectly by -key (Please see which.)

=head2 -pronto

I<scalar string>

    $err->crash( 'Pronto!' );           # emits 'Pronto!'
    $err->crash(
                'Pronto!',
            -base   => 'Bar',
            -type   => 'last call',
        );                              # emits 'Bar last call Pronto!'
    $err->crash(
            -base   => 'Bar',
            -type   => 'last call',
            -pronto => 'Pronto!',
        );                              # same thing

As a convenience, if the number of arguments passed in is odd, then the first 
arg is shifted off and appnended to the error message. This is done to 
simplify writing one-off, one-line sanity checks:

    open( my $in_fh, '<', $filename )
        or Error::Base->crash("Couldn't open $filename for reading.");

It is expected that each message argument be a single scalar. If you need 
to pass a multi-line string then please embed escaped newlines (C<'\n'>). 

=head2 -key

I<scalar string>

    my $err     = Error::Base->new(
                    _err00  => 'frobnitz error',
                    _err01  => 'What, me worry?',
                );
    $assertion      or $err->crash( -key => '_err00' );
    $expectation    or $err->crank( -key => '_err01' );

You may store arbitrary error text against arbitrary keys and access them 
later with C<< -key >>. This may suit you if you like to group all your error 
messages in one place; you need only create a single object to hold them all. 
The value of whatever key you pass will be assigned to C<< -type >>. 
The leading underbar (C<'_'>) is merely a suggested convention. 

=head2 -quiet

I<scalar boolean> default: undef

    $err->crash( -quiet         => 1, );        # no backtrace

By default, you get a full stack backtrace. If you want none, set this 
parameter. Only C<< -msg >> will be emitted. 

=head2 -top

I<scalar unsigned integer> default: 2

    $err->crash( -top           => 0, );        # really full backtrace

By default, you get a full stack backtrace: "full" meaning, from the point of
invocation. Some stack frames are added by the process of crash()-ing itself; 
by default, these are not seen. If you want more or fewer frames you may set 
this parameter. 

Beware that future implementations may change the number of stack frames 
added internally by Error::Base; and also you may see a different number of 
frames if you subclass, depending on how you do that. The safe way: 

    my $err     = Error::Base->new('Foo');      # construct object
    $err->{ -top => ($err->{-top})++ };         # drop the first frame
    $err->crash();

This is ugly and you may get a convenience method in future. 

=head2 -prepend

I<scalar string> default: undef

=head2 -indent

I<scalar string> default: first char of -prepend, padded with spaces to length

=head2 -prepend_all

I<scalar string> default: undef

    my $err     = Error::Base->new(
                    -prepend    => '#! Globalcorpcoapp:',
                );
    $err->crash ('Boy Howdy!');
        # emits '@! Globalcorpcoapp: Boy Howdy!
        #        @                   in main::fubar at line 42    [test.pl]'

Any string passed to C<< -prepend >> will be prepended to the first line only 
of the formatted error message. If C<< -indent >> is defined then that will be
prepended to all following lines. If C<< -indent >> is undefined then it will 
be formed from the first character only of C<< -prepend >>, padded with spaces
to the length of C<< -prepend >>. 
C<< -prepend_all >> will be prepended to all lines. 

This is a highly useful feature that improves readability in the middle of a 
dense dump. So in future releases, the default may be changed to form 
C<< -prepend >> in some way for you if not defined. If you are certain you 
want no prepending or indentation, pass the empty string, C<q{}>.

=head2 -$"

I<scalar string> default: q{ }

    my $err     = Error::Base->new(
                    -base   => 'Bar',
                    -type   => 'last call',
                );
    $err->crash(
                'Pronto!',
        );                              # emits 'Bar last call Pronto!'
    $err->crash(
                'Pronto!',
            '-$"'   => '=',
        );                              # emits 'Bar=last call=Pronto!'

If you interpolate an array into a double-quoted literal string, perl will 
join the elements with C<$">. Similarly, if you slow interpolate an array into
an error message part, Error::Base will join the elements with the value of 
C<< $self->{'-$"'} >>. This does not have any effect on the Perlish C<$">. 
Similarly, C<$"> is ignored when Error::Base stirs the pot. 

Also, message parts themselves are joined with C<< $self->{'-$"'} >>. 
The default is a single space. This helps to avoid the unsightly appearance of 
words stuck together because you did not include enough space in your args. 

Note that C<< '-$"' >> is a perfectly acceptable hash key but it must be 
quoted, lest trains derail in Vermont. The fat comma does not help. 

=head1 SLOW INTERPOLATION

Recall that all methods, on init(), pass through all arguments as key/value 
pairs in the error object. Except for those parameters reserved by the class 
API (by convention of leading dash), these are preserved unaltered. 

    my $err     = Error::Base->new(
                    -base   => 'Panic:',
                    -type   => 'lost my $foo.',
                );
    $err->crash(
                'Help!',
            '$foo'  => 'hat',
        );      # emits 'Panic: lost my hat. Help!'
    
    my $err     = Error::Base->new(
                    -base   => 'Sing:',
                    '@favs' => [qw/ schnitzel with noodles /],
                );
    $err->crash(
            -type   => 'My favorite things are @favs.',
        );      # emits 'Sing: My favorite things are schnitzel with noodles.'

If we want to emit an error including information only available within a 
given scope we can interpolate it then and there with a double-quoted literal: 

    open( my $in_fh, '<', $filename )
        or Error::Base->crash("Couldn't open $filename for reading.");

This doesn't work if we want to declare lengthy error text well ahead of time: 

    my $err     = Error::Base->new(
                    -base   => 'Up, Up and Away:',
                    -type   => "FCC wardrobe malfunction of $jackson",
                );
    sub call_ethel {
        my $jackson     = 'Janet';
        $err->crank;
    };                  # won't work the way we might hope

What we need is B<slow interpolation>, which Error::Base provides. 

When we have the desired value in scope, we simply pass it as the value to a key 
matching the I<placeholder> C<$jackson>: 

    my $err     = Error::Base->new(
                    -base   => 'Up, Up and Away:',
                    -type   => 'FCC wardrobe malfunction of $jackson',
                );
    sub call_ethel {
        my $jackson     = 'Janet';
        $err->crank( '$jackson' => $jackson );
    };                  # 'Up, Up and Away: FCC wardrobe malfunction of Janet'

B<Note> that the string passed to C<new()> as the value of C<< -type >> is now 
single quoted, which avoids a futile attempt to interpolate immediately. Also, 
the I<variable> C<$jackson> is passed as the value of the I<key> C<'$jackson'>.
The key is quoted to avoid it being parsed as a variable. 

You may use scalar or array placeholders, signifying them with 
the usual sigils. If you want to slow interpolate an array, you'll have to 
pass an array reference as the value of the corresponding key; this value will 
be dereferenced and joined with the value of C<< $self->{'-$"'} >>, by default 
a single space. Although you pass an aryref, use the array sigil C<@>. 

This is not full-on Perlish interpolation; don't do this: 

    my $err     = Error::Base->new(
                    -base   => 'Trouble:',
                    -type   => 'right here in $cities[$i].',
                );
    $err->crash(
            '@cities'   => [ 'Metropolis', 'River City', 'Gotham City' ],
            '$i'        => 1,
        );          # don't do this; you will not be the Music Man

Maybe someday. 

Do not try a C<< %hash >>, C<< *typeglob >>, or C<< &coderef either >>. 
This is, after all, just a way to print a line or two of text. Also, escapes 
such as C<< "\t" >> are not slow interpolated; you should interpolate them 
conventionally into a scalar (which you can slow interpolate) or just 
interpolate them directly. 

=head1 RESULTS

Soon, I'll write accessor methods for all of these. For now, rough it. 

=head2 -msg

I<scalar string> default: 'Undefined error'

The error message, expanded, without -prepend or backtrace. An empty message 
is not allowed; if none is provided by any means, 'Undefined error' emits. 

=head2 -lines

I<array of strings>

The formatted error message, fully expanded, including backtrace. 

=head2 -frames

I<array of hashrefs>

The raw stack frames used to compose the backtrace. 

=head1 SUBCLASSING

    use base 'Error::Base';
    sub init{
        my $self    = shift;
        _munge_my_args(@_);
        $self->SUPER::init(@_);
        return $self;
    };

While useful standing alone, L<Error::Base> is written to be subclassed, 
if you so desire. Perhaps the most useful method to subclass may be C<init()>.
You might also subclass C<crash()>, C<crank()>, or C<cuss()> if you want to 
do something first: 

    use base 'Error::Base';
    sub crash{
        my $self    = _fuss(@_);
        $self->a_kiss_before_dying();
        die $self;
    };

The author hopes that most users will not be driven to subclassing but if you
do so, successfully or not, please be so kind as to notify. 

=head1 SEE ALSO

Many error-related modules are available on CPAN. Some do bizarre things. 

L<Error> is self-deprecated in its own POD as "black magic"; 
which recommends L<Exception::Class> instead.

L<Exception> installs a C<< $SIG{__DIE__} >> handler that converts text 
passed to C<die> into an exception object. It permits environment variables 
and setting global state; and implements a C<try> syntax. This module may be 
closest in spirit to Error::Base. 
For some reason, I can't persuade C<cpan> to find it. 

L<Carp> is well-known and indeed, does a full backtrace with C<confess()>. 
The better-known C<carp()> may be a bit too clever and in any case, the dump 
is not formatted to my taste. The module is full of global variable settings. 
It's not object-oriented and an error object can't easily be pre-created.  

The pack leader seems to be L<Exception::Class>. Error::Base differs most 
strongly in that it has a shorter learning curve (since it does much less); 
confines itself to error message emission (catching errors is another job); 
and does a full stack backtrace dump by default. Less code may also be 
required for simple tasks. 

To really catch errors, I like L<Test::Trap> ('block eval on steroids'). 
It has a few shortcomings but is extremely powerful. I don't see why its use 
should be confined to testing. 

The line between emitting a message and catching it is blurred in many 
related modules. I did not want a jack-in-the-box object that phoned home if 
it was thrown under a full moon. The only clever part of an Error::Base 
object is that it stringifies. 

It may be true to say that many error modules seem to I<expect> to be caught. 
I usually expect my errors to cause all execution to come to a fatal, 
non-recoverable crash. Oh, yes; I agree it's sometimes needful to catch such 
errors, especially during testing. But if you're regularly throwing and 
catching, the term 'exception' may be appropriate but perhaps not 'error'. 

=head1 INSTALLATION

This module is installed using L<Module::Build>. 

=head1 DIAGNOSTICS

This module emits error messages I<for> you; it is hoped you won't encounter 
any from within itself. 

=over

=item C<< Error::Base internal error: excessive backtrace:  >>

Attempted to capture too many frames of backtrace. 
You probably mis-set C<< -top >>, rational values of which are perhaps C<0..9>.

=item C<< Error::Base internal error: unpaired args:  >>

You do I<not> have to pass paired arguments to most public methods. 
Perhaps you passed an odd number of args to a private method. 

=item C<< Error::Base internal error: undefined local list separator:   >>

C<init()> sets C<< $self->{'-$"'} = q{ } >> by default; you may also set it 
to another value. If you want your message substrings tightly joined, 
set C<< $self->{'-$"'} = q{} >>; don't undefine it. 

=back

=head1 CONFIGURATION AND ENVIRONMENT

Error::Base requires no configuration files or environment variables.

=head1 DEPENDENCIES

There are no non-core dependencies. 

L<version> 0.94                 # Perl extension for Version Objects

L<overload>                     # Overload Perl operations

L<Scalar::Util>                 # General-utility scalar subroutines

This module should work with any version of perl 5.8.8 and up. 

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

This is a very early release. Reports will be warmly welcomed. 

Please report any bugs or feature requests to
C<bug-error-base@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 THANKS

Grateful acknowledgement deserved by AMBRUS for coherent API suggestions. 
Any failure to grasp them is mine. 

=head1 AUTHOR

Xiong Changnian  C<< <xiong@cpan.org> >>

=head1 LICENSE

Copyright (C) 2011 Xiong Changnian C<< <xiong@cpan.org> >>

This library and its contents are released under Artistic License 2.0:

L<http://www.opensource.org/licenses/artistic-license-2.0.php>

=cut
