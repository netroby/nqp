my $OBJ  := 0;
my $INT  := 1;
my $NUM  := 2;
my $STR  := 3;
my $VOID := -1; # Value of this type shouldn't exist
my $CALL_ARG := 5; # Something that will be passed to a sub/method call
my $RETVAL := 8; # Something that will be returned from a sub/method call

my %type_names;
%type_names{$OBJ} := 'OBJ';
%type_names{$INT} := 'INT';
%type_names{$NUM} := 'NUM';
%type_names{$STR} := 'STR';
%type_names{$VOID} := 'VOID';
%type_names{$CALL_ARG} := 'CALL_ARG';
%type_names{$RETVAL} := 'RETVAL';


class TAST {
    has int $!type;
    has $!tree;

    method tree() { $!tree }
    method type() { $!type }

    method new($type, $tree) {
        my $obj := nqp::create(self);
        $obj.BUILD($type, $tree);
        $obj;
    }

    method BUILD($type, $tree) {
        $!type := $type;
        $!tree := $tree;
    }

    method run() {
        nqp::runtruffle($!tree);
    }

    method write_bytecode($output) {
        nqp::tasttobytecode($!tree, $output);
    }

    sub sexpr(int $unquoted, $thing, int $indent = 0) {
      if nqp::islist($thing) {
          my @ret;
          my int $first := 1;
          for $thing -> $element {
              nqp::push(@ret, ($first ?? '' !! nqp::x('  ', $indent+1)) ~ sexpr($first, $element, $indent + 1));
              $first := 0;
          }
          '(' ~ nqp::join("\n", @ret) ~ ')';
      } elsif nqp::isint($thing) {
          ~$thing;
      } elsif nqp::isnum($thing) {
          ~$thing;
      } elsif nqp::isstr($thing) {
          $unquoted ?? $thing !! '"' ~ nqp::escape($thing) ~ '"';
      } else {
          nqp::die("Can't dump: $thing.HOW.name($thing)");
      }
    }

    method dump() {
        sexpr(0, $!tree) ~ "\n";
    }
}

class QAST::OperationsTruffle {
    my %ops;
    my %hll_ops;

    my %inlinable;

    sub add_op($op, $cb, :$inlinable = 1, :$hll) {
        if $hll {
            %hll_ops{$hll} := nqp::hash() unless nqp::existskey(%hll_ops, $hll);
            %hll_ops{$hll}{$op} := $cb;
        } else {
            %ops{$op} := $cb;
        }
        %inlinable{$op} := $inlinable;
    }

    sub add_simple_op($op, $return_type, @argument_types, :$side_effects, :$inlinable = 1, :$decont, :$hll) {
        my @decont;
        if nqp::islist($decont) {
            for $decont -> $index {
                @decont[$index] := 1;
            }
        }
        elsif nqp::defined($decont) {
            @decont[$decont] := 1;
        }


        add_op($op, sub ($comp, $node, :$want) {
            if $node.list > @argument_types {
                nqp::die("{+$node.list} arguments for {$node.op}, the maximum is {+@argument_types}");
            }

            my @ret := [$op];

            my int $i := 0;
            for $node.list -> $arg {
                my $tast := $comp.as_truffle($arg, :want(@argument_types[$i]));
                nqp::push(@ret, @decont[$i] ?? ['decont', $tast.tree] !! $tast.tree);
                $i := $i + 1;
            }

            TAST.new($return_type, @ret);
        }, :$inlinable, :$hll);
    }


    for <while until repeat_while repeat_until> -> $op {
        add_op($op, sub ($comp, $node, :$want) {
            my $label;
            my int $handler := 1;
            my @operands;
            for $node.list {
                if $_.named eq 'nohandler' { $handler := 0; }
                elsif $_.named eq 'label' { $label := $_; }
                else { @operands.push($_) }
            }

            return $comp.NYI("3 argument $op") if +@operands == 3 && $op ne 'while';

            TAST.new($VOID, [
                'while',
                $comp.as_truffle(@operands[0], :want($OBJ)).tree,
                $comp.as_truffle(@operands[1], :want($VOID)).tree
            ]);
        });
    }

    add_simple_op('say', $STR, [$STR], :side_effects);
    add_simple_op('print', $STR, [$STR], :side_effects);

