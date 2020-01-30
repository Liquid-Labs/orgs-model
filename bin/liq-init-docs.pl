#!/usr/bin/env perl

use strict; use warnings;

if ($#ARGV == -1) { die "Usage:\nliq-init-docs run # to initialize\nand:\nliq-init-docs <file> <data file>"; }

if ($ARGV[0] eq 'run') {
  mkdir('.build');

  my @sources = split(/\n/, `find node_modules/\@liquid-labs -path "*/policy-*/policy/*" -name "*.md" -o -name "*.tmpl" | grep -v '/tmpl/'`); # #TODO: the '/tmpl/' files are from an older layout and will go away'
  open my $fd, ">", ".build/resolve.makefile" or die "Could not create makefile for resolve.";

  my $common_make = <<'EOF';
BIN := $(shell npm bin)

INIT_DOCS := $(BIN)/liq-init-docs
GEN_MAKE := $(BIN)/liq-gen-make

default: .build/main.makefile
EOF
  print $fd "$common_make\n";

  my @targets = ();
  for (@sources) {
    my $safe_name = $_;
    $safe_name =~ s| |\\ |g;
    my $target = $safe_name;
    $target =~ s|[^@]*\@liquid-labs/[^/]+/policy/(.+)|.build/$1.deps|;
    $targets[++$#targets] = $target;
    print $fd "$target : $safe_name\n";
    print $fd "\t".'mkdir -p $(shell dirname "$@")'."\n";
    print $fd "\t".'$(INIT_DOCS) "$<" "$@"'."\n";
    print $fd "\n"
  }

  print $fd ".build/main.makefile : ".join(' ', @targets)."\n";
  print $fd "\t".'$(GEN_MAKE) > "$@"'."\n";
  print $fd "\n";

  print "Initiating resolution build...\n";
  exec 'make -f .build/resolve.makefile --silent';
}

my $file = shift;
my $output = shift;
open(my $fd, "<", $file) or die "Couldn't open input file: $file ($!)";
open(my $out, ">", $output) or die "Couldn't open data file: $output ($!)";
# TODO: we won't necessarily recognize a template spread across multilpe lines...

print $out "(\n";

while (<$fd>) {
  /\{\{-?\s*template\s+"([^"]+)"/ or next;
  my $template = $1;
  $template =~ s/^\s+|\s+$//g;
  # we don't currently support cross-including item lists; only the partner file can do that.
  next if $template =~ /- items$/;

  my $template_path;
  for (split /\n/, `find 'node_modules/\@liquid-labs' -maxdepth 1 -name "policy-*"`) {
    my $candidate = `find "$_" -path "*${template}.tmpl"`;
    chomp($candidate);
    ($candidate && $template_path) and die "Ambiguous template: $template. Found at '$candidate' and '$template_path'.";
    $candidate && ($template_path = $candidate);
  }

  !$template_path and die "Could not find template: $template.";
  print $out "'$template_path',\n";
}
print $out ");\n";

close $fd;
close $out;