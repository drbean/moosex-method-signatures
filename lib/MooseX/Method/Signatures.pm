use strict;
use warnings;

package MooseX::Method::Signatures;

use Sub::Name;
use Scope::Guard;
use Devel::Declare ();
use MooseX::Meta::Signature::Positional;

our $VERSION = '0.01_01';

our ($Declarator, $Offset);

sub import {
    my $caller = caller();

    Devel::Declare->setup_for(
        $caller,
        { method => { const => \&parser } },
    );

    {
        no strict 'refs';
        *{$caller.'::method'} = sub (&) {};
    }
}

sub skip_declarator {
    $Offset += Devel::Declare::toke_move_past_token($Offset);
}

sub skipspace {
    $Offset += Devel::Declare::toke_skipspace($Offset);
}

sub strip_name {
    skipspace;

    if (my $len = Devel::Declare::toke_scan_word($Offset, 1)) {
        my $linestr = Devel::Declare::get_linestr();
        my $name    = substr($linestr, $Offset, $len);
        substr($linestr, $Offset, $len) = '';
        Devel::Declare::set_linestr($linestr);
        return $name;
    }

    return;
}

sub strip_proto {
    skipspace;

    my $linestr = Devel::Declare::get_linestr();
    if (substr($linestr, $Offset, 1) eq '(') {
        my $length = Devel::Declare::toke_scan_str($Offset);
        my $proto  = Devel::Declare::get_lex_stuff();
        Devel::Declare::clear_lex_stuff();
        $linestr = Devel::Declare::get_linestr();
        substr($linestr, $Offset, $length) = '';
        Devel::Declare::set_linestr($linestr);
        return $proto;
    }

    return;
}

sub shadow {
    my $pack = Devel::Declare::get_curstash_name;
    Devel::Declare::shadow_sub("${pack}::${Declarator}", $_[0]);
}

sub parse_proto {
    my ($proto) = @_;
    my ($vars, $param_spec) = (q//) x 2;

    my @elems = split /\s*,\s*/, $proto;
    for my $elem (@elems) {
        my ($type, $var, $default) = $elem =~ /
            ^
            (?:
                ([^\$]+)
                \s+
            )?
            \$([^\s]+)
            (?:
                \s*=\s*
                ([^\s]+)
            )?$
        /x;

        my $required = 1;
        if ($var =~ s/\?$// || defined $default) {
            $required = 0;
        }

        #$param_spec .= "${var} => {";
        $param_spec .= "{";
        $param_spec .= "isa => '${type}'," if defined $type;
        $param_spec .= "required => ${required},";
        $param_spec .= "default => ${default}," if defined $default;
        $param_spec .= "},";

        $vars .= "\$${var},";
    }

    return ($vars, $param_spec);
}

sub make_proto_unwrap {
    my ($proto) = @_;

    my $inject = 'my $self = shift; ';
    if (defined $proto && length $proto) {
        my ($vars, $param_spec) = parse_proto($proto);
        $inject .= "my (${vars}) = MooseX::Meta::Signature::Positional->new(${param_spec})->validate(\@_);";
    }

    print STDERR $inject, "\n";

    return $inject;
}

sub inject_if_block {
    my $inject = shift;

    skipspace;

    my $linestr = Devel::Declare::get_linestr;
    if (substr($linestr, $Offset, 1) eq '{') {
        substr($linestr, $Offset+1, 0) = $inject;
        Devel::Declare::set_linestr($linestr);
    }
}

sub scope_injector_call {
    return ' BEGIN { MooseX::Method::Signatures::inject_scope }; ';
}

sub parser {
    local ($Declarator, $Offset) = @_;

    skip_declarator;

    my $name   = strip_name;
    my $proto  = strip_proto;
    my $inject = make_proto_unwrap($proto);

    if (defined $name) {
        $inject = scope_injector_call().$inject;
    }

    inject_if_block($inject);

    if (defined $name) {
        $name = join('::', Devel::Declare::get_curstash_name(), $name)
            unless ($name =~ /::/);
        shadow(sub (&) { no strict 'refs'; *{$name} = subname $name => shift; });
    }
    else {
        shadow(sub (&) { shift });
    }
}

sub inject_scope {
    $^H |= 0x120000;
    $^H{DD_METHODHANDLERS} = Scope::Guard->new(sub {
        my $linestr = Devel::Declare::get_linestr;
        my $offset  = Devel::Declare::get_linestr_offset;
        substr($linestr, $offset, 0) = ';';
        Devel::Declare::set_linestr($linestr);
    });
}

1;
