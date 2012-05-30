use PPI;
use PPI::Dumper;
use Getopt::Long;
use Pod::Usage;
use Options;
use strict;
use warnings;
our $VERSION=1.6;
our %opts;
sub debug ($) {
    printf STDERR "DEBUG: %s\n", $_[0] if $opts{'verbose'}>0;
}
sub notice ($) {
    printf STDERR "%s\n", $_[0] if $opts{'verbose'}>-1;
}
sub warning ($) {
    printf STDERR "WARN: %s\n",$_[0] if $opts{'verbose'}>-2;
}
sub error ($) {
    if ($opts{'verbose'}>-3 || $^S) {
        die ($^S ? $_[0] : (sprintf "ERR: %s\n",$_[0]));
    }
}
#Getopt::Long::Configure(qw(gnu_getopt));
sub p2u {
    my ($v,$m,@rest)=@_;
    pod2usage(
        -verbose => $v,
        -message => $m,
        -noperldoc => 1,
        @rest
    );
}
%opts=a2h(qw(Xcomment ws Xws Sws Sqw Xeobs Xeolc Xeola));
$opts{'verbose'}=0;
our @_opts=(
    'Xdoc!' => ['Xpod!','Xcomment|Xcom!'],
    'Xend!',
    'Xdata!',
    'Xour!' => [\'Xpragma!'],
    'Xpragma!',
    'ws|space|whitespace!' => ['Xws|Xspace|Xwhitespace!','Sws|Sspace|Swhitespace!'],
    'Sqw!',
    'Xedelim|Xextra-delimiters!' => ['Xeobs!','Xeobc!','Xeola!'],
    'Sstr|Sstring!',
    'Sfor|Sforeach!',
    'Sderef|Sdereference!',
    'Scall'
);
Options::Get(\%opts,\@_opts,
    'help|h|H|?' => sub {p2u(1)},
    'manual|man' => sub {p2u(2)},
    'version' => sub {p2u(99,'',-sections=>['VERSION','AUTHOR'])},
    'author' => sub {p2u(99,'',-sections=>['AUTHOR'])},
    'verbose|v' => sub {$opts{'verbose'}++;},
    'quiet|q' => sub {$opts{'verbose'}--;},
    'dump',
) || ($opts{'verbose'}>-2 ? p2u(1) : exit 255);
our $d;
while (<>){$d.=$_;}
notice "Parsing...";
our $doc=PPI::Document->new(\$d);
notice "Pruning...";
if (!$doc) {
    error errstr PPI::Document; #Yes, it's weird; otherwise PPI::Document tries to find an 'error' method...
    #error(PPI::Document->errstr())
}
#XXX POD tokens can be present in __DATA__!
if ($opts{'Xpod'}) {
    notice "  POD";
    $doc->prune('PPI::Token::Pod');
}
if ($opts{'Xcomment'}) {
    notice "  Comments";
    $doc->prune('PPI::Token::Comment');
}elsif ($opts{'Xws'}){
    notice "  whitespace before comments";
    map {
        if ($_->previous_token()->class() eq 'PPI::Token::Whitespace') {
            $_->previous_token()->remove();
        }
        my $c=$_->content();
        $c=~s/^[ \t]+#/#/ and $_->set_content($c);
    }@{$doc->find('PPI::Token::Comment')};
}
if ($opts{'Xend'}) {
    notice "  __END__";
    $doc->prune('PPI::Statement::End');
}
if ($opts{'Xdata'}) {
    notice "  __DATA__";
    $doc->prune('PPI::Statement::Data');
}
if ($opts{'Xour'} or $opts{'Xpragma'}) {
    notice "  our, strict";
    #Get rid of our and use strict;use warnings
    $doc->prune(sub {
        if ($opts{'Xour'} and $_[1]->class() eq 'PPI::Token::Word' and $_[1]->content eq 'our') {
            debug "'$_[1]' removed [our]";
            return 1;
        }
        my %pmods=a2h(qw(strict warnings));
        if ($opts{'Xpragma'} and $_[1]->class() eq 'PPI::Statement::Include' and $pmods{$_[1]->module()}) {
            debug "'$_[1]' removed [our => strict/warnings]";
            return 1;
        }
    });
}
sub a2h { #('list','of','stuff') => ('list' => 1,'of' => 1,'stuff' => 1)
    my (@arr,%hash)=@_;
    $hash{$_}=1 foreach @arr;
    return %hash;
}
my %iops=a2h( #Operators which can be placed directly after words; $var==42 etc
    '=','->','++','--','**','!','~',
    '\\','+','-','=~','!~','*','/',
    '%','.','<<','>>','<','>','<=',
    '>=','==','!=','<=>','~~','|',
    '^','&&','||','=',',','?',':',
    '=>','.=','+=','-=','*=','/='
);
if ($opts{'Xws'}) {
    notice "  whitespace";
    #Attempts to strip as much whitespace as possible
    $doc->prune(sub {
        my $t=$_[1];
        my $tc=$t->class();
        my $n=$t->next_sibling();
        my $nc=$n?$n->class():'';
        my $p=$t->previous_sibling();
        my $pc=$p?$p->class():'';
        my %_words=a2h(qw(if else elsif unless exists map grep defined join)); #Words which can have a $symbol directly after them
        #Tokens which need a whitespace after them
        my %bpo=a2h('PPI::Token::Symbol','PPI::Token::Word','PPI::Token::Magic','PPI::Token::Operator','PPI::Token::Regexp::Match','PPI::Token::Regexp::Substitute','PPI::Token::Regexp::Transliterate');
        #Tokens which need a whitespace before them
        my %npo=a2h('PPI::Token::Word','PPI::Token::Operator');
        return 1 if $tc eq 'PPI::Token::Whitespace' and (
            ($nc eq 'PPI::Token::Whitespace') or #Unlikely
            ($t->next_token() && $t->next_token()->class() eq 'PPI::Token::Whitespace') or #>_< just in case...
            ($t->previous_token() && $t->previous_token()->isa('PPI::Token::Structure')) or #Semicolons, blocks etc
            ($nc eq 'PPI::Structure::Block' || $pc eq 'PPI::Structure::Block') or #Whitespace around {} blocks
            ($pc eq 'PPI::Structure::List' || $nc eq 'PPI::Structure::List') or #Whitespace around () lists
            ($pc eq 'PPI::Structure::Constructor' || $nc eq 'PPI::Structure::Constructor') or #Whitespace around [] and {}
            ($pc eq 'PPI::Structure::Condition' || $nc eq 'PPI::Structure::Condition') or #Whitespace around if () conditions
            ($pc eq 'PPI::Token::Operator' and ((!$npo{$nc}) or $iops{$p})) or #Operator, whitespace, Operator-or-non-word
            ($t->previous_token() && $t->previous_token()->class() eq 'PPI::Token::Operator' and ((!$npo{$nc}) or $iops{$t->previous_token()})) or #Ditto
            ($nc eq 'PPI::Token::Operator' and ((!($bpo{$pc} or $bpo{$t->previous_token()->class()})) or $iops{$n->content()})) or #Ditto, in reverse
            ($pc eq 'PPI::Token::Word' and (1 or $_words{$p->content()}) and ($nc eq 'PPI::Token::Regexp::Match' or $nc eq 'PPI::Token::Cast' or $nc eq 'PPI::Token::Symbol' or $n->isa('PPI::Structure'))) or #word, symbol-or-structure
            ($t->next_token() && $t->next_token()->class() eq 'PPI::Token::Structure' and $t->next_token() eq ')') or #whitespace at the end of a () list
            ($pc eq 'PPI::Token::Label') # LABEL:
            );
        #return 1 if $tc eq 'PPI::Token::Structure' and $t eq ';' and $t->next_token() and $t->next_token()->class() eq 'PPI::Token::Structure' and $t->next_token() eq '}';
        #return 1 if $tc eq 'PPI::Token::Operator' and $t eq ',' and $t->next_token() eq ')';
        })
};
if ($opts{'Sws'}) {
    notice "  shorten ws";
    map {$_->set_content(' ')} @{$doc->find('PPI::Token::Whitespace') || []};
}
if ($opts{'Xeobs'}) {
    notice "  end-of-block semicolons";
    map {
        my $t=$_->last_token()->previous_token();
        if ($t && $t->class eq 'PPI::Token::Structure' && $t eq ';') {$t->remove()}
        } @{$doc->find('PPI::Structure::Block') || []};
}
if ($opts{'Xeolc'} || $opts{'Xeola'}) {
    notice "  hanging colons and =>";
    map {
        my $t=$_->last_token()->previous_token();
        if ($t and ($t->class eq 'PPI::Token::Operator' && (($t eq ',' && $opts{'Xeolc'}) || ($t eq '=>' && $opts{'Xeola'}))) || ($t->class eq 'PPI::Token::Whitespace')) {$t->remove()}
        }@{$doc->find(sub {
            my $c=$_[1]->class();$c eq 'PPI::Structure::Constructor' or $c eq 'PPI::Structure::List';
            }) || []};
}
if ($opts{'Sqw'}) {
    notice "  qw()";
    #Squeeze qw() as much as possible
    map {
        my $c=$_->content();
        $c=~/^qw\s*([^ ]).*?(.)$/;
        my $usespc=0;
        my ($da,$db)=($1,$2);
        if ($da=~/[a-zA-Z]/) {$usespc=1;};
        $_->set_content('qw'.($usespc?' ':'').$da.(join ' ',$_->literal).$db);
    }@{$doc->find('PPI::Token::QuoteLike::Words') || []};
}
if ($opts{'Sstr'}) {
    notice "  (safely) shorten strings";
    map {
        my ($spc,$da,$c,$db,$qq);
        if ($_->isa('PPI::Token::Quote::Double')) {
            /^"(.*)"$/;
            $c=$1;
        }else{
            $c=~/^qq( ?)(.)(.*)(.)$/;
            ($spc,$da,$c,$db)=($1,$2,$3,$4);
            $qq=1;
        }
        if ($c=~/\\n/) {
            my @parts=split //,$c;
            $c='';
            my $esc=0;
            foreach (@parts) {
                if ($_ eq '\\') {
                    if ($esc) {$esc=0;$c.='\\'.$_;}
                    else {$esc=1;}
                }elsif ($esc) {
                    if ($_ eq 'n') {
                        $c.="\n";
                    }elsif ($_ eq 't') {
                        debug "tab replaced!";
                        $c.="\t";
                    }else{
                        $c.='\\'.$_;
                    }
                    $esc=0;
                }else{
                    $c.=$_;
                }
            }
        }
        if (!$qq) {
            $_->set_content('"'.$c.'"');
            #$_->simplify();
        }else{
            $_->set_content('qq'.$spc.$da.$c.$db);
        }
    }@{$doc->find(sub {my $c=$_[1]->class();$c eq 'PPI::Token::Quote::Double' || $c eq 'PPI::Token::Quote::Interpolate'}) || []}
}
if ($opts{'Sfor'}) {
    notice '  replace foreach with for';
    map {
        if ($_->first_token() eq 'foreach') {
            $_->first_token()->set_content('for');
        }
    } @{$doc->find('PPI::Statement::Compound') || []};
}
if ($opts{'Sderef'}) {
    notice '  shorten $x->{\'y\'} and $x->[2]';
    map {
        my $p=$_->previous_token();
        my $pp=$p->previous_token();
        if ($p->class() eq 'PPI::Token::Operator' and $p eq '->' and
          $pp->class() eq 'PPI::Token::Symbol')
            {
            $pp->insert_before(PPI::Token::Cast->new('$'));
            $p->remove();
            }
    } @{$doc->find('PPI::Structure::Subscript') || []};
    notice '  shorten %{$var}';
    map {
        my $n=$_->next_sibling();
        if ($n->class() eq 'PPI::Structure::Block') {
            my @c=$n->children();
            if (scalar(@c)==1 and $c[0]->class() eq 'PPI::Statement') {
                my @sc=$c[0]->children();
                if (scalar(@sc)==1 and $sc[0]->class() eq 'PPI::Token::Symbol') {
                    $_->insert_after(new PPI::Token::Symbol($sc[0]));
                    $n->remove();
                }
            }
        }
    } @{$doc->find('PPI::Token::Cast') || []};
}
#sub_routine() -> sub_routine
#$obj->method() -> $obj->method
if ($opts{'Scall'}) {
    map {
        my $t=$_;
        my $n=$_->snext_sibling();
        my $nc=$n?$n->class():'';
        if ($nc eq 'PPI::Structure::List') {
            my @c=$n->schildren();
            if (scalar(@c)==0) {
                my $nn=$n->next_token();
                my $nnc=$n?$n->class():'';
                my %ok=a2h(qw(PPI::Token::Structure PPI::Token::Whitespace PPI::Token::Symbol));
                if ($ok{$nnc} || ($nnc eq 'PPI::Token::Operator' and $iops{$nn->content()})) {$n->remove()}
            }
        }
    } @{$doc->find('PPI::Token::Word') || []}
}
#Trailing ; and whitespace
{my $lt;do {
    $lt=undef;
    $lt=$doc->last_token();
    if (($lt->class() eq 'PPI::Token::Structure' and $lt eq ';')
     or ($opts{'Xws'} and $lt->class() eq 'PPI::Token::Whitespace')) {$lt->remove();} else {$lt=undef};
} while ($lt);
}
#Leading whitespace
my $ft=$doc->first_token();
if ($ft->class() eq 'PPI::Token::Whitespace') {$ft->remove();}
sub d {select STDERR;PPI::Dumper->new($_[0])->print;select STDOUT;}
notice "Reinserting...";
if (!$opts{'Xcomment'} and ($opts{'Xws'} or $opts{'Sws'})) {
    notice "  fix comments";
    map {
        if ($_->content()!~/\n\s*$/) {
            if ($_->next_token()->class() eq 'PPI::Token::Whitespace') {
                $_->next_token()->set_content("\n".$_->next_token()->content()) if $_->next_token()->content()!~/\n/;
            }else{
                $_->insert_after(PPI::Token::Whitespace->new("\n"));
            }
        }
    }@{$doc->find('PPI::Token::Comment') || []};
}
#print STDERR "Reinserting __END__ and __DATA__...\n";
#$doc->last_token()->insert_after($s_end) if $s_end;
#$doc->last_token()->insert_after($s_data) if $s_data;
if ($opts{'dump'}) {notice "Dumping...";d($doc);}
notice "Serializing...";
my $ser=$doc->serialize();
print "$ser\n";
notice sprintf "Ratio: %3.2f%%\n",(length($ser)/length($d))*100;
__END__
=pod

