"""Disable the debug flag in a powered-off diagnostic clone, in place.

Only an equal-length replacement inside one allocated VDI block is allowed.
The original and diagnostic disks remain separate backups.
"""
import struct
import sys

old = b'systemd.debug_shell=1'
new = b'systemd.debug_shell=0'
with open(sys.argv[1], 'r+b') as disk:
    header = disk.read(512)
    assert struct.unpack_from('<I', header, 64)[0] == 0xbeda107f
    map_offset, data_offset = struct.unpack_from('<II', header, 340)
    block_size, extra, total = struct.unpack_from('<III', header, 376)
    disk.seek(map_offset)
    mapping = struct.unpack(f'<{total}I', disk.read(total * 4))
    matches = []
    for physical in mapping:
        if physical >= 0xfffffffe:
            continue
        location = data_offset + physical * (block_size + extra) + extra
        disk.seek(location)
        data = disk.read(block_size)
        index = data.find(old)
        if index >= 0:
            assert data.find(old, index + 1) == -1
            matches.append(location + index)
    assert len(matches) == 1, f'Expected one debug flag, found {len(matches)}'
    disk.seek(matches[0])
    disk.write(new)
print('Debug shell disabled in permanent clone')
