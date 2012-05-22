use PPI;
use PPI::Dumper;
our $d;
print STDERR "Reading...\n";
while (<>){$d.=$_;}
print STDERR "Parsing...\n";
our $doc=PPI::Document->new(\$d);
print STDERR "Pruning...\n";
die if not $doc;
#XXX POD tokens can be present in __DATA__!
print STDERR "  POD\n";
$doc->prune('PPI::Token::Pod');
print STDERR "  Comments\n";
$doc->prune('PPI::Token::Comment');
print STDERR "  our, strict\n";
#Get rid of our and use strict;use warnings
$doc->prune(sub {
    return 1 if $_[1]->class() eq 'PPI::Token::Word' and
    $_[1]->content eq 'our';
    my %pmods=a2h(qw(strict warnings));
    return 1 if $_[1]->class() eq 'PPI::Statement::Include' and $pmods{$_[1]->module()};
    });

sub a2h { #('list','of','stuff') => ('list' => 1,'of' => 1,'stuff' => 1)
    my (@arr,%hash)=@_;
    $hash{$_}=1 foreach @arr;
    return %hash;
}
print STDERR "  whitespace\n";
#Attempts to strip as much whitespace as possible
$doc->prune(sub {
    eval {
    my $t=$_[1];
    my $tc=$t->class();
    my $n=$t->next_sibling();
    my $nc=$n?$n->class():undef;
    my $p=$t->previous_sibling();
    my $pc=$p?$p->class():undef;
    my %iops=a2h( #Operators which can be placed directly after words; $var==42 etc
        '=','->','++','--','**','!','~',
        '\\','+','-','=~','!~','*','/',
        '%','.','<<','>>','<','>','<=',
        '>=','==','!=','<=>','~~','|',
        '^','&&','||','=',',','?',':',
        '=>','.=','+=','-=','*=','/='
    );
    #my %_words=a2h(qw(if else elsif unless exists map grep defined join)); #Words which can have a $symbol directly after them
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
        ($pc eq 'PPI::Token::Word' and (1 or $_words{$p->content()}) and ($nc eq 'PPI::Token::Symbol' or $n->isa('PPI::Structure'))) or #word, symbol-or-structure
        ($t->next_token() && $t->next_token()->class() eq 'PPI::Token::Structure' and $t->next_token() eq ')') or #whitespace at the end of a () list
        ($pc eq 'PPI::Token::Label') # LABEL:
        );
    #return 1 if $tc eq 'PPI::Token::Structure' and $t eq ';' and $t->next_token() and $t->next_token()->class() eq 'PPI::Token::Structure' and $t->next_token() eq '}';
    #return 1 if $tc eq 'PPI::Token::Operator' and $t eq ',' and $t->next_token() eq ')';
};#warn $@;
    });
print STDERR "  shorten ws\n";
map {$_->set_content(' ')} @{$doc->find('PPI::Token::Whitespace')};
print STDERR "  end-of-block semicolons\n";
map {
    my $t=$_->last_token()->previous_token();
    if ($t && $t->class eq 'PPI::Token::Structure' && $t eq ';') {$t->remove()}
    } @{$doc->find('PPI::Structure::Block')};
print STDERR "  hanging colons and =>\n";
map {
    my $t=$_->last_token()->previous_token();
    if ($t and ($t->class eq 'PPI::Token::Operator' && ($t eq ',' || $t eq '=>')) || ($t->class eq 'PPI::Token::Whitespace')) {$t->remove()}
    }@{$doc->find(sub {
        my $c=$_[1]->class();$c eq 'PPI::Structure::Constructor' or $c eq 'PPI::Structure::List';
        })};
print STDERR "  quotelikes\n";
#Squeeze qw() as much as possible
map {
    my $c=$_->content();
    $c=~/^qw\s*([^ ]).*?(.)$/;
    my $usespc=0;
    my ($da,$db)=($1,$2);
    if ($da=~/[a-zA-Z]/) {$usespc=1;};
    $_->set_content('qw'.($usespc?' ':'').$da.(join ' ',$_->literal).$db);
    }@{$doc->find('PPI::Token::QuoteLike::Words')};
#Trailing ;
my $lt=$doc->last_token();
if ($lt->class() eq 'PPI::Token::Structure' and $lt eq ';') {$lt->remove();};
#Leading whitespace
my $ft=$doc->first_token();
if ($ft->class() eq 'PPI::Token::Whitespace') {$ft->remove();}
sub d {select STDERR;PPI::Dumper->new($_[0])->print;select STDOUT;}
#print STDERR "Reinserting __END__ and __DATA__...\n";
#$doc->last_token()->insert_after($s_end) if $s_end;
#$doc->last_token()->insert_after($s_data) if $s_data;
print STDERR "Dumping...\n";d($doc);
print STDERR "Serializing...\n";
my $ser=$doc->serialize();
print "$ser\n";
printf STDERR "Ratio: %3i%%\n",(length($ser)/length($d))*100;
=pod
=head1 List of PPI classes, for convenience :P

Element
     Node
        Document
           Document::Fragment
        Statement
           Statement::Package
           Statement::Include
           Statement::Sub
              Statement::Scheduled
           Statement::Compound
           Statement::Break
           Statement::Given
           Statement::When
           Statement::Data
           Statement::End
           Statement::Expression
              Statement::Variable
           Statement::Null
           Statement::UnmatchedBrace
           Statement::Unknown
        Structure
           Structure::Block
           Structure::Subscript
           Structure::Constructor
           Structure::Condition
           Structure::List
           Structure::For
           Structure::Given
           Structure::When
           Structure::Unknown
     Token
        Token::Whitespace
        Token::Comment
        Token::Pod
        Token::Number
           Token::Number::Binary
           Token::Number::Octal
           Token::Number::Hex
           Token::Number::Float
              Token::Number::Exp
           Token::Number::Version
        Token::Word
#        Token::DashedWord - deprecated PPI class, don't worry about it
        Token::Symbol
           Token::Magic
        Token::ArrayIndex
        Token::Operator
        Token::Quote
           Token::Quote::Single
           Token::Quote::Double
           Token::Quote::Literal
           Token::Quote::Interpolate
        Token::QuoteLike
           Token::QuoteLike::Backtick
           Token::QuoteLike::Command
           Token::QuoteLike::Regexp
           Token::QuoteLike::Words
           Token::QuoteLike::Readline
        Token::Regexp
           Token::Regexp::Match
           Token::Regexp::Substitute
           Token::Regexp::Transliterate
        Token::HereDoc
        Token::Cast
        Token::Structure
        Token::Label
        Token::Separator
        Token::Data
        Token::End
        Token::Prototype
        Token::Attribute
        Token::Unknown
=cut