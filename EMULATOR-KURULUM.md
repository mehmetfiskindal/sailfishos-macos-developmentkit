# Apple Silicon üzerinde Sailfish emülatör denemesi

3 Ekim 2026 tarihinde VirtualBox 7.2.20 üzerinde Sailfish OS 5.1.0.11
emülatörü için x86 VM oluşturuldu. VirtualBox'ın deneysel
`VBoxInternal2/EnableX86OnArm=1` ayarı zaten açıktı.

VM adı: `Sailfish OS Emulator 5.1.0.11 - ARM host experiment`.
Dosyalar proje içindeki `emulators/` dizininde tutuluyor ve Git'ten hariç.
Downloads içindeki orijinal VDI değiştirilmedi; VirtualBox ile klonlandı.

## Kurulum

Arşivin içindeki `sailfishos.vdi` çıkarıldıktan sonra:

```bash
bash scripts/setup-emulator.sh /path/to/sailfishos.vdi
```

Script yeni VM oluşturur; aynı adlı VM varsa mevcut VM'e dokunmadan çıkar.
Mevcut VM'i güncellemek için scripti tekrar çalıştırmak yeterli değildir.

Kullanılan ayarlar: x86/Linux26, BIOS, 1 CPU, 2048 MB RAM, 128 MB VRAM, VBoxVGA,
SATA/AHCI disk. `CustomVideoMode1=720x1280x32` gereklidir: bootloader
`vga=864` (`0x360`) modunu istiyor. Bu ayar olmadan video modu sorusunda
bekledi; ayar eklendikten sonra kernel açıldı.

NAT üzerinden SSH yönlendirmesi: `127.0.0.1:2223 → guest:22`.
VM'e özel ED25519 anahtarı `sdk-key` dosyasına üretildi; public key,
`ssh/root/authorized_keys` ve `ssh/defaultuser/authorized_keys` içine kondu.
Private key guest'e paylaşılmıyor.

Image'ın systemd mount dosyalarına göre paylaşımlar:

- `ssh` → `/etc/ssh/authorized_keys`
- `config` → `/etc/mersdk/share`
- `media` → `/run/media/defaultuser/sdk`

Config paylaşımına compositor ekran ölçüleri ve device model ayarları eklendi.

## Başlatma ve normal kapatma

```bash
VBOX=/Applications/VirtualBox.app/Contents/MacOS/VBoxManage
VM='Sailfish OS Emulator 5.1.0.11 - ARM host experiment'
"$VBOX" startvm "$VM" --type gui
"$VBOX" controlvm "$VM" acpipowerbutton
```

SSH servisi hazır olduğunda:

```bash
ssh -p 2223 \
  -i 'emulators/Sailfish OS Emulator 5.1.0.11 - ARM host experiment/sdk-key' \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=out/emulator-known-hosts \
  root@127.0.0.1
```

## Doğrulananlar ve açık sorunlar

- VM oluşturuldu ve başlatıldı.
- Sailfish konsolu `Sailfish OS 5.1.0.11 (Pispala)` ve
  `Kernel 5.0.21-1.4.5.jolla on an i686` gösterdi.
- Guest Additions servisi loglarda çalıştı.
- Grafik arayüz ayrı teşhis kopyasında görüntü verdi.
- SSH, NAT adresi `10.0.2.15` verildikten sonra doğrulandı. Ayrıntı sondaki bölümde.
- İlk VBoxVGA/virtio denemesinin ardından VMSVGA/Intel E1000 ayarı da denendi;
  VMSVGA ayarında grafik servisi DRM aygıtı bulamadığı için kapanıyor.

Grafik konsolu tty7, login konsolu tty2. Bunlara Ctrl+Alt+F7 ve
Ctrl+Alt+F2 ile geçilebilir. Ekran görüntüleri ve VM logları teşhis için saklandı.

Ayrı bir offline teşhis diski (`sailfish-debug.vdi`) hazırlandı; bu disk
bootloader hatası verdi ve kullanılmayı bıraktık. VM tekrar ilk çalışan
`sailfishos.vdi` diskine bağlandı. Aktif diskte debug shell etkinleştirilmedi.
Geçici offline inceleme container'ları temizlendi.

## Grafik sorununun teşhisi ve düzeltmesi

3 Ekim 2026 tarihli canlı journal kaydı doğrudan nedeni gösterdi:

```text
lipstick: Could not find DRM device!
lipstick.service: Main process exited, code=killed, status=6/ABRT
```

VMSVGA altında `/dev/dri` yoktu. Image'ın kernel modüllerinde `vmwgfx`
bulunmuyor. Mevcut `vboxvideo` modülü ise VBoxVGA'nın `80ee:beef` PCI
aygıtını destekliyor; VMSVGA'ya bağlanmıyor. Konsolun VESA ile görüntü
vermesi Qt/EGLFS grafik oturumunun da çalışacağı anlamına gelmiyor.

