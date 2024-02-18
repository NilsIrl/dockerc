# dockerc - compile docker images to standalone portable binaries

## Features

- [X] Compiler docker images into portable binaries
- [X] Rootless containers
- [ ] MacOS support (using qemu)
- [X] x86_64 support
- [ ] arm64 support
- [X] Supports arguments
- [ ] Support `-p`
- [ ] Support `-v`
- [ ] Support other [arguments][0]...


### Why zig?

* Small binary size
* Full static linking

[0]: https://docs.docker.com/engine/reference/commandline/container_run/