"""Read an offline emulator disk's first Linux partition for diagnostics."""
import struct
import subprocess

with open('/tmp/disk.raw', 'rb') as disk:
    mbr = disk.read(512)
for index in range(4):
    entry = mbr[446 + index * 16:462 + index * 16]
    kind = entry[4]
    start, count = struct.unpack_from('<II', entry, 8)
    print(f'Partition {index + 1}: type={kind:02x}, start={start}, sectors={count}', flush=True)
    if kind == 0x83:
        subprocess.run(['dd', 'if=/tmp/disk.raw', 'of=/tmp/root.ext4', 'bs=4M',
                        f'skip={start * 512}', f'count={count * 512}',
                        'iflag=skip_bytes,count_bytes', 'conv=sparse', 'status=none'], check=True)
        break
else:
    raise SystemExit('No Linux partition found')
for path in ('/etc/fstab', '/etc/sysconfig/network-scripts/ifcfg-eth0',
             '/etc/ssh/sshd_config', '/etc/systemd/system', '/usr/lib/systemd/system'):
    print(f'=== {path} ===', flush=True)
    command = ('ls -p ' if path.endswith('/system') else 'cat ') + path
    subprocess.run(['debugfs', '-R', command, '/tmp/root.ext4'], check=True)