    add_simple_op('null', $OBJ, []);

    add_simple_op('concat', $STR, [$STR, $STR]);

    add_simple_op('lc', $STR, [$STR]);

    add_simple_op('uc', $STR, [$STR]);

    add_simple_op('chars', $INT, [$STR]);

    add_simple_op('tc', $STR, [$STR]);

    add_simple_op('falsey', $INT, [$OBJ]);
    add_simple_op('istrue', $INT, [$OBJ]);

    add_op('stringify', sub ($comp, $node, :$want) {
        $comp.as_truffle($node[0], :want($STR));
    });
    add_op('numify', sub ($comp, $node, :$want) {
        $comp.as_truffle($node[0], :want($NUM));
    });

    for ['_i', $INT, '_n', $NUM, '_s', $STR] -> $suffix, $type {
        for <le lt gt ge eq ne> -> $cmp {
            add_simple_op('is' ~ $cmp ~ $suffix, $INT, [$type, $type]);
        }
    }

    add_simple_op('eqaddr', $INT, [$OBJ, $OBJ]);

    for ['_i', $INT, '', $OBJ, '_s', $STR, '_n', $NUM] -> $suffix, $type {
        my str $op_name := 'list' ~ $suffix;
        add_op($op_name, sub ($comp, $node, :$want) {

           my @tree := [$op_name];

           for $node.list -> $elem {
               my $tast := $comp.as_truffle($elem, :want($type));
               @tree.push($tast.tree);
           }

           TAST.new($OBJ, @tree);
        });

        add_simple_op('atpos' ~ $suffix, $type, [$OBJ, $INT]);
        add_simple_op('bindpos' ~ $suffix, $type, [$OBJ, $INT, $OBJ]);

        add_simple_op('atkey' ~ $suffix, $type, [$OBJ, $STR]);
        add_simple_op('bindkey' ~ $suffix, $type, [$OBJ, $STR, $type], :side_effects);
        add_simple_op('shift' ~ $suffix, $type, [$OBJ]);
    }

    add_simple_op('existskey', $INT, [$OBJ, $STR]);

    add_simple_op('islist', $INT, [$OBJ]);

    add_simple_op('iterator', $OBJ, [$OBJ]);

    add_op('hash', sub ($comp, $node, :$want) {
        my @tree := ['hash'];
        for $node.list -> $key, $val {
            my $key_tast := $comp.as_truffle($key, :want($STR));
            my $val_tast := $comp.as_truffle($val, :want($OBJ));
            @tree.push($key_tast.tree);
            @tree.push($val_tast.tree);
         }
         TAST.new($OBJ, @tree);
    });

    add_simple_op('elems', $INT, [$OBJ]);

    add_simple_op('tclc', $STR, [$STR]);

    for ['_i', $INT, '_n', $NUM] -> $suffix, $type {
        for <add div mod mul sub> -> $math-op {
            add_simple_op($math-op ~ $suffix, $type, [$type, $type]);
        }
    }

    for ['_i', $INT, '_n', $NUM] -> $suffix, $type {
        for <abs neg> -> $math-op {
            add_simple_op($math-op ~ $suffix, $type, [$type]);
        }
    }

    add_simple_op('bitor_i', $INT, [$INT, $INT]);
    add_simple_op('bitand_i', $INT, [$INT, $INT]);
    add_simple_op('bitxor_i', $INT, [$INT, $INT]);

    for <gcd lcm> -> $math-op {
        add_simple_op($math-op ~ '_i', $INT, [$INT, $INT]);
    }

    for <ceil exp floor log sqrt> -> $math-op {
        add_simple_op($math-op ~ '_n', $NUM, [$NUM]);
    }

    for <inf nan neginf> -> $math-op {
        add_simple_op($math-op, $NUM, []);
    }

    add_simple_op('pow_n', $NUM, [$NUM, $NUM]);

    for <asec asin acos atan cos cosh sin sinh sec sech tan tanh> -> $math-op {
        add_simple_op($math-op ~ '_n', $NUM, [$NUM]);
    }

    add_simple_op('atan2_n', $NUM, [$NUM, $NUM]);

    add_simple_op('isnanorinf', $INT, [$NUM]);

    add_simple_op('isinvokable', $INT, [$OBJ]);

