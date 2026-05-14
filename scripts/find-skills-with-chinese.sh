#!/usr/bin/env bash
set -euo pipefail

root="${1:-skills}"
min_ratio="${MIN_HAN_RATIO:-0.01}"

export MIN_HAN_RATIO="$min_ratio"

for skill_dir in "$root"/*; do
  [ -d "$skill_dir" ] || continue
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  if perl -e '
    use strict;
    use warnings;

    my $path = shift @ARGV;
    my $min_ratio = $ENV{MIN_HAN_RATIO} // 0.01;

    open my $fh, q{<:encoding(UTF-8)}, $path or exit 1;
    local $/;
    my $text = <$fh> // q{};

    my $han = () = ($text =~ /\p{Han}/g);
    my $nonspace = () = ($text =~ /\S/g);
    my $ratio = $nonspace ? ($han / $nonspace) : 0;

    exit($ratio >= $min_ratio ? 0 : 1);
  ' "$skill_file"; then
    basename "$skill_dir"
  fi
done
