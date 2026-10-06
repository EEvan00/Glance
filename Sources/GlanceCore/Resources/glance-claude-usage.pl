#!/usr/bin/perl
use strict;
use warnings;
use JSON::PP;
use File::Basename qw(dirname);
use File::Spec;
my $directory = dirname(File::Spec->rel2abs($0));
my $input = do { local $/; <STDIN> } // '';
my $value = eval { decode_json($input) };
if (ref($value) eq 'HASH' && ref($value->{rate_limits}) eq 'HASH') {
    my %limits;
    for my $key (qw(five_hour seven_day)) {
        my $window = $value->{rate_limits}{$key};
        next unless ref($window) eq 'HASH';
        $limits{$key} = { used_percentage => $window->{used_percentage}, resets_at => $window->{resets_at} };
    }
    if (keys %limits) {
        my $temporary = "$directory/claude-usage-$$.tmp";
        if (open my $file, '>', $temporary) {
            chmod 0600, $temporary;
            print $file encode_json({ rate_limits => \%limits, updated_at => time });
            close $file;
            rename $temporary, "$directory/claude-usage.json" or unlink $temporary;
        }
    }
}
my $previous;
if (open my $file, '<', "$directory/claude-statusline-original.json") {
    $previous = eval { local $/; decode_json(<$file>) }; close $file;
}
if (ref($previous) eq 'HASH' && defined $previous->{command} && length $previous->{command}) {
    # Preserve the user's pre-existing status line with the original stdin.
    if (open my $pipe, '|-', '/bin/sh', '-c', $previous->{command}) {
        print $pipe $input; close $pipe;
    }
} else {
    my $name = ref($value) eq 'HASH' ? ($value->{model}{display_name} // 'Claude') : 'Claude';
    print $name;
    for my $key (qw(five_hour seven_day)) {
        my $used = eval { $value->{rate_limits}{$key}{used_percentage} };
        if (defined $used && $used =~ /^\d+(?:\.\d+)?$/ && $used <= 100) {
            printf ' · %s %d%%', $key eq 'five_hour' ? '5h' : '7d', 100 - $used;
        }
    }
}
