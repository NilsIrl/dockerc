# dockerc - compile docker images to standalone portable binaries

## Usage

Install dockerc from the [latest release](https://github.com/NilsIrl/dockerc/releases).


```
# Image from docker hub
$ dockerc --image docker://oven/bun --output bun
# Image in local docker daemon storage
$ zig-out/bin/dockerc --image docker-daemon:mysherlock-image:latest --output sherlock_bin
```

Skopeo is used for loading images, for other locations refer to [its documentation][1].

## Features

- [X] Compiler docker images into portable binaries
- [X] Rootless containers
- [ ] MacOS and Windows support (using QEMU)
- [X] x86_64 support
- [ ] arm64 support
- [X] Supports arguments
- [ ] Support `-p`
- [ ] Support `-v`
- [ ] Support other [arguments][0]...

[0]: https://docs.docker.com/engine/reference/commandline/container_run/
[1]: https://github.com/containers/skopeo/blob/main/docs/skopeo.1.md#image-names
