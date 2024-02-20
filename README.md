# dockerc - compile docker images to standalone portable binaries

## Usage

Install dockerc from the [latest release](https://github.com/NilsIrl/dockerc/releases).

Example with the `oven/bun` docker image. This works for any image you can think of!

```
$ dockerc --image docker://oven/bun --output bun
```

To specify an image in the docker daemon internal storage use
**docker-archive**:_path_[:_docker-reference_]. Skopeo is used to loading
images, for other locations refer to [its documentation][1].

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


### Why zig?

* Small binary size
* Full static linking

[0]: https://docs.docker.com/engine/reference/commandline/container_run/
[1]: https://github.com/containers/skopeo/blob/main/docs/skopeo.1.md#image-names
