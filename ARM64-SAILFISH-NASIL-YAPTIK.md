# Apple Silicon üzerinde Sailfish ARM64 derlemesini nasıl yaptık?

**Tarih: 3 Ekim 2026**

Mac üzerinde Docker kullanarak native ARM64 Linux derleme ortamı kurduk.
Küçük C ve C++ örneklerini Sailfish SDK target'ının kütüphanelerine bağladık.
Ardından iki executable'ı da Sailfish target dosya sistemi içinde `chroot`
ile çalıştırdık. Her iki örnek de başarılı oldu.

Bu aşamanın amacı, Gea tarafından üretilecek C/C++ kaynaklarına geçmeden
önce ARM64 host → Sailfish aarch64 derleme ve çalıştırma yolunu sınamaktı.

## 1. Mimari

```text
Apple Silicon Mac / macOS ARM64
    ↓
Docker Desktop / Linux ARM64 VM
    ↓
Ubuntu 22.04 ARM64 container
    ├── GCC / G++ 11: derleme
    ├── GNU binutils: linkleme ve ELF incelemesi
    └── Sailfish OS aarch64 SDK target: header ve runtime girdileri
            ↓
        AArch64 ELF executable
            ↓
        Sailfish target içinde native chroot testi
```

Docker engine'in `linux/arm64` çalıştığını doğruladık. Container için
`--platform linux/arm64` kullandık. Bu deneyde x86 emülasyonu veya QEMU
user-mode kullanmadık; programlar Docker'ın ARM64 Linux kernel'i üzerinde
çalıştı.

## 2. Docker derleme ortamı

Ubuntu 22.04 tabanlı bir `Dockerfile` oluşturduk. İçine şu araçları kurduk:

```text
build-essential, binutils, cmake, pkg-config,
p7zip-full, curl, ca-certificates, python3
```

Ubuntu image'ının digest'ini sabitledik. Apt paket sürümleri sabitlenmiş
değil; kullanılan sürümleri `out/host-packages.txt` içinde kaydediyoruz.
Yöntem tekrar çalıştırılabilir, fakat her çalıştırmada bit düzeyinde aynı
çıktıyı garanti etmiyor.

Mac'te Docker CLI ve credential helper aynı dizinde bulunduğu için
`scripts/docker.sh`, bu dizini PATH'e ekliyor:

```text
/Applications/Docker.app/Contents/Resources/bin
```

## 3. Resmi Sailfish sysroot'unu indirdik

Kullandığımız arşiv:

```text
Sailfish_OS-5.1.0.11-Sailfish_SDK_Target-aarch64.tar.7z
```

Kaynak: [Sailfish resmi SDK target arşivleri](https://releases.sailfishos.org/sdk/targets/).
Dosya boyutu 196.094.719 bayt. İndirdiğimiz arşivin bütünlüğünü resmi MD5
değeriyle doğruladık; aynı dosyanın SHA-256 değerini de tekrar kullanım için
kaydettik:

```text
MD5:    24b40e5e6c1366996dc5a4a69a46e3b3
SHA256: b0425395468254ebaaead29b477d29e446f8dbe7c1ec1c3ac7d80b82757deadc
```

Bu dosya **target userland ve sysroot** içeriyor. ARM64 host üzerinde
çalışan eksiksiz bir Sailfish SDK tooling paketi değil.

## 4. Sysroot'u Linux volume'üne açtık

Sysroot'u macOS paylaşım dizinine açmak yerine Docker volume'ünde tuttuk:

```text
Volume: sailfish-5.1.0.11-aarch64-probe
Container yolu: /opt/sailfish
```

Bu seçim Linux dosya izinlerini, büyük/küçük harf ayrımını ve sembolik
bağlantıları koruyor. Proje dizini ise container'a `/work` olarak bağlanıyor;
derleme çıktıları bu yüzden Mac'te `out/` altında görülebiliyor.

7z arşivi hem `.tar` hem `.tar.meta` içeriyor. Açarken yalnızca tar üyesini
seçtik. Tar'ın sondaki padding'i de tüketmesi için `--ignore-zeros`
kullandık; böylece pipe'ın erken kapanıp 7z üreticisine SIGPIPE göndermesini
önledik.

## 5. C ve C++ örneklerini derledik

`samples/hello.c`, `printf` ve `gnu_get_libc_version()` kullanıyor.
`samples/hello.cpp` ise `std::string`, `std::vector` ve `std::cout`
kullanıyor; `-std=c++20` ile derleniyor.

Target arşivinde C++ geliştirme header'ları bulunmadığından, bu ilk deneyde
girdileri şu şekilde seçtik:

| Girdi | Kaynak |
| --- | --- |
| GCC / G++ compiler | Ubuntu ARM64 GCC 11 |
| Compiler builtin header'ları | Ubuntu GCC 11 |
| C++ standart kütüphane header'ları | Ubuntu GCC 11 |
| C sistem header'ları | Sailfish target |
| `Scrt1.o`, `crti.o`, `crtn.o` | Sailfish target |
| `crtbeginS.o`, `crtendS.o` | Ubuntu GCC 11 |
| ELF loader, libc, libm | Sailfish target |
| libstdc++, libgcc_s | Sailfish target |

`--sysroot=/opt/sailfish` yanında `-nostdinc` ve C++ için `-nostdinc++`
kullandık. Include dizinlerini açıkça belirledik. C++ header dizinlerini C
header dizinlerinden önce verdik; `#include_next` kullanan standart
kütüphane header'ları için bu sıra gerekliydi.

Bu karışık toolchain, test ettiğimiz örnekler için çalışıyor. Bütün C++20
özellikleri veya Gea kaynaklarının tamamı için uyumluluk kanıtı değil.

## 6. Linkleme girdilerini açıkça seçtik

Yalnızca `--sysroot` vermekle yetinmedik. Ubuntu'nun varsayılan runtime
girdilerini eklemesini engellemek için `-nostdlib` kullandık; başlangıç
nesnelerini ve hedef kütüphanelerini açık dosya yollarıyla verdik.

Önemli linker ayarları:

```text
-pie
--dynamic-linker=/lib/ld-linux-aarch64.so.1
-rpath-link=/opt/sailfish/lib64:/opt/sailfish/usr/lib64
```

Her executable için linker map dosyası ürettik. Script, map içindeki mutlak
`LOAD` yollarını kontrol ediyor: Sailfish sysroot'u dışındaki girdilerden
yalnızca GCC 11'in `crtbeginS.o` ve `crtendS.o` dosyalarına izin veriyor.
Beklenmeyen bir host girdisi varsa build duruyor.

## 7. ELF dosyalarını ve çalışmayı doğruladık

`readelf` ile şu bilgileri raporladık:

- ELF mimarisi: `AArch64`.
- Interpreter: `/lib/ld-linux-aarch64.so.1`.
- Dinamik kütüphane bağımlılıkları.
- GLIBC, GLIBCXX, CXXABI ve GCC sembol sürümü gereksinimleri.

Sonra dosyaları sysroot içindeki `/tmp/gea-probe/` dizinine kopyaladık ve
container içinde şu komutlarla çalıştırdık:

```bash
chroot /opt/sailfish /tmp/gea-probe/hello-c
chroot /opt/sailfish /tmp/gea-probe/hello-cpp
```

Bu çalıştırmada Ubuntu'nun `/lib` ve `/usr` dizinleri target root'unun
dışında kalıyor. Target içine Ubuntu shared library kopyalamadık.
`--privileged` kullanmadık; Docker'ın varsayılan SYS_CHROOT yeteneği yeterli
oldu.

Kaydedilen sonuç:

```text
Native ARM64 execution inside Sailfish target chroot:
Hello Sailfish, C / glibc 2.41
Hello Sailfish C++
```

Kullanılan host paketleri:

```text
gcc-11:   11.4.0-1ubuntu1~22.04.3
g++-11:   11.4.0-1ubuntu1~22.04.3
binutils: 2.38-4ubuntu2.12
```

İndirdiğimiz 5.1.0.11 isimli arşiv 18 Haziran 2026 tarihinde yayımlanmış.
İçindeki runtime glibc 2.41 olarak çalışıyor; libstdc++ dosyası 6.0.32,
libgcc ise 13.4. Bu değerlerin herhangi bir telefon kurulumuyla aynı
olduğunu varsaymıyoruz.

## 8. Tek komutla tekrar çalıştırma

Gereksinimler: Apple Silicon Mac, çalışan Docker Desktop, Bash, curl ve
ilk kurulum için internet bağlantısı. Bu belgenin yanında proje dosyaları
da bulunmalı.

Proje kökünde:

```bash
bash scripts/probe.sh
```

Script eksik arşivi indirir, image'ı oluşturur, checksum kontrolünü yapar,
sysroot'u hazırlar, örnekleri derler ve çalışma testini gerçekleştirir.

Dosyaların görevleri:

| Dosya | Görev |
| --- | --- |
| `Dockerfile` | ARM64 Linux derleme araçları |
| `scripts/probe.sh` | Uçtan uca deney |
| `scripts/docker.sh` | Docker CLI ve helper PATH ayarı |
| `scripts/run-container.sh` | Proje ve sysroot volume bağlantıları |
| `scripts/prepare-sysroot.sh` | Checksum kontrolü ve arşiv açma |
| `scripts/build-probes.sh` | Derleme, linkleme, ELF raporu ve chroot testi |
| `samples/hello.c`, `samples/hello.cpp` | Test programları |
| `out/hello-c`, `out/hello-cpp` | Üretilen executable'lar |
| `out/elf-report.txt` | ELF ve sembol sürümü bilgileri |
| `out/hello-c.map`, `out/hello-cpp.map` | Linker girdileri |
| `out/runtime-report.txt` | Çalıştırma sonucu |
| `out/image.txt`, `out/host-packages.txt` | Kullanılan image ve araç sürümleri |

## 9. Doğrulamanın kapsamı ve sonraki adım

Bu deney, native ARM64 Linux compiler ile üretilen iki programın
**indirdiğimiz Sailfish SDK target userland'i içinde çalıştığını** kanıtlıyor.
Henüz tam Gea uygulaması derlemedik, RPM üretmedik, SB2/mb2 portunu
tamamlamadık ve fiziksel cihaz testi yapmadık.

Chroot testi grafik emülatör veya boot edilmiş Sailfish OS değil; Docker'ın
Linux kernel'ini kullanıyor. Resmi Sailfish emülatör hedefi i486 olduğu için
bu aarch64 executable'lar onda çalışmaz. VirtualBox'ın ARM host üzerinde
x86 guest çalıştırması resmi olarak desteklenen yol değil.

Bir sonraki adım, target ile eşleşen GCC 13 toolchain/C++ geliştirme
header'larını hazırlamak ve Gea'nın ürettiği portable CMake projesini
derlemek. Ardından RPM paketleme ve uygun cihaz/emülatör testi gelir.

## Kaynaklar

- [Sailfish SDK target indirmeleri](https://releases.sailfishos.org/sdk/targets/)
- [Sailfish tooling ve target ayrımı](https://docs.sailfishos.org/Tools/Platform_SDK/Target_Installation/)
- [Platform SDK ile mb2 paket derleme](https://docs.sailfishos.org/Tools/Platform_SDK/Building_Packages/)
- [Sailfish uygulama ve emülatör hedefleri](https://docs.sailfishos.org/Develop/Apps/Your_First_App/)
- [Docker Desktop Linux VM yapısı](https://docs.docker.com/desktop/features/vmm/)
- [VirtualBox ARM host sınırlamaları](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/KnownIssues.html)
