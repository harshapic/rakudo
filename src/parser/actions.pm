# $Id$
#
# Copyright (C) 2007, The Perl Foundation.

class Perl6::Grammar::Actions ;

method TOP($/) {
    my $past := $( $<statement_block> );
    $past.blocktype('declaration');
    make $past;
}


method statement_block($/, $key) {
    ##  FIXME: $?BLOCK, @?BLOCK
    our $?BLOCK;
    our @?BLOCK;
    ## when creating a block, create an empty first child node (PAST::Stmts)
    ## for special varible initialization and parameter handling. also,
    ## register the special variables in the block's symbol table
    if ($key eq 'open') {
        my $init := PAST::Stmts.new();
        $init.push( PAST::Var.new(:name('$!'), :isdecl(1)));
        $init.push( PAST::Var.new(:name('$/'), :isdecl(1)));
        $init.push( PAST::Var.new(:name('$_'), :isdecl(1)));
        $?BLOCK := PAST::Block.new( PAST::Stmts.new( $init ),
                                    :blocktype('immediate'),
                                    :node($/)
                                  );
        $?BLOCK.symbol( '$!', :scope('lexical') );
        $?BLOCK.symbol( '$/', :scope('lexical') );
        $?BLOCK.symbol( '$_', :scope('lexical') );
        @?BLOCK.unshift($?BLOCK);
    }
    if ($key eq 'close') {
        my $past := @?BLOCK.shift();
        $?BLOCK := @?BLOCK[0];
        $past.push($($<statementlist>));
        make $past;
    }
}


method block($/) {
    make $( $<statement_block> );
}


method statementlist($/) {
    my $past := PAST::Stmts.new( :node($/) );
    for $<statement> {
        $past.push( $($_) );
    }
    make $past;
}


method statement($/, $key) {
    my $past;
    if $key eq 'statement_control' {
        $past := $( $<statement_control> );
    }
    elsif $key eq 'statement_mod_cond' {
        $past := $( $<statement_mod_cond> );
        $past.push( $( $<expr> ) );
    }
    else {
        $past := $( $<expr> );
    }
    make $past;
}


method statement_control($/, $key) {
    make $( $/{$key} );
}


method if_statement($/) {
    my $cond := +$<EXPR> - 1;
    my $past := PAST::Op.new( $( $<EXPR>[$cond] ),
                              $( $<block>[$cond] ),
                              :pasttype('if'),
                              :node( $/ )
                            );
    if ( $<else> ) {
        $past.push( $( $<else>[0] ) );
    }
    while ($cond != 0) {
        $cond := $cond - 1;
        $past := PAST::Op.new( $( $<EXPR>[$cond] ),
                               $( $<block>[$cond] ),
                               $past,
                               :pasttype('if'),
                               :node( $/ )
                             );
    }
    make $past;
}


method unless_statement($/) {
    my $past := PAST::Op.new( $( $<EXPR> ),
                              $( $<block> ),
                              :pasttype('unless'),
                              :node( $/ )
                            );
    make $past;
}


method use_statement($/) {
    make PAST::Stmts.new( :node($/) );
}


method statement_mod_cond($/) {
    make PAST::Op.new( $( $<EXPR> ),
                       :pasttype( ~$<sym> ),
                       :node( $/ )
                     );
}


method statement_prefix($/) {
    my $past := $($<statement>);
    my $sym := ~$<sym>;
    if ($sym eq 'do') {
        # fall through, just use the statement itself
    }
    ## after the code in the try block is executed, bind $! to Undef,
    ## and set up the code to catch an exception, in case one is thrown
    elsif ($sym eq 'try') {
        ##  Set up code to execute <statement> as a try node, and
        ##  set $! to Undef if successful.
        my $exitpir  := "    new %r, 'Undef'\n    store_lex '$!', %r";
        my $try := PAST::Stmts.new( $past ,
                                    PAST::Op.new( :inline( $exitpir ) ) );
        $past := PAST::Op.new( $try, :pasttype('try') );

        ##  Add a catch node to the try op that captures the
        ##  exception object into $!.
        my $catchpir := "    .get_results (%r, $S0)\n    store_lex '$!', %r";
        $past.push( PAST::Op.new( :inline( $catchpir ) ) );
    }
    elsif ($sym eq 'gather') {
        $/.panic($sym ~ ' not implemented');
    }
    elsif ($sym eq  'contend') {
        $/.panic($sym ~ ' not implemented');
    }
    elsif ($sym eq 'async') {
        $/.panic($sym ~ ' not implemented');
    }
    elsif ($sym eq 'lazy') {
        $/.panic($sym ~ ' not implemented');
    }
    make $past;
}


method routine_declarator($/, $key) {
    if ($key eq 'sub') {
        my $past := $($<routine_def>);
        $past.blocktype('declaration');
        $past.node($/);
        make $past;
    }
}


method routine_def($/) {
    my $past := $($<block>);
    my $params := $past[0];
    if $<ident> {
        $past.name( ~$<ident>[0] );
    }
    if ($<multisig>) {
        for $<multisig>[0]<signature>[0] {
            my $param_var := $($_<param_var>);
            $past.symbol($param_var.name(), :scope('lexical'));
            $params.push($param_var);
        }
    }
    make $past;
}


method param_var($/) {
    make PAST::Var.new( :name(~$/),
                        :scope('parameter'),
                        :node($/) 
                      );
}