    add_simple_op('isnull', $INT, [$OBJ]);
    add_simple_op('ifnull', $OBJ, [$OBJ, $OBJ]);

    add_simple_op('x', $STR, [$STR, $INT]);

    add_simple_op('chr', $STR, [$INT]);
    add_simple_op('codepointfromname', $INT, [$STR]);
    add_simple_op('strfromname', $STR, [$STR]);
    add_simple_op('escape', $STR, [$STR]);
    add_simple_op('flip', $STR, [$STR]);
    add_simple_op('findcclass', $INT, [$INT, $STR, $INT, $INT]);
    add_simple_op('findnotcclass', $INT, [$INT, $STR, $INT, $INT]);
    add_simple_op('iscclass', $INT, [$INT, $STR, $INT]);
    add_simple_op('ordbaseat', $INT, [$STR, $INT]);
    add_simple_op('replace', $STR, [$STR, $INT, $INT, $STR]);
    add_simple_op('codes', $INT, [$STR]);
    add_simple_op('join', $STR, [$STR, $OBJ]);

    add_simple_op('stat', $INT, [$STR, $INT]);
    add_simple_op('lstat', $INT, [$STR, $INT]);
    add_simple_op('stat_time', $NUM, [$STR, $INT]);
    add_simple_op('lstat_time', $NUM, [$STR, $INT]);
    add_simple_op('chdir', $STR, [$STR]);
    add_simple_op('chmod', $INT, [$STR, $INT]);
    add_simple_op('copy', $INT, [$STR, $STR]);
    add_simple_op('cwd', $STR, []);
    add_simple_op('fileexecutable', $INT, [$STR]);
    add_simple_op('fileislink', $INT, [$STR]);
    add_simple_op('filereadable', $INT, [$STR]);
    add_simple_op('filewritable', $INT, [$STR]);
    add_simple_op('link', $INT, [$STR, $STR]);
    add_simple_op('mkdir', $INT, [$STR, $INT]);
    add_simple_op('rename', $INT, [$STR, $STR]);
    add_simple_op('rmdir', $INT, [$STR]);
    add_simple_op('symlink', $INT, [$STR, $STR]);
    add_simple_op('unlink', $INT, [$STR]);

    for <postinc postdec> -> $op {
        add_op($op, sub ($comp, $node, :$want) {
            my $old_value := $comp.as_truffle($node[0], :want($INT));
            my str $action := $op eq 'postinc' ?? 'add_i' !! 'sub_i';
            my $do_action := $comp.as_truffle(
                QAST::Op.new(
                    :op('bind'),
                    $node[0],
                    QAST::Op.new(:op($action),$node[0],QAST::IVal.new(:value(1)))
                ),
                :want($VOID)
            );

            TAST.new($INT, ['old-int-value', $old_value.tree, $do_action.tree]);
       });
    }

    # explicit takeclosure is used by the JVM backend we no-op it.
    add_op('takeclosure', sub ($comp, $node, :$want) {
        $comp.as_truffle($node[0], :want($want));
    });

    # TODO :$want
    add_op('call', :!inlinable, sub ($comp, $node, :$want) {
        my $ret := ['call'];

        my @args := $node.list;

        if $node.name {
            nqp::push($ret, ['get-lexical', $node.name]);
        }
        else {
            nqp::push($ret, $comp.as_truffle(nqp::shift(@args), :want($OBJ)).tree);
        }

        my @names;
        for @args -> $arg {
            @names.push($arg.named ?? $arg.named !! '');
            nqp::push($ret, $comp.as_truffle($arg, :want($CALL_ARG)).tree);
        }
        nqp::splice($ret, [@names], 2, 0);

        TAST.new($OBJ, $ret);
    });

    %ops<callstatic> := %ops<call>;

    add_op('bind', sub ($comp, $node, :$want) {
        my @children := $node.list;
        if +@children != 2 {
            nqp::die("A 'bind' op must have exactly two children");
        }
        unless nqp::istype(@children[0], QAST::Var) {
            nqp::die("First child of a 'bind' op must be a QAST::Var");
        }

        my $*BINDVAL := @children[1];
        $comp.as_truffle(@children[0], :want($want));
    });

