# Sailfish ARM64 build probe

Apple Silicon → ARM64 Ubuntu container → Sailfish aarch64 ELF.

Run from this directory with Docker Desktop running:

```sh
bash scripts/probe.sh
```

The script downloads the official Sailfish OS 5.1.0.11 aarch64 SDK target
(196 MB), checks its published MD5 and the recorded SHA-256, builds the
ARM64 image, and extracts the target into the Docker volume
`sailfish-5.1.0.11-aarch64-probe`. Extraction uses a Linux volume to preserve
permissions, case sensitivity and symlinks. The Ubuntu base image digest is
pinned; apt package versions are recorded in `out/host-packages.txt`, rather
than frozen. This is a reproducible procedure, not a bit-identical build.

Outputs:

- `out/hello-c`: C executable printing the running libc version.
- `out/hello-cpp`: C++20-mode executable using string, vector and iostream.
- `out/elf-report.txt`: architecture, interpreter, dependencies and symbol versions.
- `out/hello-*.map`: all linker inputs. The build rejects unexpected host inputs.
- `out/runtime-report.txt`: native execution inside the Sailfish target chroot.
- `out/image.txt`, `out/host-packages.txt`: build image and host tool versions.

## Toolchain boundary

This probe uses Ubuntu GCC 11 for compilation and its builtin/C++ headers
and `crtbeginS.o`/`crtendS.o`. The official target archive contains no C++
development headers. C system headers, libc startup objects, loader,
libc, libm, libstdc++ and libgcc_s come from Sailfish. Linking uses
`-nostdlib` and explicit target inputs to prevent accidental Ubuntu runtime
linkage. No Ubuntu shared libraries are copied into the target.

Both executables are copied into the target root and executed with `chroot`.
Host runtime directories are inaccessible there; Docker's default
SYS_CHROOT capability is sufficient, with no privileged container or QEMU.
This proves the samples run against this SDK target userland. It does not
prove full Gea compatibility, physical-device behavior, or a complete
ARM64 Sailfish tooling port. The next compiler milestone is a GCC 13
toolchain with matching target C++ development headers and a full Gea build.

## Verified result

On 2026-10-03, both AArch64 executables compiled, linked, and ran:

```text
Native ARM64 execution inside Sailfish target chroot:
Hello Sailfish, C / glibc 2.41
Hello Sailfish C++
```

The target tarball was published on 2026-06-18 under the 5.1.0.11 name;
its runtime reports glibc 2.41 and includes libstdc++ 6.0.32 / libgcc 13.4.
Do not infer that an arbitrary phone installation has identical libraries.

## Emulator

The official Sailfish emulator uses the i486 target. These aarch64 binaries
cannot run there. VirtualBox documents x86 guests on ARM hosts as unsupported;
an emulator on this Mac needs a separately validated emulation route.
The chroot execution above is a CLI userland test, not a graphical emulator
or a booted Sailfish OS.

References:

- [Sailfish target downloads](https://releases.sailfishos.org/sdk/targets/)
- [Tooling vs target](https://docs.sailfishos.org/Tools/Platform_SDK/Target_Installation/)
- [Sailfish emulator target](https://docs.sailfishos.org/Develop/Apps/Your_First_App/)
- [VirtualBox ARM host limitations](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/KnownIssues.html)
