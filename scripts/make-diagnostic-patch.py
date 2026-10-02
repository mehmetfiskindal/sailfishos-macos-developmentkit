"""Compare modified ext4 with original raw partition at byte offset 512."""
import struct

with open('/tmp/disk.raw', 'rb') as original, open('/tmp/root.ext4', 'rb') as changed, open('/tmp/diagnostic.patch', 'wb') as patch:
    original.seek(512)
    logical = 512
    count = 0
    while True:
        new = changed.read(1024 * 1024)
        if not new:
            break
        old = original.read(len(new))
        if old != new:
            for offset in range(0, len(new), 512):
                sector = new[offset:offset + 512]
                if sector != old[offset:offset + 512]:
                    assert len(sector) == 512
                    patch.write(struct.pack('<Q', logical + offset) + sector)
                    count += 1
        logical += len(new)
print(f'{count} changed sectors')
