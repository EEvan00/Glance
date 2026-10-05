#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader;
my ($library, $mode) = @ARGV;
die "Invalid media bridge arguments\n" unless defined($library) && defined($mode) && ($mode eq 'stream' || $mode eq 'command');
my $handle = DynaLoader::dl_load_file($library, 0) or die "Cannot load media bridge\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "status_trio_media_$mode") or die "Missing media bridge function\n";
DynaLoader::dl_install_xsub('main::run_bridge', $symbol);
run_bridge();
