#!/usr/bin/env perl

use strict; use warnings;

# The idea is to support both "policy instance" and "policy component test" builds. A "policy  instance" would be _the_
# policy of a particular organization. In that case, the settings are expected to be found under the `data/orgs`
# directory.
#
# A "policy component test" build simulates a policy build using the component with the expectation that all the work
# is done in the `.build` directory *and* the test executable will stage a settings file that combines all settings
# from any "super" components packages used in the test.
my $SETTINGS_FILE=".build/settings.yaml";
my $SETTINGS_FILE_SRC;
if (-f "./data/orgs/settings.sh") {
	$SETTINGS_FILE_SRC="./data/orgs/settings.sh";
}
else {
	$SETTINGS_FILE_SRC=".build/settings.sh";
}

my $OUT_DIR;
if (scalar(@ARGV) == 1) {
	$OUT_DIR=$ARGV[0];
}
elsif (scalar(@ARGV) > 1) {
	print STDERR "Usage: liq-gen-make [target output directory]\n  Output defaults to 'policy'.\n";
}
else {
	$OUT_DIR='policy'
}

my $sources = `find -L node_modules/\@liquid-labs -path "*/policy-*/policy/*" -name "*.md" -not -path "node_modules/*/node_modules/*" -not -path "*/.yalc/*"`;

my %refs_tracker = ();
my @all = ();

my $common_make = <<'EOF';
BIN := $(shell npm bin)

SETTINGS_CONV := $(BIN)/liq-settings-conv
PROJ_MAPPER := $(BIN)/liq-proj-mapper
REFS_GEN := $(BIN)/liq-refs-gen
TSV_FILTER := $(BIN)/liq-standards-filter-abs
TSV2MD := $(BIN)/liq-tsv2md
GUCCI := $(BIN)/gucci

POLICY_PROJECTS = $(shell find node_modules/@liquid-labs -maxdepth 1 -name "policy-*")
ASSET_DIRS = $(shell find -L node_modules/@liquid-labs -path "*/policy-*/policy/*" -type d -not -path "node_modules/*/node_modules/*" -not -path "*/.yalc/*")

default: all

EOF

