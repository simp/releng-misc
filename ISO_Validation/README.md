# Scripts for validating different parts of the ISO

These are generally items that either don't make sense in the Rake tasks (human
interaction required) or have just been hacked together and may make their way
into `simp-rake-helpers` at some point in the future.

## validate_simp_repo_sigs.rb

A script for validating that the RPMs that are provided by SIMP on the ISO are
valid in accordance with the `simp-gpgkeys` package.
