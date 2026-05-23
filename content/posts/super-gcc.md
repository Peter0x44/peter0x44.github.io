---
title: "Building a Host-Tuned GCC to Make GCC Compile Faster"
date: 2026-05-22T00:00:00+00:00
draft: false
tags: ["programming", "compilers", "gcc", "toolchains", "benchmarking"]
comments: true
---

A while ago, I became interested in reducing my compile times, and examined various methods for this.

This blog post is about enabling all compiler options that I believe can make gcc faster when compiling code, and measuring the gains I got as a result.

## How to Build It

```bash
mkdir build-gcc16
cd build-gcc16

../gcc-16.1.0/configure \
  --prefix="$HOME/opt/gcc16-super" \
  --program-prefix=super- \
  --enable-languages=c,c++ \
  --disable-multilib \
  --with-build-config='bootstrap-native bootstrap-lto bootstrap-O3'

make profiledbootstrap -j$(nproc)
make install-strip
```

Expect to be waiting for a while on `make profiledbootstrap`.
It took 72 minutes of wall time on my laptop (AMD Ryzen AI MAX+ PRO 395, 16c/32t, `-j32`).

Now, I will break down the various configure options, and what they precisely do.
If you wish to see the configure options used to compile any build of gcc, `gcc -v` will dump them.

## Configure Options Explained

**[`--with-build-config='bootstrap-native bootstrap-lto bootstrap-O3'`](https://gcc.gnu.org/install/build.html)**

`--with-build-config` selects small Makefile fragments from `gcc/config/*.mk` that control how the bootstrap stages are compiled. The relevant ones here are:

`bootstrap-native` adds `-march=native -mtune=native` to the flags, so the resulting compiler binary is optimized for the build host. Without this, the compiler is built with generic x86-64 codegen, and can't use AVX2, AVX512, etc. Note that this affects the compiler itself, not the code it generates. If you also want the compiler to default to native-tuned output for *your* programs, see `--with-arch`/`--with-cpu`/`--with-tune` below.

`bootstrap-lto` enables link-time optimization for the bootstrap stages. LTO lets the optimizer work across translation unit boundaries when building the compiler itself, which is a large codebase that benefits from it.

`bootstrap-O3` raises the optimization level for the bootstrap stages from `-O2` to `-O3`.

**[`make profiledbootstrap`](https://gcc.gnu.org/install/build.html)**

This is a make target, not a configure option. It performs a profile-guided optimization (PGO) build: it first builds an instrumented compiler, runs a training workload to collect execution profiles, then rebuilds using that feedback. The GCC build docs describe this as producing "a faster compiler binary", and I believe it accounts for a large part of the gain here.

**[`--program-prefix=super-`](https://gcc.gnu.org/install/configure.html)**

Prepends `super-` to the names of installed programs, so `gcc` installs as `super-gcc`, `g++` as `super-g++`, and so on. This lets the custom compiler coexist with the distro compiler without overwriting it. This is optional, you can omit it and control which compiler gets invoked by their order in your PATH.

**[`--with-cpu=native` / `--with-arch=native` / `--with-tune=native`](https://gcc.gnu.org/install/configure.html)**

You might also want these, but I did not use them in this benchmark, since this can affect compile times, so it's a control variable in the experiment. These change the *defaults* for code the compiler emits when compiling *your* programs, they have no effect on how the compiler binary itself is built. If you want the compiler to default to native-tuned output so you don't have to pass `-march=native` by hand every time, add them.

**`--enable-languages=c,c++`**

I restricted this to C and C++ to reduce build time. I don't use any other language frontend, but you can add them if you need them.

**`--disable-multilib`**

Skips building 32-bit target libraries.

**`--enable-checking=release`**

Worth knowing about if you are comparing against a GCC built from a git clone. Source tarballs default to `--enable-checking=release` (cheap assertions only), but git clones default to `--enable-checking=yes,extra`, which enables more internal consistency checks and measurably slows the compiler down. If a git-built GCC seems slower than expected, that is probably why.

You could also go further and build with `--enable-checking=no` to disable all assertions, which might squeeze out a bit more performance. I did not try that.

## Benchmark Comparison

I benchmarked compile time, not runtime of generated code. The workloads were clean parallel rebuilds (`-j32`) of four codebases, timed with `hyperfine` (2 runs each, cleaning between runs).

The baseline was Arch Linux's distro `gcc` 16.1.1, which is already built with `bootstrap-lto`. 

It was configured likeso:
```
 /build/gcc/src/gcc/configure --enable-languages=ada,c,c++,d,fortran,go,lto,m2,objc,obj-c++,rust,cobol --enable-bootstrap --prefix=/usr --libdir=/usr/lib --libexecdir=/usr/lib --mandir=/usr/share/man --infodir=/usr/share/info --with-bugurl=https://gitlab.archlinux.org/archlinux/packaging/packages/gcc/-/issues --with-build-config=bootstrap-lto --with-linker-hash-style=gnu --with-system-zlib --enable-cet=auto --enable-checking=release --enable-clocale=gnu --enable-default-pie --enable-default-ssp --enable-gnu-indirect-function --enable-gnu-unique-object --enable-libstdcxx-backtrace --enable-link-serialization=1 --enable-linker-build-id --enable-lto --enable-multilib --enable-plugin --enable-shared --enable-threads=posix --disable-libssp --disable-libstdcxx-pch --disable-werror --disable-fixincludes
 ```

The important things for performance in the command line are:
 --with-build-config=bootstrap-lto

I'm not entirely sure what all of them do, but if there other options have a major perf impact here, please tell me in the comments.

## Benchmark Results                            


| Workload | distro `gcc` | self-built `super-gcc` | Speedup |
|----------|--------------|------------------------|---------|
| GCC 16.1.0 `all-gcc` | 214.982 s | 163.376 s | 1.32x (24.0%) |
| binutils 2.46.0 | 28.173 s | 23.900 s | 1.18x (15.2%) |
| SDL 3.4.8 | 13.258 s | 11.093 s | 1.20x (16.3%) |
| CPython 3.14.5 | 20.627 s | 18.103 s | 1.14x (12.2%) |

The GCC-on-GCC result is the most improved, probably because that's the workload the compiler was profiled on. The other three benchmarks are less dramatic improvements, but not insignificant.

## Disclaimers

This was done under WSL2, not Linux directly. I only took two runs per workload, so there is some noise.

## Conclusion

The gain varied from 12% to 24% depending on the workload, and the baseline was already a modern distro build with LTO enabled. The extra knobs here are `bootstrap-native`, `-O3`, and PGO. That is where the improvement likely comes from.

I will be doing this for all gcc releases going forward, leaving something running for 72 minutes for a 12% faster build seems like a good deal to me!

Your results will probably vary, and if you try this, please leave a comment letting me know if it helped (or not), and by how much. I'm very curious, and I'm sure other GCC developers are too.