method special_variable($/) {
    make PAST::Var.new( :node($/), :name(~$/), :scope('lexical') );
}


method term($/, $key) {
    my $past := $( $/{$key} );
    if $<postfix> {
        for $<postfix> {
            my $term := $past;
            $past := $($_);
            $past.unshift($term);
        }
    }
    make $past;
}

method postfix($/, $key) {
    make $( $/{$key} );
}

method methodop($/, $key) {
    my $past;
    if ($key eq 'null') {
        $past := PAST::Op.new();
    }
    else {
        $past := $( $/{$key} );
    }
    $past.name(~$<ident>);
    $past.pasttype('callmethod');
    $past.node($/);
    make $past;
}

method postcircumfix($/, $key) {
    my $semilist := $( $<semilist> );
    my $past := PAST::Var.new( $semilist[0],
                               :scope('keyed'),
                               :vivibase('List'),
                               :viviself('Undef'),
                               :node( $/ )
                             );
    make $past;
}


method noun($/, $key) {
    make $( $/{$key} );
}

method scope_declarator($/) {
    my $past := $( $<variable> );
    my $name := $past.name();
    our $?BLOCK;
    unless $?BLOCK.symbol($name) {
        $past.isdecl(1);
        my $scope := 'lexical';
        if (~$<declarator> eq 'our') { $scope := 'package'; }
        $?BLOCK.symbol($name, :scope($scope));
    }
    make $past;
}


method variable($/, $key) {
    my $viviself := 'Undef';
    if (~$<sigil> eq '@') { $viviself := 'List'; }
    make PAST::Var.new( :node($/), :name( ~$/ ), :viviself($viviself) );
}


method circumfix($/, $key) {
    my $past;
    if ($key eq '( )') {
        $past := $( $<statementlist> );
    }
    if ($key eq '[ ]') {
        $past := $( $<statementlist> );
    }
    elsif ($key eq '{ }') {
        $past := $( $<block> );
    }
    make $past;
}


method value($/, $key) {
    make $( $/{$key} );
}


method number($/, $key) {
    make $( $/{$key} );
}


##  for a variety of reasons, this is easier in PIR than NQP for now.
##  NQP doesn't have assign yet, and Perl6Str is lighter-weight than Str.
method integer($/) {
    my $str;
    PIR q<  $P0 = find_lex '$/'   >;
    PIR q<  $S0 = $P0             >;
    PIR q<  $P1 = new 'Perl6Str'  >;
    PIR q<  assign $P1, $S0       >;
    PIR q<  store_lex '$str', $P1 >;
    make PAST::Val.new( :value( +$str ),
                        :returns('Integer'),
                        :node( $/ )
                      );
}


method quote($/) {
    make $( $<quote_expression> );
}


method quote_expression($/) {
    my $past;
    if ( +$<quote_concat> == 1 ) {
        $past := $( $<quote_concat>[0] );
    }
    else {
        $past := PAST::Op.new( :name('list'),
                               :pasttype('call'),
                               :node( $/ ) );
        for $<quote_concat> {
            $past.push( $($_) );
        }
    }
    make $past;
}


method quote_concat($/) {
    my $terms := +$<quote_term>;
    my $count := 1;
    my $past := $( $<quote_term>[0] );
    while ($count != $terms) {
        $past := PAST::Op.new( $past,
                               $( $<quote_term>[$count] ),
                               :pirop('n_concat'),
                               :pasttype('pirop')
                             );
        $count := $count + 1;
    }
    make $past;
}


method quote_term($/, $key) {
    my $past;
    if ($key eq 'literal') {
        $past := PAST::Val.new( :value( ~$<quote_literal> ), :node($/) );
    }
    if ($key eq 'variable') {
        $past := $( $<variable> );
    }
    make $past;
}


method subcall($/) {
    my $past := $($<semilist>);
    $past.name( ~$<ident> );
    $past.pasttype('call');
    $past.node($/);
    make $past;
}


method semilist($/) {
    my $past := PAST::Op.new( :node($/) );
    if ($<EXPR>) {
        my $expr := $($<EXPR>[0]);
        if (~$expr.name() eq 'infix:,') {
            for @($expr) {
                $past.push( $_ );
            }
        }
        else {
            $past.push( $expr );
        }
    }
    make $past;
}


method listop($/, $key) {
    my $past;
    if ($key eq 'arglist') {
        $past := $( $<arglist> );
    }
    if ($key eq 'noarg') {
        $past := PAST::Op.new( );
    }
    $past.name( ~$<sym> );
    $past.pasttype('call');
    $past.node($/);
    make $past;
}


method arglist($/) {
    my $past := PAST::Op.new( :node($/) );
    my $expr := $($<EXPR>);
    if (~$expr.name() eq 'infix:,') {
        for @($expr) {
            $past.push( $_ );
        }
    }
    else {
        $past.push( $expr );
    }
    make $past;
}


method EXPR($/, $key) {
    if ($key eq 'end') {
        make $($<expr>);
    }
    else {
        my $past := PAST::Op.new( :name($<type>),
                                  :pasttype($<top><pasttype>),
                                  :pirop($<top><pirop>),
                                  :lvalue($<top><lvalue>),
                                  :node($/)
                                );
        for @($/) {
            $past.push( $($_) );
        }
        make $past;
    }
}


# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4: