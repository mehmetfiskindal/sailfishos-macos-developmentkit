# How We Built Sailfish ARM64 on Apple Silicon

**Date: October 3, 2026**

We set up a native ARM64 Linux build environment on Mac using Docker.
We linked small C and C++ samples against the Sailfish SDK target libraries,
then ran both executables with `chroot` inside the Sailfish target filesystem.
Both samples succeeded.

The goal of this phase was to validate the ARM64 host → Sailfish aarch64
compile, link, and execution path before moving on to C/C++ sources generated
by Gea.

## 1. Architecture

```text
Apple Silicon Mac / macOS ARM64
    ↓
Docker Desktop / Linux ARM64 VM
    ↓
Ubuntu 22.04 ARM64 container
    ├── GCC / G++ 11: compilation
    ├── GNU binutils: linking and ELF inspection
    └── Sailfish OS aarch64 SDK target: headers and runtime inputs
            ↓
        AArch64 ELF executable
            ↓
        Native chroot test inside the Sailfish target
```

We verified that the Docker engine runs `linux/arm64` and used
`--platform linux/arm64` for the container. This experiment did not use x86
emulation or QEMU user-mode; the programs ran on Docker's ARM64 Linux kernel.

## 2. Docker Build Environment

We created an Ubuntu 22.04-based `Dockerfile` and installed the following tools:

```text
build-essential, binutils, cmake, pkg-config,
p7zip-full, curl, ca-certificates, python3
```

We pinned the Ubuntu image digest. Apt package versions are not pinned; we
record the installed versions in `out/host-packages.txt`. The procedure is
repeatable, though it does not guarantee bit-identical output on every run.

Because the Docker CLI and credential helper reside in the same directory on
Mac, `scripts/docker.sh` adds this directory to `PATH`:

```text
/Applications/Docker.app/Contents/Resources/bin
```

## 3. Downloading the Official Sailfish Sysroot

Archive used:

```text
Sailfish_OS-5.1.0.11-Sailfish_SDK_Target-aarch64.tar.7z
```

