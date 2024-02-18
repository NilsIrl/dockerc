```
sudo apt install libzstd-dev
./configure --without-xz --without-zlib LDFLAGS="-static"
make LDFLAGS="-all-static" -j
```

```
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
```

Examples images to try on:

* https://github.com/oven-sh/bun?tab=readme-ov-file#install
* https://github.com/containers/skopeo/blob/main/install.md#container-images
* https://github.com/shepherdjerred/macos-cross-compiler
