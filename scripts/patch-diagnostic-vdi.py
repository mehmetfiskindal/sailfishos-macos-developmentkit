"""Apply sector differences to allocated blocks of a native VirtualBox clone.

The patch stream contains <uint64 logical offset><512 bytes data> records.
Reject unallocated blocks before any write. Run only on a powered-off clone.
"""
import struct
import sys

disk_path, patch_path = sys.argv[1:]
patch = open(patch_path, 'rb').read()
assert len(patch) % 520 == 0
with open(disk_path, 'r+b') as disk:
    header = disk.read(512)
    assert struct.unpack_from('<I', header, 64)[0] == 0xbeda107f
    map_offset, data_offset = struct.unpack_from('<II', header, 340)
    block_size, extra = struct.unpack_from('<II', header, 376)
    writes = []
    for index in range(0, len(patch), 520):
        logical = struct.unpack_from('<Q', patch, index)[0]
        block, inside = divmod(logical, block_size)
        assert inside + 512 <= block_size
        disk.seek(map_offset + block * 4)
        physical = struct.unpack('<I', disk.read(4))[0]
        assert physical < 0xfffffffe, f'Unallocated block {block}'
        writes.append((data_offset + physical * (block_size + extra) + extra + inside,
                       patch[index + 8:index + 520]))
    for offset, data in writes:
        disk.seek(offset)
        disk.write(data)
print(f'Applied {len(writes)} sectors to diagnostic clone')
