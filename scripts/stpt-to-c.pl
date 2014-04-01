#!/usr/bin/perl

use strict;

my %addr2var;
my %addr2form;
my %seen_var;

print <<END;
#include "c_interface.h"

void test(void) {
END

while (<>) {
    chomp;
    next unless /^STPT/;
    /^STPT (\w+)\((.*)\)( = (.*))?$/ or die "Parse failure: <$_>";
    my($func, $args, $is_out, $out) = ($1, $2, $3, $4);
    my @args = split(/, /, $args);
    my $var;
    my $ret_type;
    my @call_args;
    my $set_form_to_var = 0;
    for my $a (@args) {
	if (exists($addr2var{$a})) {
	    push @call_args, $addr2var{$a};
	} elsif ($a =~ /^0x/) {
	    push @call_args, $a;
	} else {
	    push @call_args, "XXX";
	}
    }
    if ($func eq "vc_createValidityChecker") {
	$var = "vc";
	$ret_type = "VC";
    } elsif ($func eq "vc_bvType") {
	my $size = $args[1];
	$call_args[1] = $size;
	$var = "ty_bv$size";
	$ret_type = "Type";
    } elsif ($func eq "vc_registerErrorHandler") {
	next;
    } elsif ($func eq "vc_setFlags") {
	next;
    } elsif ($func eq "vc_setInterfaceFlags") {
	next;
    } elsif ($func eq "vc_query_with_timeout") {
	next;
    } elsif ($func eq "vc_varExpr") {
	my $name = $args[1];
	$name =~ s/\_\d+$//;
	$call_args[1] = qq'"$name"';
	$var = "var_" . $name;
	$ret_type = "Expr";
	$addr2form{$out} = $name;
    } elsif ($func eq "vc_bvConstExprFromInt" or
	     $func eq "vc_bvConstExprFromLL") {
	my $width = $args[1];
	$call_args[1] = $width;
	my $val = $args[2];
	$call_args[2] = $val;
	$var = "const_" . $val . "_" . $width;
	$ret_type = "Expr";
	my $form;
	if ($width % 4) {
	    $form = sprintf("0b%0${width}b");
	} else {
	    my $hex_digits = $width/4;
	    $form = sprintf("0h%0${hex_digits}x");
	}
	$addr2form{$out} = $form;
    } elsif ($func eq "vc_bvConcatExpr") {
	$var = "e_concat";
	$ret_type = "Expr";
	$addr2form{$out} = "(" . $addr2form{$args[1]} . " @ "
	  . $addr2form{$args[2]} . ")";
    } elsif ($func eq "vc_bvExtract") {
	my $high = $args[2];
	$call_args[2] = $high;
	my $low = $args[3];
	$call_args[3] = $low;
	$var = "e_extract";
	$ret_type = "Expr";
	$addr2form{$out} = $addr2form{$args[1]} . "[$high:$low]";
    } elsif ($func eq "vc_bvSignExtend") {
	my $width = $args[2];
	$call_args[2] = $width;
	$var = "e_sx";
	$ret_type = "Expr";
	$addr2form{$out} = "BVSX($addr2form{$args[1]}, $width)";
    } elsif ($func eq "vc_eqExpr") {
	$var = "e_eq";
	$ret_type = "Expr";
	$addr2form{$out} = "(" . $addr2form{$args[1]} . " = "
	  . $addr2form{$args[2]} . ")";
    } elsif ($func eq "vc_iteExpr") {
	$var = "e_ite";
	$ret_type = "Expr";
	$addr2form{$out} = "IF " . $addr2form{$args[1]} . " THEN "
	  . $addr2form{$args[2]} . " ELSE " . $addr2form{$args[3]} . " ENDIF";
    } elsif ($func eq "vc_boolToBVExpr") {
	$var = "e_boolbv";
	$ret_type = "Expr";
	$addr2form{$out} = "BOOLBV($addr2form{$args[1]})";
    } elsif ($func eq "vc_simplify") {
	$var = "e_simp";
	$ret_type = "Expr";
	#$addr2form{$out} = $addr2form{$args[1]};
	$set_form_to_var = 1;
    } elsif ($func eq "vc_bvAndExpr") {
	$var = "e_bvand";
	$ret_type = "Expr";
	$addr2form{$out} = "(" . $addr2form{$args[1]} . " & "
	  . $addr2form{$args[2]} . ")";
    } elsif ($func eq "vc_bvOrExpr") {
	$var = "e_bvor";
	$ret_type = "Expr";
	$addr2form{$out} = "(" . $addr2form{$args[1]} . " | "
	  . $addr2form{$args[2]} . ")";
    } elsif ($func eq "vc_bvNotExpr") {
	$var = "e_bvnot";
	$ret_type = "Expr";
	$addr2form{$out} = "~$addr2form{$args[1]}";
    } elsif ($func eq "vc_notExpr") {
	$var = "e_not";
	$ret_type = "Expr";
	$addr2form{$out} = "(NOT $addr2form{$args[1]})";
    } elsif ($func eq "vc_getWholeCounterExample") {
	$var = "wce";
	$ret_type = "WholeCounterExample";
    } elsif ($func eq "vc_getTermFromCounterExample") {
	$var = "ce";
	$ret_type = "Expr";
    } elsif ($func eq "vc_getCounterExample") {
	$var = "ce";
	$ret_type = "Expr";
    }

    my $call_args = join(", ", @call_args);
    my $call = "$func($call_args)";
    if ($var) {
	if ($seen_var{$var}++) {
	    $var = $var . "_" . $seen_var{$var};
	}
	$addr2var{$out} = $var;
	if ($set_form_to_var or length($addr2form{$out}) > 200) {
	    $addr2form{$out} = $var;
	} elsif (exists $addr2form{$out}) {
	    print "    /* $var = $addr2form{$out} */\n";
	}
	print "    $ret_type $var = $call;\n";
    } else {
	print "    $call;\n";
    }
}

print <<END;
}

int main(int argc, char **argv) {
    test();
    return 0;
}
END