    for <if unless> -> $op_name {
        add_op($op_name, sub ($comp, $node, :$want) {
            my int $operands := +$node.list;

            nqp::die("Operation 'if' needs either 2 or 3 operands")
                if $operands < 2 || $operands > 3;

            my int $result_type := $want == $VOID ?? $VOID !! $OBJ;

            my $cond := $comp.as_truffle($node[0], :want($OBJ));
            my $then := $comp.as_truffle($node[1], :want($result_type));

            my @tree := $operands == 3
                  ?? [$op_name ~ '-else', $cond.tree, $then.tree, $comp.as_truffle($node[2], :want($result_type)).tree]
                  !! [$op_name, $cond.tree, $then.tree];

            return TAST.new($result_type, @tree);
        });
    }

    method compile_op($comp, $op, $hll, :$want) {
        my str $name := $op.op;
        if nqp::existskey(%hll_ops, $hll) && nqp::existskey(%hll_ops{$hll}, $name) {
            %hll_ops{$hll}{$name}($comp, $op, :$want);
        }
        elsif nqp::existskey(%ops, $name) {
            %ops{$name}($comp, $op, :$want);
        }
        else {
            $comp.NYI("unimplemented QAST::Op {$op.op}");
        }
    }
}

class QAST::TruffleCompiler {
    my class BlockInfo {
        has $!qast; # The QAST::Block
        has $!outer; # Outer block's BlockInfo
        has @!params; # the parameters the block takes

        method new($qast, $outer) {
            my $obj := nqp::create(self);
            $obj.BUILD($qast, $outer);
            $obj
        }

        method BUILD($qast, $outer) {
            $!qast := $qast;
            $!outer := $outer;
            @!params := nqp::list();
        }

        method add_param($param) {
            @!params.push($param);
        }

        method params() { @!params }
    }

    method compile(QAST::CompUnit $cu) {
        self.as_truffle($cu, :want($VOID));
    }

    my %want_char := nqp::hash($INT, 'I', $NUM, 'N', $STR, 'S', $VOID, 'v');
    sub want($node, $type) {
        my @possibles := nqp::clone($node.list);
        my $best := @possibles.shift;
        return $best unless %want_char{$type};
        my $char := %want_char{$type};
        for @possibles -> $sel, $ast {
            if nqp::index($sel, $char) >= 0 {
                $best := $ast;
            }
        }
        $best
    }

    method coerce(TAST $tast, $desired) {
        my int $got := $tast.type;
        if $got != $desired {
            if $desired == $VOID {
                return TAST.new($VOID, $tast.tree);
            }

            if $desired == $CALL_ARG {
                if $got == $INT {
                    return TAST.new($CALL_ARG, ['int-arg', $tast.tree]);
                }
                elsif $got == $NUM {
                    return TAST.new($CALL_ARG, ['num-arg', $tast.tree]);
                }
                elsif $got == $STR {
                    return TAST.new($CALL_ARG, ['str-arg', $tast.tree]);
                }
                elsif $got == $OBJ {
                    return TAST.new($CALL_ARG, $tast.tree);
                }
            }

            if $desired == $OBJ {
                if $got == $INT {
                    return TAST.new($OBJ, ['box-nqp-int', $tast.tree]);
                }
                if $got == $STR {
                    return TAST.new($OBJ, ['box-nqp-str', $tast.tree]);
                }
                if $got == $NUM {
                    return TAST.new($OBJ, ['box-nqp-num', $tast.tree]);
                }
                if $got == $VOID {
                    return TAST.new($OBJ, ['coerce-void-to-obj', $tast.tree]);
                }
            }

            if $desired == $RETVAL {
                if $got == $INT {
                    return TAST.new($RETVAL, ['retval-int', $tast.tree]);
                }
                if $got == $STR {
                    return TAST.new($RETVAL, ['retval-str', $tast.tree]);
                }
                if $got == $NUM {
                    return TAST.new($RETVAL, ['retval-num', $tast.tree]);
                }
                elsif $got == $OBJ {
                    return TAST.new($RETVAL, $tast.tree);
                }
            }

            if $desired == $NUM {
                if $got == $INT {
                    return TAST.new($NUM, ['coerce-int-to-num', $tast.tree]);
                }
                if $got == $STR {
                    return TAST.new($NUM, ['coerce-str-to-num', $tast.tree]);
                }
            }

            if $desired == $STR {
                if $got == $INT {
                    return TAST.new($STR, ['coerce-int-to-str', $tast.tree]);
                }
                if $got == $NUM {
                    return TAST.new($STR, ['coerce-num-to-str', $tast.tree]);
                }
            }

            # TODO - Perl 6 proper does it differently than nqp
            if $got == $OBJ {
                if $desired == $STR {
                    return TAST.new($STR, ['smart-stringify', $tast.tree]);
                } elsif $desired == $INT {
                    return TAST.new($INT, ['smart-intify', $tast.tree]);
                } elsif $desired == $NUM {
                    return TAST.new($NUM, ['smart-numify', $tast.tree]);
                }
            }


            say("Can't coerce {%type_names{$got}} to {%type_names{$desired}}");
            $tast;
        } else {
            $tast;
        }
    }

