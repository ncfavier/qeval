{ pkgs ? import ./nixpkgs.nix
, baseKernelPackages ? pkgs.linuxPackages # tested up to 6.1
, extraKernelConfig ? {}
, qemu ? pkgs.qemu.override {
    guestAgentSupport = false;
    numaSupport = false;
    alsaSupport = false;
    pulseSupport = false;
    jackSupport = false;
    sdlSupport = false;
    gtkSupport = false;
    vncSupport = false;
    smartcardSupport = false;
    spiceSupport = false;
    ncursesSupport = false;
    libiscsiSupport = false;
    tpmSupport = false;

    hostCpuOnly = true;
    seccompSupport = true;
  }
, suspensionUseCompression ? true # set to false if you favour speed at the expense of size
, enableKVM ? true
, timeout ? if enableKVM then 10 else 20
, suspensionTimeout ? if enableKVM then 60 else 120
, dumbTerminal ? false
, editEvaluators ? x: x
}:

with pkgs;
with lib;

rec {
  kconfig = {
    X86 = true;
    "64BIT" = true;
    # PRINTK = true; # extra debugging

    DEFAULT_HOSTNAME = "qeval";

    SWAP = false;

    TTY = true;
    SERIAL_8250 = true;
    SERIAL_8250_CONSOLE = true;
    VT = false;

    # execute elf and #! scripts
    BINFMT_ELF = true;
    BINFMT_SCRIPT = true;

    # enable ramdisk with gzip
    BLK_DEV_INITRD = true;
    RD_GZIP = true;

    # allow for userspace to shut kernel down
    PROC_FS = true;
    MAGIC_SYSRQ = true;

    # needed for guest to tell qemu to shutdown
    PCI = true;
    ACPI = true;

    # allow unix domain sockets
    NET = true;
    UNIX = true;
    WIRELESS = false;

    # enable block layer
    BLOCK = true;
    BLK_DEV = true;
    BLK_DEV_LOOP = true;

    # required by Nix, which wants to acquire the big lock
    FILE_LOCKING = true;

    MISC_FILESYSTEMS = true;
    SQUASHFS = true;
    SQUASHFS_LZ4 = true;
    LZ4_DECOMPRESS = true;
    SQUASHFS_DECOMP_SINGLE = true;
    # SQUASHFS_DECOMP_MULTI = true;
    # SQUASHFS_FILE_DIRECT = true;
    SQUASHFS_FILE_CACHE = true;

    PROC_SYSCTL = true;
    KERNFS = true;
    SYSFS = true;
    DEVTMPFS = true;
    TMPFS = true;

    OVERLAY_FS = true;

    # support passing in various things
    VIRTIO_MENU = true;
    VIRTIO_PCI = true;
    VIRTIO_PCI_LEGACY = false;
    VIRTIO_BLK = true;
    VIRTIO_CONSOLE = true;

    FUTEX = true;

    # enable timers (ghc needs them)
    POSIX_TIMERS = true;
    TIMERFD = true;
    EVENTFD = true;
    EPOLL = true;

    # tsc scaling, maybe
    # "X86_TSC"

    ADVISE_SYSCALLS = true;

    # "FSCACHE"
    # "CACHEFILES"

    # required for guest to gather entropy, some applications
    # will otherwise block forever (e.g. rustc)
    HW_RANDOM = true;
    HW_RANDOM_VIRTIO = true;

    SMP = true;
    HYPERVISOR_GUEST = true;
    KVM_GUEST = true;
    PARAVIRT = true;
    PARAVIRT_SPINLOCKS = true;
  } // extraKernelConfig;

  kernel = linuxKernel.manualConfig rec {
    inherit lib stdenv;
    inherit (baseKernelPackages.kernel) version src;
    modDirVersion = concatStringsSep "." (take 3 (splitVersion version ++ [ "0" "0" ]));
    configfile = kernelConfig.override { linux = baseKernelPackages.kernel; } { config = kconfig; };
    allowImportFromDerivation = false; # not needed
  };

  initrdUtils = runCommand "initrd-utils"
    { buildInputs = [ nukeReferences ];
      allowedReferences = [ "out" ]; # prevent accidents like glibc being included in the initrd
    }
    ''
      mkdir -p $out/bin $out/lib

      # Copy what we need from Glibc.
      cp -p ${glibc}/lib/ld-linux*.so.? $out/lib
      cp -p ${glibc}/lib/libc.so.* $out/lib
      cp -p ${glibc}/lib/libm.so.* $out/lib
      cp -p ${glibc}/lib/libresolv.so.* $out/lib

      # Copy BusyBox.
      cp -pd ${busybox}/bin/* $out/bin

      # Run patchelf to make the programs refer to the copied libraries.
      for i in $out/bin/* $out/lib/*; do if ! test -L $i; then nuke-refs $i; fi; done

      for i in $out/bin/*; do
          if [ -f "$i" -a ! -L "$i" ]; then
              echo "patching $i..."
              patchelf --set-interpreter $out/lib/ld-linux*.so.? --set-rpath $out/lib $i || true
          fi
      done
    '';

  terminfo = runCommand "terminfo" { nativeBuildInputs = [ ncurses ]; } ''
    tic -s -o "$out" ${builtins.toFile "dumb.terminfo" ''
      dumb|dumb terminal, am, cols#80, bel=^G, cr=^M, cud1=^J, ind=^J
    ''}
  '';

  stage1 = writeScript "vm-run-stage1" ''
    #! ${initrdUtils}/bin/ash -e
    export PATH=${initrdUtils}/bin
    echo

    mkdir /etc
    echo -n > /etc/fstab

    mount -t proc none /proc
    mount -t sysfs none /sys

    echo 2 > /proc/sys/vm/panic_on_oom

    for o in $(cat /proc/cmdline); do
      case $o in
        jobDesc=*) jobDesc=''${o#*=} ;;
      esac
    done

    mount -t devtmpfs devtmpfs /dev

    mkdir -p /dev/shm /dev/pts
    mount -t tmpfs -o "mode=1777" none /dev/shm
    mount -t devpts none /dev/pts

    mkdir -p /tmp /run /var
    mount -t tmpfs -o "mode=1777" none /tmp
    mount -t tmpfs -o "mode=755" none /run
    ln -sfn /run /var/run

    mkdir -p /etc
    ln -sf /proc/mounts /etc/mtab
    echo "127.0.0.1 localhost" > /etc/hosts
    echo "root:x:0:0:root:/:/bin/sh" > /etc/passwd
    echo "root:x:0:" > /etc/group
    ${optionalString dumbTerminal ''
    ln -s ${terminfo} /etc/terminfo
    export TERM=dumb NO_COLOR=1
    ''}

    mkdir -p /bin
    ln -s ${initrdUtils}/bin/ash /bin/sh

    for store in /dev/vd*; do
      if [ -e "$store" ]; then
        name=$(basename $store)
        mkdir -p /mnt/store/$name
        mount -o ro,loop /dev/$name /mnt/store/$name
      fi
    done

    stores="$(find /mnt/store -mindepth 1 -maxdepth 1 | paste -sd :)"
    echo "stores: $stores:/nix/store"
    mkdir -p /nix/store /nix/.store-work
    mount -t overlay overlay -o "lowerdir=$stores,upperdir=/nix/store,workdir=/nix/.store-work" /nix/store

    if [ -n "$jobDesc" ]; then
      . "$jobDesc"
    fi

    . "$preCommand"

    # opening the virtio serial port triggers the migration
    { read -r date; read -rd "" input; } < /dev/vport1p1
    date -s "@$date" > /dev/null
    echo "$input" > /input

    . "$command" /input

    exec poweroff -f
  '';

  initrd = initrdPath: makeInitrd {
    contents = [
      { object = stage1;
        symlink = "/init"; }
    ];
  };

  # https://github.com/NixOS/nix/issues/5633
  removeReferences = let
    flip = drv: pkgs.runCommand "flipped-${drv.name}" { inherit drv; } ''
      tr a-z0-9 n-za-m5-90-4 < "$drv" > "$out"
    '';
  in drv: flip (flip drv);

  mkSquashFs = settings: name: contents: removeReferences (stdenv.mkDerivation {
    name = "squashfs-${name}.img";
    nativeBuildInputs = [ squashfsTools ];
    closureInfo = closureInfo { rootPaths = contents; };
    buildCommand = ''
      mksquashfs $(< "$closureInfo"/store-paths) "$out" \
        -keep-as-directory -all-root -b 1048576 ${settings}
    '';
  });

  mkSquashFsXz = mkSquashFs "-comp xz -Xdict-size 100%";
  mkSquashFsLz4 = mkSquashFs "-comp lz4 -Xhc";
  mkSquashFsGz = mkSquashFs "-comp gzip -Xcompression-level 9";

  prepareJob = lib.makeOverridable ({
      name, aliases ? [], initrdPath ? [ initrdUtils ], storeDrives ? {}, mem ? 50, command, preCommand ? "",
      doCheck ? true, testInput ? "", testOutput ? "success", ... }:
    let
      fullPath = (concatLists (builtins.attrValues storeDrives)) ++ initrdPath;

      desc = writeText "desc" ''
        export PATH=${lib.makeBinPath (map builtins.unsafeDiscardStringContext fullPath)}
        command=${writeScript "command" command}
        preCommand=${writeScript "preCommand" preCommand}
      '';
      run' = run {
        inherit name initrdPath mem desc;
        storeDrives = (mapAttrs mkSquashFsLz4 storeDrives) // {
          desc = mkSquashFsLz4 "desc-${name}" [ desc initrdUtils ];
        };
      };

      description = writeText "desc" (builtins.toJSON {
        inherit name aliases mem;
        available = map (p: p.name) fullPath;
      });

      self = stdenv.mkDerivation {
        inherit name aliases;

        src = (writeShellScriptBin "run" ''
          set -e
          PATH=${makeBinPath [ coreutils ]}
          job=$(mktemp -d)
          ${run'}/bin/run-qemu "$job" "$@"
          rm -rf "$job"
        '').overrideAttrs (old: {
          checkPhase = old.checkPhase or "" + ''
            expected=${escapeShellArg testOutput}
            result=$(time "$target" ${escapeShellArg testInput})
            printf '%s\n' "$result"
            if [[ "$result" != "$expected" ]]; then
              echo expected:
              ${xxd}/bin/xxd <<< "$expected"
              echo got:
              ${xxd}/bin/xxd <<< "$result"
              exit 1
            fi
          '';
        });

        installPhase = ''
          mkdir -p $out/bin $out/desc
          for n in $name $aliases; do
            ln -s $src/bin/run "$out/bin/$n"
          done

          ln -s ${description} "$out/desc/$name"
        '';
      };
    in self // {
      inherit desc;
      run = run';

      # Nix itself can't do it, because it can't check if something
      # is a file or a directory (exportReferencesGraph doesn't tell),
      # but apparmor rules differ based on that distinction
      apparmor = stdenv.mkDerivation rec {
        name = "apparmor.profile";

        closureItems = [
          self self.src run'
          bashInteractive glibcLocales
        ];

        buildCommand = ''
          (
            echo '${self.src}/bin/run {'
            echo '  signal, ptrace,'
            echo '  /dev/{kvm,null,random,urandom,tty}' wr,
            echo '  /tmp/**' wr,
            echo '  /proc/** r,'
            echo '  /sys/devices/system/** r,'

            closure=${closureInfo { rootPaths = closureItems; }}
            while read -r path; do
              if [ -f "$path" ]; then
                echo "  $path mkrix,"
              elif [ -d "$path" ]; then
                echo "  $path** mkrix,"
              fi
            done < $closure/store-paths
            echo }
          ) > $out
        '';
      };
    });

  # -drive if=virtio,readonly,format=qcow2,file="$disk" \

  # -enable-kvm -cpu Haswell-noTSX-IBRS,vmx=on \
  # -cpu IvyBridge \
  # -net none -m "$mem" \
  # -virtfs local,readonly,path=/nix/store,security_model=none,mount_tag=store \
  commonQemuOptions = ''
    -only-migratable \
    -nographic -no-reboot \
    -sandbox on,spawn=allow \
    -cpu qemu64 ${lib.optionalString enableKVM "-enable-kvm"} \
    -m "$mem" \
    -net none \
    -device virtio-rng-pci,max-bytes=1024,period=1000 \
    -device virtio-serial-pci \
    -chardev pipe,path="$job"/control,id=control \
    -device virtserialport,chardev=control,id=control '';

  qemuDriveOptions = lib.concatMapStringsSep " " (d: "-drive if=virtio,readonly=on,format=raw,file=${d}");

  suspensionWriteCommand =
    if suspensionUseCompression
    then "${lz4}/bin/lz4 -3 --favor-decSpeed -"
    else "cat >";

  suspensionReadCommand =
    if suspensionUseCompression
    then "${lz4}/bin/lz4 -dc --favor-decSpeed"
    else "cat ";

  run = args@{ name, initrdPath, storeDrives, mem, desc, ... }: writeShellScriptBin "run-qemu" ''
    # ${name}
    export PATH=${makeBinPath [ coreutils ]}
    job="$1"
    shift
    mkfifo "$job"/control.{in,out}
    mem=''${QEVAL_MEM:-${toString mem}}
    timeout=''${QEVAL_TIME:-${toString timeout}}
    max_output=''${QEVAL_MAX_OUTPUT:-1M}

    {
      date -u +%s
      printf '%s\0' "$*"
    } > "$job"/control.in &

    timeout --foreground "$timeout" ${qemu}/bin/qemu-system-x86_64 \
      ${commonQemuOptions} \
      -monitor none \
      ${qemuDriveOptions (builtins.attrValues storeDrives)} \
      -incoming "exec:${suspensionReadCommand} ${suspension args}" | ${dos2unix}/bin/dos2unix -f | head -c "$max_output"
  '' // args;
  # ^ qemu incorrectly does crlf conversion, check in the future if still necessary

  # if this doesn't build, and just silently sits there, try increasing memory
  suspension = { name, initrdPath, storeDrives, mem, desc }: removeReferences (stdenv.mkDerivation {
    name = "${name}-suspension";
    requiredSystemFeatures = lib.optional enableKVM "kvm";
    nativeBuildInputs = [ qemu ];

    inherit mem desc;

    migrationCommand = ''${suspensionWriteCommand} "$out"; echo '{"execute":"quit"}' > job/qmp.in'';

    buildCommand = ''
      mkdir job
      job=$PWD/job
      mkfifo job/control.{in,out} job/qmp.{in,out}

      ${jq}/bin/jq -cn --unbuffered '
        {execute: "qmp_capabilities"},
        (limit(1; inputs | select(.event == "VSERPORT_CHANGE" and .data.id == "control" and .data.open)) |
        {execute: "migrate", arguments: {uri: "exec:\($ENV.migrationCommand)"}})
      ' < job/qmp.out > job/qmp.in &

      timeout ${toString suspensionTimeout} qemu-system-x86_64 \
        ${commonQemuOptions} \
        -qmp pipe:"$job"/qmp \
        ${qemuDriveOptions (builtins.attrValues storeDrives)} \
        -kernel ${kernel}/bzImage \
        -initrd ${initrd initrdPath}/initrd \
        -append "console=ttyS0,38400 tsc=unstable panic=-1 jobDesc=${desc}"
    '';
  });

  evaluators = builtins.mapAttrs (_: prepareJob) (editEvaluators
    (import ./evaluators.nix { inherit pkgs; }));

  all = symlinkJoin rec {
    name = "all-evaluators";
    paths = builtins.attrValues evaluators;
    postBuild = ''
      # keep a runtime dependency on the evaluators
      echo ${concatStringsSep " " paths} > "$out/evaluators"
    '';
  };

  apparmorAll = map (p: p.apparmor) (builtins.attrValues evaluators);
}
