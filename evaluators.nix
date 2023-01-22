{ pkgs }:
with pkgs;

{
  perl = {
    name = "perl";
    mem = 50;
    aliases = [ "pl" ];
    storeDrives.perl = [ pkgsCross.musl64.perl ];
    preCommand = ''
      perl -e 'print "Hello world!"'
    '';

    command = ''
      perl "$1"
    '';

    testInput = "print \"success\"";
  };

  rust =
    let
      opts = lib.concatStringsSep " " [
        "--color never"
        "-C opt-level=0"
        "-C prefer-dynamic"
        "-C debuginfo=0"
        "-v" "--error-format short"
        "-C codegen-units=1"
      ];
    in {
      name = "rust";
      aliases = [ "rs" ];
      mem = 200;
      storeDrives.rust = [
        (rustChannelOf {
          channel = "nightly";
          date = "2022-10-18";
          sha256 = "fx05J7wYhY4kGPMKhZG+3eIXUGnSm0vdx8jClYJ8vos=";
        }).rust
        gcc
      ];

      preCommand = ''
        echo 'fn main() {}' > /tmp/sample
        rustc ${opts} -o /tmp/sample.out /tmp/sample
        /tmp/sample.out
        rm /tmp/sample /tmp/sample.out
      '';

      command = ''
        mv "$1" /input.raw
        cat > /input <<EOF
          #![allow(unreachable_code, dead_code)]
          fn main() {
            println!("{:?}", {
              $(cat /input.raw)
            })
          }
        EOF
        rustc ${opts} -o /input.out /input && /input.out
      '';

      testInput = "\"success\"";
      testOutput = "\"success\"";
    };

  go = {
    name = "go";
    mem = 125;
    storeDrives.go = [ go ];

    command = ''
      mv "$1" /input.raw
      cat > /input.go <<EOF
        package main
        import "fmt"
        func main() {
          fmt.Println($(cat /input.raw))
        }
      EOF
      go run /input.go
    '';

    testInput = ''"success"'';
  };

  c = {
    name = "c";
    mem = 100;
    aliases = [ "gcc" ];
    storeDrives.gcc = [ gcc ];
    preCommand = ''
      echo 'int main() { return 0; }' > /tmp/sample
      gcc -x c -o /tmp/sample.out /tmp/sample
      /tmp/sample.out
    '';

    command = ''
      mv "$1" /input.raw
      cat - /input.raw > /input <<EOF
        #include <complex.h>
        #include <limits.h>
        #include <math.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
      EOF
      gcc -x c -o /input.out -std=c11 -lm -Wall -Wextra -Wshadow -Wpedantic -pedantic-errors -fsanitize=address,undefined -fdiagnostics-color=never /input && /input.out
    '';

    testInput = ''
      int main() { printf("success\n"); }
    '';
  };

  cpp = {
    name = "cpp";
    mem = 100;
    storeDrives.gcc = [ gcc ];

    command = ''
      mv "$1" /input.raw
      cat > /input <<EOF
        #include <iostream>
        using namespace std;
        int main() {
          $(cat /input.raw)
          return 0;
        }
      EOF
      g++ -x 'c++' -o /input.out -w -fdiagnostics-color=never /input && /input.out
    '';

    testInput = "cout << \"success\" << endl;";
  };

  tcc = {
    name = "tcc";
    mem = 50;
    storeDrives.tcc = [ tinycc ];
    preCommand = ''
      echo 'int main() { return 0; }' > /tmp/sample
      tcc -run /tmp/sample
    '';

    command = ''
      tcc -run "$1" 2>/dev/null
    '';

    testInput = ''
      void main() { printf("success\n"); }
    '';
  };

  java = rec {
    name = "java";
    mem = 150;

    storeDrives.jdk = [ openjdk ];

    preCommand = ''
      cat > /tmp/Main.java <<EOF
        ${testInput}
      EOF
      javac /tmp/Main.java
      cd /tmp && java Main
    '';

    command = ''
      mv "$1" Main.java
      javac Main.java && java Main
    '';

    testInput = ''
      public class Main {
        public static void main(String... args) {
          System.out.println("success");
        }
      }
    '';
  };

  kotlin = rec {
    name = "kotlin";
    mem = 500;
    storeDrives.kotlin = [ kotlin ];

    preCommand = ''
      cat > /tmp/Main.kts <<EOF
        ${testInput}
      EOF
      kotlinc -script /tmp/Main.kts
    '';

    command = ''
      mv "$1" /input.kts
      kotlinc -script /input.kts
    '';

    testInput = ''println("success")'';
  };

  python = {
    name = "python";
    aliases = [ "python3" "py" "py3" ];
    mem = 75;
    storeDrives.python = [ python3 ];
    preCommand = ''
      ${python3}/bin/python3 -c "print(42)"
    '';

    command = ''
      ${python3}/bin/python3 -c 'import sys;exec(compile(open(sys.argv[1]).read(), "input", "single"))' "$1"
    '';

    testInput = "print(\"success\")";
  };

  python2 = {
    name = "python2";
    aliases = [ "py2" ];
    mem = 75;
    storeDrives.python2 = [ python2 ];
    preCommand = ''
      ${python2}/bin/python2 -c "print 42"
    '';

    command = ''
      ${python2}/bin/python2 -c 'import sys;exec(compile(open(sys.argv[1]).read(), "input", "single"))' "$1"
    '';

    testInput = "print \"success\"";
  };

  ruby = {
    name = "ruby";
    aliases = [ "rb" ];
    mem = 100;
    storeDrives.ruby = [ ruby ];

    preCommand = ''
      echo 42 | ruby
    '';

    command = ''
      ruby "$1"
    '';

    testInput = "puts \"success\"";
  };

  sh = {
    name = "bash";
    aliases = [ "shell" "sh" ];
    mem = 60;
    storeDrives.bash = [
      bash coreutils gnused gnugrep gawk file bsdgames tree jq
    ];

    command = ''
      export TZDIR=${pkgs.tzdata}/share/zoneinfo
      bash "$1"
    '';

    testInput = "echo success";
  };

  ash = {
    name = "ash";
    command = ''
      /bin/sh /input
    '';

    testInput = "echo success";
  };

  nodejs = {
    name = "nodejs";
    aliases = [ "node" "js" ];
    mem = 100;
    storeDrives.node = [ nodejs ];

    preCommand = ''
      node -e "console.log(42)"
    '';

    command = ''
      <"$1" node -p | tr -s '\n ' ' '
    '';
    /*
      mv "$1" /input.raw
      cat > /input <<EOF
        function debug(val) {
          return require("util").inspect(val, { depth: 1, colors: false })
            .replace(/\s+/g, ' ')
        }
        console.log(debug($(cat /input.raw)))
      EOF

      node /input
    '';*/

    testInput = "'success'";
    testOutput = "success ";
  };

  lua = {
    name = "lua";
    mem = 50;
    storeDrives.lua = [ lua5_3 ];

    command = ''
      lua "$1"
    '';

    testInput = "print(\"success\")";
  };

  brainfuck = {
    name = "brainfuck";
    aliases = [ "bf" ];
    storeDrives.brainfuck = [
      (runCommand "just-brainfuck" {} ''
        mkdir -p $out/bin
        cp ${haskellPackages.brainfuck}/bin/bf $out/bin/
      '')
    ];

    preCommand = ''
      echo '+[-[<<[+[--->]-[<<<]]]>>>-]>-.---.>..>.<<<<-.<+.>>>>>.>.<<.<-.' > /tmp/sample
      bf < /tmp/sample
    '';

    command = ''
      bf < "$1"
    '';

    testInput = "+[-[<<[+[--->]-[<<<]]]>>>-]>-.---.>..>.<<<<-.<+.>>>>>.>.<<.<-.";
    testOutput = "hello world";
  };

  php = {
    name = "php";
    mem = 100;
    storeDrives.php = [ php ];

    command = ''
      php -r "$(cat "$1")"
    '';

    testInput = ''echo "success";'';
  };

  racket = {
    name = "racket";
    aliases = [ "rkt" "r" ];
    mem = 200;
    storeDrives.racket = [ racket ];

    preCommand = ''
      racket -e '(+ 40 2)'
    '';

    command = ''
      ( echo "#lang racket"
        cat "$1"
      ) | racket /proc/self/fd/0
    '';

    testInput = "(displayln 'success)";
  };

  guile = {
    name = "guile";
    mem = 100;
    storeDrives.guile = [ guile ];

    command = ''
      guile --no-auto-compile -s "$1"
    '';

    testInput = ''(display "success")'';
  };

  haskell = lib.makeOverridable ({ packages ? _: [], init ? "" }: {
    name = "haskell";
    aliases = [ "hask" "hs" "h" ];
    mem = 200;
    storeDrives.ghc = [ (haskellPackages.ghcWithPackages packages) ];

    preCommand = ''
      mkdir -p ~/.ghc
      ln -s ${writeText "ghci.conf" init} ~/.ghc/ghci.conf
      echo '"foo":[]:[]' > /tmp/sample
      ghci -v0 < /tmp/sample
    '';

    command = ''
      ghci -v0 -fdiagnostics-color=never < "$1"
    '';

    testInput = "putStrLn \"success\"";
  }) {};

  ocaml = {
    name = "ocaml";
    mem = 100;
    storeDrives.ocaml = [ ocaml-ng.ocamlPackages_latest.ocaml ];

    preCommand = ''
      ocaml -e 42
    '';

    command = ''
      { cat "$1"; echo ';;'; } | ocaml -no-version -noprompt -color never -I +unix unix.cma | head -n -1
    '';

    testInput = ''"success"'';
    testOutput = ''- : string = "success"'';
  };

  qalculate = {
    name = "qalculate";
    mem = 100;
    aliases = [ "qalc" "calc" "cal" "q" ];
    storeDrives.qalc = [ libqalculate ];

    preCommand = ''
      mkdir /.config
      qalc "42 byte to megabyte"
    '';

    command = ''
      qalc -terse -file "$1"
    '';

    testInput = "\"success\"";
    testOutput = "\"success\"";
  };

  nix = let
    closure = closureInfo { rootPaths = [
      (writeText "dummy" "dummy").drvPath
    ]; };
  in {
    name = "nix";
    mem = 200;
    storeDrives.nix = [ nix ];

    preCommand = ''
      mkdir -p /etc/nix
      cat > /etc/nix/nix.conf << EOF
      experimental-features = nix-command flakes ca-derivations recursive-nix
      sandbox = false
      build-users-group =
      start-id = 0
      substituters =
      EOF

      export NIX_PATH=nixpkgs=${pkgs.path}

      nix-store --load-db < ${closure}/registration

      nix-instantiate --eval -E "42"
    '';

    command = ''
      nix-instantiate --quiet --eval --read-write-mode \
        -E "let pkgs = import <nixpkgs> {}; inherit (pkgs) lib; in $(cat "$1")"
    '';

    testInput = ''
      builtins.readFile (pkgs.writeText "foo" "success")
    '';
    testOutput = ''"success"'';
  };

  unlambda = {
    name = "unlambda";
    mem = 100;
    storeDrives.unlambda = [ haskellPackages.unlambda ];

    preCommand = ''
      printf '`r```````````.H.e.l.l.o. .w.o.r.l.di' | unlambda
    '';

    command = ''
      unlambda < "$1"
    '';

    testInput = ''
      `r```````.s.u.c.c.e.s.si
    '';
  };
}