    proto method as_truffle($node, :$want) {
        if nqp::defined($want) {
            if nqp::istype($node, QAST::Want) {
                self.coerce(self.as_truffle(want($node, $want), :$want), $want)
            }
            else {
                self.coerce({*}, $want)
            }
        }
        else {
            nqp::die("Unknown want");
        }
    }

    multi method as_truffle(QAST::CompUnit $node, :$want) {
        my $*HLL := '';
        if $node.hll {
            $*HLL := $node.hll;
        }

        TAST.new($OBJ, ['stmts', self.as_truffle($node[0][1], :want($VOID)).tree, self.as_truffle($node[0][3], :want($OBJ)).tree]);
    }

    multi method as_truffle(QAST::Stmts $node, :$want) {
        my @tree := ['stmts'];
        self.compile_all_the_children($node, $want, @tree);
        TAST.new($want, @tree);
    }

    method compile_params(@params) {
        my @ret;
        my int $index := 0;
        my @known_keys;

        for @params -> $param {
            if $param.slurpy {
                if $param.named {
                    nqp::push(@ret, ["get-{$param.scope}-slurpy-named", $param.name, @known_keys]);
                }
                else {
                    nqp::push(@ret, ["get-{$param.scope}-slurpy-positionals", $param.name, $index]);
                }
            }
            else {
                my $type := $OBJ; # TODO native params
                if $param.named {
                    my @names := nqp::islist($param.named) ?? $param.named !! nqp::list($param.named);
                    for @names -> $name {
                        @known_keys.push($name);
                    }

                    if $param.default {
                        my $default := self.as_truffle($param.default, :want($type)).tree;
                        nqp::push(@ret, [
                            "get-{$param.scope}-optional-named",
                            $param.name,
                            @names,
                            $default]);
                    }
                    else {
                        nqp::push(@ret, [
                            "get-{$param.scope}-required-named",
                             $param.name,
                             @names]);
                    }
                }
                else {
                    nqp::push(@ret, ["get-{$param.scope}-positional", $param.name, $index]);
                    $index := $index + 1;
                }
            }
        }
        @ret;
    }

    method compile_all_the_children($node, $want, @tree, :$result_child) {
        my @stmts := $node.list;

        if $want == $VOID {
            $result_child := -1;
        }
        elsif !nqp::defined($result_child) {
            $result_child := +@stmts - 1;
        }

        my int $i := 0;
        for @stmts -> $stmt {
            my $tast := self.as_truffle(@stmts[$i], :want($i == $result_child ?? $want !! $VOID));
            nqp::push(@tree, $tast.tree);
            $i := $i + 1;
        }
    }

    multi method as_truffle(QAST::Block $node, :$want) {
        my $outer := try $*BLOCK;
        my $block := BlockInfo.new($node, $outer);
        {
            my $*BLOCK := $block;
            my $*BINDVAL := 0;
            my @ret := ['block'];

            self.compile_all_the_children($node, $RETVAL, @ret);

            my @compiled_params := self.compile_params($*BLOCK.params);

            nqp::splice(@ret, @compiled_params, 1, 0);

            TAST.new($OBJ,
                $node.blocktype eq 'immediate' ?? ['call', @ret, []] !! @ret);
        }
    }

    multi method as_truffle(QAST::SVal $node, :$want) {
        TAST.new($STR, ['sval', $node.value]);
    }

