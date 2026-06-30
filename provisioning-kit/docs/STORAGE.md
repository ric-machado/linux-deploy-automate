# Storage layout (`dev` profile)

GPT partition table, UEFI boot, `/boot/efi` and `/boot` outside LVM, a single
volume group containing percentage-sized logical volumes plus a fixed-size
swap LV.

| Mount | Type | Size | Notes |
|---|---|---|---|
| `/boot/efi` | partition (FAT32) | 512M | ESP, `flag: boot`, outside LVM |
| `/boot` | partition (ext4) | 2G | outside LVM |
| *(PV)* | partition, `flag: lvm` | remainder of disk | `size: -1` |
| `/` | LV (ext4) in `vg-data` | **25%** of VG | |
| `/var` | LV (ext4) in `vg-data` | **15%** of VG | |
| `/var/lib/docker` | LV (ext4) in `vg-data` | **20%** of VG | |
| `/tmp` | LV (ext4) in `vg-data` | **5%** of VG | |
| *(swap)* | LV (swap) in `vg-data` | **4G fixed** | not a percentage, see below |
| *(free)* | unallocated in `vg-data` | **~30-35% of VG** | deliberately left free, see below |

## Percentages are relative to the VG, not the disk

curtin's `lvm_partition.size` accepts a `"NN%"` string and computes it off
the **parent VG's available space** (`available_for_partitions`), not the
whole physical disk. Since the VG here is "whatever's left after the ESP and
`/boot` partitions", a 25% `lv-root` is 25% of (disk − 512M − 2G), not 25% of
the raw disk.

## Why swap is fixed-size, not a percentage

curtin's `swap:` top-level key only creates a *swapfile* inside an existing
filesystem — it doesn't reference a logical volume. To get a dedicated swap
LV (rather than a swapfile sitting inside `/`), swap has to be modelled as an
ordinary `lvm_partition` + `format(fstype: swap)` + a path-less `mount`.

Swap should scale with RAM, not with disk size, and curtin has no
RAM-relative sizing primitive (no `min(ram, x)`). A fixed value (4G by
default) is therefore set explicitly in `profiles/dev/user-data` and should
be edited per deployment if the target's RAM is far from a typical dev
workstation/VM.

## Free space left in the VG

25 + 15 + 20 + 5 = 65% allocated to ext4 LVs, + a fixed swap LV. The
remainder (roughly 30-35% of the VG, depending on disk size and the fixed
swap's share) is left unallocated on purpose, for future `lvextend` +
`resize2fs`/`xfs_growfs` without needing to shrink anything first.

## Disk selection: `match:`

The default in `profiles/dev/user-data` is:

```yaml
match:
  size: largest
```

This is the simplest option and fine for single-disk VMs/bare metal, but
fragile if disk enumeration order or count changes. For production or
multi-disk/SAN hosts, pin a specific disk instead:

```yaml
# By serial number (see `lsblk -o NAME,SERIAL` or `udevadm info /dev/sda`):
match:
  serial: <disk-serial>

# By WWN:
match:
  wwn: <disk-wwn>

# By kernel device path (least stable across reboots/hardware changes):
match:
  path: /dev/sda
```

These alternatives are present as commented-out examples directly in
`profiles/dev/user-data`.
