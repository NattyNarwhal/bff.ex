# bff.ex

This is a tool to list the contents of an AIX backup file. The main utility of
that is extracting AIX install media from the backup format-based packages
into a sysroot, or recovering backups.

This also serves as some documentation for the format below.

Oh, and a demonstration of binary pattern matching. Why doesn't every language
support it?

## Build

You need a modern-ish Erlang and Elixir. It'll probably support back-level
versions, but I haven't tested it. Caveat emptor.

Run `mix escript.build`. The resulting file only requires Erlang.

## Run

Only listing the contents is supported. AIX backup files are consumed over
standard input, like so:

```
$ ./bff l < /mnt/downloads/AIX/rpm.rte 
 ** Disk "by name" / Filesystem "by name" **
drwxr-xr-x	2	2	2019-06-20 22:34:26Z	0	./
-r-xr-xr-x	0	0	2019-06-20 22:34:26Z	4853	./lpp_name
drwxr-xr-x	2	2	2019-06-20 22:34:26Z	0	./usr
drwxr-xr-x	2	2	2019-06-20 22:34:26Z	0	./usr/lpp
drwxr-xr-x	2	2	2019-06-20 22:34:26Z	0	./usr/lpp/rpm.rte
-r-xr-xr-x	0	0	2019-06-20 22:34:10Z	139372	./usr/lpp/rpm.rte/liblpp.a
drwxr-xr-x	2	2	2019-06-20 22:34:26Z	0	./usr/lpp/rpm.rte/inst_root
WARNING: ./usr/lpp/rpm.rte/liblpp.a is packed
[...]
```

The listing is tab-separated.

## TODO

In order from highest priority to lowest.

* Extract files (with proper metadata)
* Support packed files (some kind of Huffman coding)
* Verify header checksums
* Inode based backups

## Format documentation

The format can be mostly gleaned from the AIX header files, in particular,
`dumprestor.h` and `sys/mode.h`.

All values are little endian (surprising, considering AIX only runs on big
endian hosts). I assume this must be because it's based off of old BSD backup,
which ran on VAXen.

A common pattern is expressing values in terms of how many 64-bit values they
are. The header calls these "dwords" (doublewords).

Sometimes uninitialized data can leak through in the unused parts of a data
structure - if you see stuff at the end, it may just be garbage.

### Headers

There are generally two genres of backup file - a name based approach, and an
inode based approach. The two use the same format with different structures.
Generally, name based backups are more common and easier to support.

The format is divided into chunks prefixed with a header. The header lists:

* How long the header is (8-bit value, how long it is in 64-bit words)
* The type of header (8-bit value)
* The "magic number" (16-bit value, affects how you interpret headers/data)
* A checksum (16-bit value, unknown algorithm)

There are multiple *types* of headers. The ones I know about:

* `FS_VOLUME` (0): Begins the archive and contains metadata.
* `FS_NAME_X` (11): Indicates a file (in the Unix sense).
* `FS_END` (7): Indicates end of processing. Tends to be garbage after this.

An archive seems to begin with an `FS_VOLUME`, and has `FS_NAME_X` entries,
terminated by an `FS_END`, at least for name based backups.

There are multiple types of *magic*. The ones I know about:

* `MAGIC` (60011): Normal.
* `PACKED_MAGIC` (60012): Indicates packed data

These don't change the headers seemingly, but change how you interpret their
data; i.e. `FS_NAME_X` file contents will be compressed, dsize/size differ.

The "magic number" people talk about with AIX archives seems to be the header
of the volume record. There is no other thing at the beginning of a backup.

### Types of header

I won't go into too many details that can be covered by the binary pattern
matches in the source, but I will cover the gotchas.

#### `FS_NAME_X`

The name padded to quadword length, but the garbage at the dnd may be trimmed
according to first null or if it's max length.

For non-symlinks (this means you must test the mode field for if it's a link),
there are two 32-bit values indicating the length of the ACL/PCL fields in
dwords. Presumably, these could map to AIX ACL/PCL structures directly. These
are not expressed as part of the header length.

### Compression

I don't know. It's some kind of Huffman encoding deal per the header though.

### Checksum

I also don't know.