=head1 NAME

squeeze - compress perl code as much as possible

=head1 SYNOPSIS

perl squeeze.pl [options] [input files]

=head1 VERSION

squeeze.pl 1.6

=head1 OPTIONS

 help                        Show the help
 man                         Show the whole manual page
 verbose|v                   Increases message level; can be used multiple times
 quiet|q                     Decreases message level; can be used multiple times
 dump                        Dumps the PPI parse tree *after* processing
 
 All the following options can be used as no[option] to invert function
 All options starting with X remove something
 All options starting with S shorten something
 Indents show "groups" of options
 
 Xdoc
   Xpod                      =pod
   Xcomment|Xcom             #comments
 Xend                        __END__ sections
 Xdata                       __DATA__ sections
 Xour                        our $variable -> $variable
 Xpragma                     removes use strict/use warnings
 ws|space|whitespace
   Xws|Xspace|Xwhitespace    removes whitespace where possible
   Sws|Sspace|Swhitespace    shortens all whitespace
 Sqw                         shortens qw()
 Xedelim|Xextra-delimiters
   Xeobs                     End-Of-Block semicolons
   Xeolc                     End-Of-List commas
   Xeola                     End-Of-List arrows (=>)
 Sstr|Sstring                replace escape sequences with characters
 Sfor|Sforeach               replace foreach with for
 Sderef|Sdereference         $x->{'y'} => $x{'y'}
                             %{$x} -> %$x
 Scall                       remove empty lists after subroutine calls

=head1 AUTHOR

Gosha Tugai <gosha.tugai@gmail.com>

=cut