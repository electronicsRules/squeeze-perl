package Options;
use 5.006;
use strict;
use warnings;
use Carp;
use Getopt::Long;

our $VERSION = '0.01';

sub Get {
    my ($store,$data,@others)=@_;
    my $key;
    my %opts;
    my @_opts;
    my %check;
    foreach (@$data) {
        if (defined $key && ref $_ eq 'ARRAY') {
            $opts{$key}=$_;
            $check{_clean_name($key)}=$_;
            undef $key;
        }elsif (!ref $_ and !defined $key) {
            $key=$_;
        }elsif (!ref $_ and defined $key) {
            $opts{$key}=1;
            $check{_clean_name($key)}=1;
            $key=$_;
        }else {
            croak "Error in input at element '$_'\n";
        }
    }
    $opts{$key}=1 if defined $key;
    $check{_clean_name($key)}=1 if defined $key;
    foreach my $k (keys %opts) {
        $store->{_clean_name($k)}=0 if not defined $store->{_clean_name($k)};
        if (ref $opts{$k}) {
            push @_opts, $k, sub {Options::_cb(@_,$store,\%check);};
            push @_opts, map {$store->{_clean_name($_)}=0 if not defined $store->{_clean_name($_)};$_} grep {!$check->{_clean_name($_)}} map {ref $_ ? $$_ : $_} @{$opts{$k}};
        }else{
            push @_opts, $k;
        }
    }
    my $r=GetOptions($store,@_opts,@others);
    foreach (keys %{$store}) {
        if (ref $store->{$store}) {
            $data->{$_}=1;
        }
    }
    return $r;
}

sub _cb {
    my ($opt,$val,$data,$other,$int)=@_;
    my $oname=_clean_name($opt);
    $data->{$oname}=$val unless $int;
    if ($val==1) {
        foreach (@{$other->{$oname}}) {
            if (ref $_) {
                $data->{_clean_name($$_)}->{$oname}=1;
                _cb($$_,$val,$data,$other,1);
            }else{
                #$data->{_clean_name($_)}=1;
                _cb($_,$val,$data,$other,0);
            }
        }
    }else{
        foreach (@{$other->{$oname}}) {
            my $n=_clean_name(ref $_ ? $$_ : $_);
            if (ref $_) {
                if (ref $data->{$n} and $data->{$n}->{$oname}) {
                    delete $data->{$n}->{$oname};
                    if (scalar(keys %{$data->{$n}})==0) {
                        #$data->{$n}=0;
                        _cb($$_,$val,$data,$other);
                    }
                }
            }else{
                #$data->{$n}=0;
                _cb($_,$val,$data,$other,0);
            }
        }
    }
}

sub _clean_name {
    my ($name)=@_;
    $name=(split /\|/,$name)[0];
    $name=~s/[!+]|(?:[=:][sif]@?(?:{[0-9,]}))$//;
    return $name;
}
1;