VM kapalıyken düzeltmeyi tekrar uygulamak için:

```bash
bash scripts/fix-emulator-graphics.sh
```

Scriptin temel düzeltmesi:

```bash
"$VBOX" modifyvm "$VM" --graphicscontroller vboxvga --accelerate-3d off
```

Yeni açılışta şu sonuçlar doğrulandı:

```text
/dev/dri/card0
fb0: switching to vboxdrmfb from VESA VGA
[drm] Initialized vboxvideo 1.0.0 ... on minor 0
```

Sailfish duvar kâğıdı ve yön okları `out/sailfish-first-ui.png` ekran
görüntüsünde görüldü. Deneysel x86 emülasyonunda bu açılış birkaç dakika
sürdü; erken alınan siyah ekran tek başına servisin çöktüğünü göstermiyor.
Kurulum scripti de artık VBoxVGA seçiyor.
Başlangıç ekran isteği telefon arayüzüyle aynı `GUI/LastGuestSizeHint=720,1280` olarak ayarlandı. `1024,768` yatay pencere, arayüzü sola yaslayıp dokunmayı kaydırıyordu.
pencere değişince telefon ekranını yeniden boyutlandıran
`GUI/AutoresizeGuest` kapatıldı. Bu anahtarlar
[VirtualBox kaynak kodunda](https://github.com/VirtualBox/virtualbox/blob/main/src/VBox/Frontends/VirtualBox/src/extradata/UIExtraDataDefs.cpp)
tanımlı.

Teşhis için asıl diskin ayrı bir native VirtualBox klonu
(`graphics-diagnostic.vdi`) kullanıldı. Yalnızca bu kopyada
`systemd.debug_shell=1` etkinleştirildi. Değişiklikler partition başlangıcı
olan **512 bayt** hesaba katılarak 11 sektörlük farkla uygulandı;
VDI başlığı ve bootloader korunuyor. Bu kopya normal kullanım için gerekli değil.
Canlı kayıtlar VM dizininin `media/` klasöründe bulunuyor.

Asıl diske dönüş denemesinde siyah ekran tekrar görüldü. Bunun aynı DRM
hatası olup olmadığı o diskte canlı log alınamadığı için doğrulanamadı.
Bu yüzden görüntü veren teşhis diskinin ayrı native klonu
`sailfish-fixed.vdi` oluşturuldu. Klondaki boot parametresi eşit uzunluklu
`systemd.debug_shell=0` ile değiştirilerek root debug konsolu kapatıldı.
Eski `sailfishos.vdi` ve teşhis kopyası yedek olarak korunur.
Teşhis açılışının ana ekran görüntüsü `out/sailfish-first-ui.png` dosyasında.

## SSH ve kullanılabilir disk

Aktif disk `sailfish-session.vdi`. Bu, `sailfish-fixed.vdi` klonudur;
üzerinde debug kabuğu açıktır ve açılışta NAT adresi yazan bir oneshot
servis vardır.

`sdk-setup-emulan`, `eth0` görünmeden çalışıyor. Yedek connman dosyasına
boş `MAC` yazıp çıkıyor, bu yüzden DHCP hiç başlamıyor ve Guest Additions
`Net/Count=0` bildiriyor. Servis, taşıyıcı geldikten sonra adresi elle kuruyor:

```text
10.0.2.15/24
gateway 10.0.2.2
dns 10.0.2.3
```

3 Ekim 2026 tarihinde bu adresle SSH doğrulandı:

```text
Linux SailfishEmul 5.0.21-1.4.5.jolla #1 SMP PREEMPT Wed Apr 15 03:10:37 UTC 2026 i686 i686 i386 GNU/Linux
Sailfish OS 5.1.0.11 (Pispala)
```

```bash
ssh -p 2223 \
  -i 'emulators/Sailfish OS Emulator 5.1.0.11 - ARM host experiment/sdk-key' \
  -o IdentitiesOnly=yes \
  root@127.0.0.1
```

Paylaşımlar bağlanıyor: `ssh` → `/etc/ssh/authorized_keys`, `config` →
`/etc/mersdk/share`, `media` → `/run/media/defaultuser/sdk`.
`/dev/dri/card0` var ve `lipstick` süreci ayakta. Pencere, arayüz ve
dokunma katmanı `720x1280` olmalı. `QT_QPA_EGLFS_SCALE=1`; ölçek 2
dokunmayı `2048x1536` sanıyordu, `1024x768` yatay pencere ise duvar
kâğıdını sola yaslayıp dokunmayı kaydırıyordu. VMSVGA'ya dönülmez. Donanım ayarları kurulum betiğindeki gibi:
VBoxVGA, 3D kapalı, Intel E1000, NAT `2223→22`.

Bu bir deneysel x86 emülasyonu testidir; ARM64 Docker derleme ortamından
ayrıdır. Mevcut ARM64 executable'lar i486 emülatörde çalıştırılamaz.