    multi method as_truffle(QAST::IVal $node, :$want) {
        TAST.new($INT, ['ival', $node.value]);
    }

    multi method as_truffle(QAST::NVal $node, :$want) {
        TAST.new($NUM, ['nval', $node.value]);
    }

    # TODO native types for variables
    multi method as_truffle(QAST::Var $node, :$want) {
        my $action;

        if $node.scope eq 'lexical' || $node.scope eq 'local' {
            my str $scope := $node.scope;
            if $*BINDVAL {
                my $value := self.as_truffle_clear_bindval($*BINDVAL, :want($OBJ));
                $action := ["bind-$scope", $node.name, $value.tree];
            } else {
                $action := ["get-$scope", $node.name];
            }

            if $node.decl eq '' {
                return TAST.new($OBJ, $action);
            }
            # TODO static should do deserialization
            elsif $node.decl eq 'var' || $node.decl eq 'static' {
                return TAST.new($OBJ, ["declare-$scope", $node.name, $action]);
            }
            elsif $node.decl eq 'param' {
                $*BLOCK.add_param($node);
                return TAST.new($OBJ, $action);
            }
            else {
                self.NYI("var declaration type {$node.decl}");
            }
        }
        elsif $node.scope eq 'positional' {
            return self.as_truffle_clear_bindval($*BINDVAL
                ?? QAST::Op.new( :op('bindpos'), $node[0], $node[1], $*BINDVAL)
                !! QAST::Op.new( :op('atpos'), $node[0], $node[1]), :$want);
        }
        elsif $node.scope eq 'associative' {
            return self.as_truffle_clear_bindval($*BINDVAL
                ?? QAST::Op.new( :op('bindkey'), $node[0], $node[1], $*BINDVAL)
                !! QAST::Op.new( :op('atkey'), $node[0], $node[1]), :$want);
        }
        else {
            self.NYI("var scope {$node.scope}");
        }
    }

    multi method as_truffle(QAST::Op $node, :$want) {
        QAST::OperationsTruffle.compile_op(self, $node, $*HLL, :$want);
    }

    method as_truffle_clear_bindval($node, :$want) {
        my $*BINDVAL := 0;
        self.as_truffle($node, :$want);
    }

    multi method as_truffle(QAST::Node $node, :$want) {
        self.NYI('QAST node: ' ~ $node.HOW.name($node));
    }

    # HACK before we deserialize objects
    multi method as_truffle(QAST::WVal $node, :$want) {
        TAST.new($OBJ, ['null']);
    }

    method NYI($msg) {
        nqp::die("NYI: $msg");
    }
}


my $mini_setting := '
sub print(*@args) {
    nqp::print(nqp::join("", @args));
    1;
}
sub say(*@args) {
    nqp::say(nqp::join("", @args));
    1;
}

sub plan($quantity) {
    nqp::say("1..$quantity");
}

sub is($got, $expected) {
    if $got eq $expected {
        nqp::say("ok");
    } else {
        nqp::say("not ok");
    }
}

sub ok($condition) {
    if $condition {
        nqp::say("ok");
    } else {
        nqp::say("not ok");
    }
};
';

class TruffleBackend {
    method start($source, *%adverbs) {
        $mini_setting ~ $source;
    }

    method stages() {
        'tast bytecode truffle'
    }

    method bytecode($tast, *%adverbs) {
        if (%adverbs<target> eq 'bytecode') && %adverbs<output> {
            $tast.write_bytecode(%adverbs<output>);
            nqp::null;
        }
        else {
            $tast;
        }
    }

    method tast($qast, *%adverbs) {
        QAST::TruffleCompiler.compile($qast);
    }

    method truffle($tast, *%adverbs) {
        sub (*@args) {
            $tast.run();
        }
    }

    method is_precomp_stage($stage) {
        0;
    }

    method is_textual_stage($stage) {
        0;
    }

    method apply_transcodings($s, $transcode) {
        $s
    }

    method compunit_mainline($cu) {
        nqp::isinvokable($cu) ?? $cu !! nqp::compunitmainline($cu);
    }

    method compunit_coderefs($cu) {
        nqp::compunitcodes($cu);
    }

    method is_compunit($cuish) {
        !nqp::isnull($cuish) && (nqp::isinvokable($cuish) || nqp::iscompunit($cuish));
    }
}
