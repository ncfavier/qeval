# qeval

qeval is a toy to safely-ish (beware bugs and hardware limitations) execute malicious/untrusted code.
It's inspired by [shbot](https://github.com/geirha/shbot), but none of the code was taken from there.

There are currently evaluators for

* Ash (from busybox)
* Bash
* Brainfuck
* C (gcc)
* C (tcc)
* C++ (gcc)
* Go
* Guile
* Haskell
* Java (openjdk)
* Kotlin
* Lua
* Nix
* NodeJS
* OCaml
* Perl 5
* PHP
* Python 2
* Python 3
* Qalculate (which doesn't really need the sandboxing)
* Racket
* Ruby
* Rust nightly
* Unlambda

Perl is currently the fastest evaluator, taking 0.16s on my laptop for a simple `print 42`.


### Example usage

```sh
# This may build Linux, QEMU, and will build all evaluators. Use `evaluators.sh` if you're impatient.
$ nix-build --no-out-link . -A all
$ result/bin/sh id
uid=0(root) gid=0 groups=0
```

### With [flakes](https://nixos.wiki/wiki/Flakes)

```sh
# Run an evaluator directly
$ nix run github:ncfavier/qeval#sh id
uid=0(root) gid=0 groups=0
# Build all evaluators
$ nix build github:ncfavier/qeval
```

### Todo

* Disk hotplug to reduce amount of disk suspensions (and be able to mlock the remaining one)
* Make store drives more self-contained (PATH, hooks) so we don't have to use unsafeDiscardContext shenanigans
* More sophisticated control processes
  * Quicker abort when output has reached size limit
  * Report exit status, memory usage (and OOM), other statistics (count syscalls?)