$common_make .= <<"EOF";
clean:
	rm -rf .build/* $OUT_DIR/*

.build:
	mkdir -p \$@

# Setup the YAML settings file that the template processor (gucci) consumes. This supports either or both a BASH style
# 'settings.sh' and 'settings.yaml'. TODO: At some point the BASH style settings should probably be deprecated and
# removed.
$SETTINGS_FILE : $SETTINGS_FILE_SRC \$(SETTINGS_CONV) | .build
	\$(SETTINGS_CONV) "\$@" "\$<"

.build/proj-maps.pl : \$(POLICY_PROJECTS) \$(PROJ_MAPPER) | .build
	rm -f "\$@"
	\$(PROJ_MAPPER) "\$@" \$(POLICY_PROJECTS)

EOF

print $common_make;

foreach my $source (split /\n/, $sources) {
  (my $safe_source = $source) =~ s/ /\\ /g;
  my @bits = split(/\/+/, $source);
  my $pivot = 0;
  for (@bits) {
    if (/^@/) { last; }
    $pivot += 1;
  }
  my $project = join("/", @bits[$pivot...$pivot + 1]);
  my $common_path = join("/", @bits[$pivot + 3...$#bits - 1]);
  $common_path ne 'policy' or $common_path = '';
	my $raw_name = $bits[$#bits];
  (my $base_name = $raw_name) =~ s/\.md//;
  (my $safe_name = $base_name) =~ s/ /\\ /g;

	# For each sourch path (which is a merge of the source paths), we generate a 'policy-refs.yaml' file that creates an
  # entry for each of the possible document paths and it's relative position to the current document. (This enables the # use of an absolute reference in the source which is translated into a relative URL in the generated document.)
  #
  # TODO: This check was put in place to fix a bug... it was something like where you had two policy modules with some
  # union in the directory sturcture (e.g., both had `policy/orgs/network`) and it was causing only one component's
  # definition to be written. Looking at the current implementation, I worry that this just changed the race condition.
  # But... maybe it's a valid fix. This code is way to subtle.
  if (!exists($refs_tracker{$common_path})) {
    print ".build/$common_path/policy-refs.yaml : ".'$(ASSET_DIRS) $(REFS_GEN) .build/proj-maps.pl '."$SETTINGS_FILE | .build\n";
    print "\t".'rm -f "$@"'."\n";
    print "\t".'mkdir -p $(dir $@)'."\n";
    print "\t".'$(REFS_GEN) "$@" ./.build/proj-maps.pl "'.${project}.'" "'.${common_path}.'" $(ASSET_DIRS)'."\n";
    print "\t".'cat "$@" '."$SETTINGS_FILE".' > tmp.yaml && mv tmp.yaml "$@"'."\n";
    print "\n";

    $refs_tracker{$common_path} = ".build/${common_path}/policy-refs.yaml";
  }

  (my $items = $source) =~ s/\.md/ - items.tsv/;
  (my $safe_items = $safe_source) =~ s/\.md/\\ -\\ items.tsv/;
  my $tsv = '';
  my $tmpl = '';
  if (-e "$items") {
		my @incs=`grep -E "^# *include +" "$items"`;
		@incs = map {
			chomp;
			/^#\s*include\s+([^\r]+)/; # handle DOS-y files...
			my @res = `find -L ./node_modules/\@liquid-labs/ -path "*/policy-*/*" -path "*/$1.tsv" -not -path "*@*@*"`;
			if (scalar(@res) > 1) { die "Ambiguous include '$1' in '$source' for gen-make. (".join(", ", @res).")"; }
			if (scalar(@res) == 0) { die "Did not find include '$1' in '$source' gen-make."; }
			$res[0] =~ s/ /\\ /g;
			chomp($res[0]);
			$res[0];
		} @incs;
			# s|^#\s*include\s*|node_modules/${project}/policy/|; s/ /\\ /g; chomp($_); "$_.tsv"; } @incs;

    $tsv = ".build/${common_path}/${safe_name}".'\ -\ items.tsv';
    print "$tsv : $safe_items $SETTINGS_FILE_SRC ".join(' ', @incs).' $(TSV_FILTER) | .build'."\n";
    print "\t".'rm -f "$@"'."\n";
    print "\t".'$(TSV_FILTER) --settings="'.$SETTINGS_FILE_SRC.'" "$<" "$@"'."\n";
    print "\n";

    $tmpl = ".build/${common_path}/${safe_name}".'\ -\ items.tmpl';
    print "$tmpl : ".$tsv.' $(TSV2MD) | .build'."\n";
    print "\t".'rm -f "$@"'."\n";
    print "\t".'$(TSV2MD) "$<" "$@"'."\n";
    print "\n";
  }
  else {
    $safe_items = '';
  }

  my $safe_target = "${OUT_DIR}/${common_path}/${safe_name}.md";
  my $refs = $refs_tracker{$common_path};
	my @deps = do "./.build/${common_path}/${raw_name}.deps" or ();
	my $deps_string = '';
	if ($#deps >= 0) {
		my @safe_deps = map { s| |\\ |g; $_; } @deps;
		$deps_string = join(' ', @safe_deps);
	}
  print "$safe_target : $safe_source $tmpl $refs $SETTINGS_FILE $deps_string\n";
  print "\t".'mkdir -p $(shell dirname "$@")'."\n"; # $(dir...) does not play will spaces
  print "\tcat $deps_string $tmpl ".'"$<" | $(GUCCI) --vars-file '.$refs.' -s IS_SUBMIT_AUDIT=0 -s IS_PR_AUDIT=0 > "$@" || { rm "$@"; echo "\nFailed to make\n$@\n"; exit 1; }'."\n";
  print "\n";

  push(@all, $safe_target);
}

my $roles_ref = "${OUT_DIR}".'/Company\ Jobs\ and\ Roles\ Reference.md';
print "${roles_ref}:\n";
print "\t@[[ '\$(STAFF_FILE)' != '' ]] || { echo \"'STAFF_FILE' var not set. Try calling 'STAFF_FILE=/foo/bar make'\"; exit 1; }\n";
print "\t\$(BIN)/liq-gen-roles-ref \$(PWD)/data \$(STAFF_FILE) > \"\$@\"\n";
push(@all, $roles_ref);

print "\nall: ".join(" ", @all);