Source: [Sailfish official SDK target archives](https://releases.sailfishos.org/sdk/targets/).
The file size is 196,094,719 bytes. We verified the integrity of the
downloaded archive against its published MD5 value and also recorded its SHA-256
checksum for reuse:

```text
MD5:    24b40e5e6c1366996dc5a4a69a46e3b3
SHA256: b0425395468254ebaaead29b477d29e446f8dbe7c1ec1c3ac7d80b82757deadc
```

This file contains the **target userland and sysroot**. It is not a complete
Sailfish SDK tooling package running on an ARM64 host.

## 4. Extracting the Sysroot into a Linux Volume

Instead of extracting the sysroot into a macOS shared directory, we kept it in
a Docker volume:

```text
Volume: sailfish-5.1.0.11-aarch64-probe
Container path: /opt/sailfish
```

This choice preserves Linux file permissions, case sensitivity, and symlinks.
The project directory is mounted into the container as `/work`, which is why
build outputs are visible under `out/` on the Mac.

The 7z archive contains both `.tar` and `.tar.meta`. During extraction, we
selected only the tar member and passed `--ignore-zeros` so `tar` consumes the
trailing padding as well, preventing the pipe from closing early and sending
SIGPIPE to the `7z` producer.

## 5. Compiling the C and C++ Samples

`samples/hello.c` uses `printf` and `gnu_get_libc_version()`.
`samples/hello.cpp` uses `std::string`, `std::vector`, and `std::cout`, and is
compiled with `-std=c++20`.

Because the target archive does not contain C++ development headers, we chose
the inputs for this initial experiment as follows:

| Input | Source |
| --- | --- |
| GCC / G++ compiler | Ubuntu ARM64 GCC 11 |
| Compiler builtin headers | Ubuntu GCC 11 |
| C++ standard library headers | Ubuntu GCC 11 |
| C system headers | Sailfish target |
| `Scrt1.o`, `crti.o`, `crtn.o` | Sailfish target |
| `crtbeginS.o`, `crtendS.o` | Ubuntu GCC 11 |
| ELF loader, libc, libm | Sailfish target |
| libstdc++, libgcc_s | Sailfish target |

Alongside `--sysroot=/opt/sailfish`, we used `-nostdinc` (and `-nostdinc++`
for C++) and specified the include directories explicitly. We placed the C++
header directories before the C header directories; this order was required for
standard library headers that use `#include_next`.

This hybrid toolchain works for the samples we tested, though it is not proof
of compatibility for all C++20 features or the full set of Gea sources.

## 6. Explicitly Selecting Linker Inputs

We did not rely solely on `--sysroot`. To prevent Ubuntu from adding its
default runtime inputs, we used `-nostdlib` and supplied startup objects and
target libraries by explicit file paths.

Key linker settings:

```text
-pie
--dynamic-linker=/lib/ld-linux-aarch64.so.1
-rpath-link=/opt/sailfish/lib64:/opt/sailfish/usr/lib64
```

We generated a linker map file for each executable. The script inspects the
absolute `LOAD` paths in the map: outside the Sailfish sysroot, it only permits
GCC 11's `crtbeginS.o` and `crtendS.o` files. If an unexpected host input is
present, the build stops.

## 7. Verifying the ELF Files and Execution

Using `readelf`, we reported:

- ELF architecture: `AArch64`.
- Interpreter: `/lib/ld-linux-aarch64.so.1`.
- Dynamic library dependencies.
- GLIBC, GLIBCXX, CXXABI, and GCC symbol version requirements.

Next, we copied the binaries into `/tmp/gea-probe/` inside the sysroot and ran
them inside the container with:

```bash
chroot /opt/sailfish /tmp/gea-probe/hello-c
chroot /opt/sailfish /tmp/gea-probe/hello-cpp
```

In this run, Ubuntu's `/lib` and `/usr` directories remain outside the target
root, and we did not copy Ubuntu shared libraries into the target. We did not
use `--privileged`; Docker's default `SYS_CHROOT` capability was sufficient.

Recorded result:

```text
Native ARM64 execution inside Sailfish target chroot:
Hello Sailfish, C / glibc 2.41
Hello Sailfish C++
```

Host packages used:

```text
gcc-11:   11.4.0-1ubuntu1~22.04.3
g++-11:   11.4.0-1ubuntu1~22.04.3
binutils: 2.38-4ubuntu2.12
```

The downloaded archive named 5.1.0.11 was published on June 18, 2026. Its
runtime runs as glibc 2.41, with `libstdc++` 6.0.32 and `libgcc` 13.4. We do
not assume these values match any given physical phone installation.

## 8. Re-running with a Single Command

Requirements: Apple Silicon Mac, running Docker Desktop, Bash, `curl`, and an
internet connection for the initial setup. The project files must also be
present alongside this document.

From the project root:

```bash
bash scripts/probe.sh
```

The script downloads the missing archive, builds the image, checks checksums,
prepares the sysroot, compiles the samples, and runs the execution test.

File responsibilities:

| File | Responsibility |
| --- | --- |
| `Dockerfile` | ARM64 Linux build tools |
| `scripts/probe.sh` | End-to-end experiment |
| `scripts/docker.sh` | Docker CLI and helper `PATH` setup |
| `scripts/run-container.sh` | Project and sysroot volume mounts |
| `scripts/prepare-sysroot.sh` | Checksum check and archive extraction |
| `scripts/build-probes.sh` | Compilation, linking, ELF report, and chroot test |
| `samples/hello.c`, `samples/hello.cpp` | Test programs |
| `out/hello-c`, `out/hello-cpp` | Built executables |
| `out/elf-report.txt` | ELF and symbol version details |
| `out/hello-c.map`, `out/hello-cpp.map` | Linker inputs |
| `out/runtime-report.txt` | Execution result |
| `out/image.txt`, `out/host-packages.txt` | Image and tool versions used |

## 9. Scope of Verification and Next Steps

This experiment proves that two programs produced with a native ARM64 Linux
compiler **run inside the downloaded Sailfish SDK target userland**. We have not
yet built a full Gea application, produced an RPM, completed an SB2/mb2 port, or
tested on a physical device.

The chroot test is not a graphical emulator or a booted Sailfish OS; it uses
Docker's Linux kernel. Because the official Sailfish emulator target is i486,
these aarch64 executables cannot run on it. Running x86 guests on an ARM host
in VirtualBox is not an officially supported path.

The next step is to prepare a GCC 13 toolchain and C++ development headers
matching the target and build the portable CMake project generated by Gea,
followed by RPM packaging and testing on an appropriate device or emulator.

## References

- [Sailfish SDK target downloads](https://releases.sailfishos.org/sdk/targets/)
- [Sailfish tooling and target separation](https://docs.sailfishos.org/Tools/Platform_SDK/Target_Installation/)
- [Building packages with Platform SDK mb2](https://docs.sailfishos.org/Tools/Platform_SDK/Building_Packages/)
- [Sailfish app and emulator targets](https://docs.sailfishos.org/Develop/Apps/Your_First_App/)
- [Docker Desktop Linux VM architecture](https://docs.docker.com/desktop/features/vmm/)
- [VirtualBox ARM host limitations](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/KnownIssues.html)
