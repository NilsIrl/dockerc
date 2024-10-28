# dockerc - compile docker images to standalone portable binaries

No more [![Tweet](./assets/post.png)][4]

No more `docker run`, no more `pip install`, no more `npm i`, just give your users executables they can run!


## Usage

Install dockerc from the [latest release](https://github.com/NilsIrl/dockerc/releases).


```
# Image from docker hub
$ dockerc --image docker://oven/bun --output bun
# Image in local docker daemon storage
$ dockerc --image docker-daemon:mysherlock-image:latest --output sherlock_bin
# Specify target instruction set architecture
$ docker --image docker://hello-world --arch arm64 --output hello
```

The output binary can then be called as you would with usual binaries. You can
also specify `-e`, and `-v` in the same way you would when using `docker run`.
Networked services running inside the container can be accessed directly without
having to specify `-p`.

Skopeo is used for loading images, for other locations refer to [its documentation][1].

## Build from source

Please note that this project uses Git submodules. If you clone this repository, you may need to run the following commands to initialize and update the submodules:

```
$ git submodule init
$ git submodule update
```

This will ensure that you download and update all relevant submodule contents. Once the submodules are properly initialized, you can proceed with the compilation instructions below.

```
$ zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
$ zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-linux-musl
```

## Features

- [X] Compile docker images into portable binaries
- [X] Rootless containers
- [ ] MacOS and Windows support (using QEMU)
- [X] x86_64 support
- [X] arm64 support
- [X] Supports arguments
- [X] [Supports specifying environment variables using `-e`][2]
- [X] [Supports specifying volumes using `-v`][3]
- [ ] Support other [arguments][0]...

[0]: https://docs.docker.com/engine/reference/commandline/container_run/
[1]: https://github.com/containers/skopeo/blob/main/docs/skopeo.1.md#image-names
[2]: https://docs.docker.com/reference/cli/docker/container/run/#env
[3]: https://docs.docker.com/reference/cli/docker/container/run/#volume
[4]: https://www.reddit.com/r/github/comments/1at9br4/i_am_new_to_github_and_i_have_lots_to_say/
