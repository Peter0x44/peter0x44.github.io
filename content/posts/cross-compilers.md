---
title: "Cross Compilation Theory and Practice - from a Tooling Perspective"
date: 2025-07-24T14:17:41+01:00
draft: false
tags: ["programming", "compilers", "cross-compilation", "toolchains"]
categories: ["tutorials"]
comments: true
---

Cross compilation is a common task during development, but different compilers and programming languages handle it in their own ways, and I wanted to write about the various flavors of trade-offs and design decisions that you will find across different tooling. I feel like I have absorbed a lot of information about how cross compilation works across different targets, tools and languages, so I figured it was time to condense my knowledge into a blog post. This is not a tutorial, but it still contains practically applicable knowledge. I don't claim to get every detail correct, merely explaining how things work to my understanding.

Before diving into the specifics, let's establish some jargon that comes up repeatedly across different tools:

## Fundamental Concepts

### Target Triple

**Target Triple**: A string unambiguously identifying a target

They are in a loose adhoc format that follows some rough conventions:
CPU_TYPE-VENDOR-OPERATING_SYSTEM or CPU_TYPE-VENDOR-KERNEL-OPERATING_SYSTEM.

A target triple doesn't really become "official" until a major toolchain, operating system, or hardware vendor adopts it.

CPU_TYPE sometimes has processor features encoded into it, like i(3/4/5/6)86, or endianness when it differs from the conventional one for an architecture (powerpc64le, armeb, mipel).
VENDOR can be omitted or replaced with `unknown`.
KERNEL/OPERATING_SYSTEM can be `none` for baremetal targets, and sometimes one of them is the name of an ABI or libc.

You can learn what the target triple of your machine is by running `cc -dumpmachine`. This is what you would select if you wanted to compile executables for that machine on a different one.

### Sysroot

**Sysroot**: A directory containing the target system's headers and libraries.

This in a literal sense, refers to the root of the target's filesystem. On Linux systems, this will contain `usr/`. Things like the libc, kernel-headers, etc would be located here.

## How Different Tools Handle Cross Compilation

Now that I have explained the most essential terminology and theory required for cross compilers, I will explain how all of these concepts work in practice across various languages and toolchains.

### GCC

GCC requires being built separately for every target triple you want to target.
That is why you can typically find several separate packages of gcc for various targets in the repositories of popular distros.

If you want to build GCC yourself, there are several target triples to consider when you are configuring, that are relevant to cross-compilation:

**Host**: The target triple the compiler runs on.

**Target**: The target triple the compiler generates code for.

**Build**: The target triple on which the compiler was built. Almost never needs to be manually specified.

These can be passed to [gcc's configure script](https://gcc.gnu.org/install/configure.html) with --host=, --target=, --build=

Now, to provide some examples to explain what the combinations mean in practice:

##### Native compilation
```
build  = x86_64-linux-gnu
host   = x86_64-linux-gnu
target = x86_64-linux-gnu
```

For a native compile, all 3 target triples are the same.

##### Cross compilation
```
build  = x86_64-linux-gnu
host   = x86_64-linux-gnu
target = x86_64-w64-mingw32
```

For a cross compiler, host and target differ. This compiler will run on x86_64 linux and emit code for x86_64 windows.

##### Canadian cross
```
build  = x86_64-linux-gnu
host   = aarch64-linux-gnu
target = x86_64-w64-mingw32
```

For a Canadian cross (cross compiling a compiler), all 3 of the target triples typically differ.
This will compile a compiler, on a x86_64 linux system, that runs on an aarch64 linux system, and emits code for x86_64 windows.

The next thing you need to use the cross-compiler is a sysroot. You can build one from scratch or copy /usr from a target system into a directory locally, and point to it as a sysroot.
GCC accepts this at configure time with --with-sysroot=, or at runtime with --sysroot=.

Jeff Preshing describes one method of creating a Linux sysroot from scratch in this blog post:
https://preshing.com/20141119/how-to-build-a-gcc-cross-compiler/

Installing GCC will prepend the name of the target to the executables of the toolchain, and you could then invoke the compiler driver by prepending the target triple, `x86_64-linux-gnu-gcc`

> **Note**: I roughly described the steps above at a high level for educational purposes, but [crosstool-NG](https://crosstool-ng.github.io/) can automate much of the process for you, which is extremely complicated and tedious.

### Clang

Unlike GCC, LLVM as typically packaged by distros can generate code for any supported target, not just one selected at compile time. This can make it easier to use for cross-compilation in some circumstances, because all it needs is a sysroot for the target. This can spare you from doing a lengthy build of a compiler.

So this means, in theory, on my Arch machine, I can direct clang to generate a windows executable from my mingw-w64 sysroot like so:
```
$ clang -target x86_64-w64-mingw32 --sysroot=/usr/x86_64-w64-mingw32/ hello.c
```
Unfortunately, this has some rough edges and does not always work out, as the [Clang documentation warns](https://clang.llvm.org/docs/CrossCompilation.html):
```
/usr/bin/x86_64-w64-mingw32-ld: cannot find -lgcc: No such file or directory
/usr/bin/x86_64-w64-mingw32-ld: cannot find -lgcc_eh: No such file or directory
/usr/bin/x86_64-w64-mingw32-ld: cannot find -lgcc: No such file or directory
/usr/bin/x86_64-w64-mingw32-ld: cannot find -lgcc_eh: No such file or directory
clang: error: linker command failed with exit code 1 (use -v to see invocation)
```
But, after pointing clang to libgcc manually, it did create a functional windows executable without issues.
```
$ clang -target x86_64-w64-mingw32 --sysroot=/usr/x86_64-w64-mingw32/ -L /usr/lib/gcc/x86_64-w64-mingw32/15.1.0/ hello.c
$ file a.exe
a.exe: PE32+ executable for MS Windows 5.02 (console), x86-64, 18 sections
$ wine a.exe
hello world
```
This is pretty cool! It could spare you a lot of time when it works, but building LLVM yourself is probably still often necessary in a lot of circumstances.

As for building a sysroot from scratch, at the time of writing glibc does not currently support building with clang from a release, so you may have to use musl, or a different libc. This is not something I have ever attempted personally, so I'm not aware of the caveats involved with using LLVM.

You can also use `zig` for its `zig cc` command. Zig comes pre-packaged with sysroots for many targets, including Windows and Linux using musl.
https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-gcc-clang.html


### CMake

Of course, a significant portion of the software you might want to cross compile depends on a build system of some sort. CMake is the most popular, and the one I have the most experience with, so I will cover it here.

With CMake, you have to write a "toolchain file", which gives CMake some information about your toolchain.

[CMake's documentation](https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html#cross-compiling-for-linux) provides this example:
```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(CMAKE_SYSROOT /home/devel/rasp-pi-rootfs)
set(CMAKE_STAGING_PREFIX /home/devel/stage)

set(tools /home/devel/gcc-4.7-linaro-rpi-gnueabihf)
set(CMAKE_C_COMPILER ${tools}/bin/arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER ${tools}/bin/arm-linux-gnueabihf-g++)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
```

We can see some of the usual information, like sysroot, operating system, and processor. CMake has decided to make users specify that separately instead of trying to figure it from the target triple, which is probably a smart idea.

CMAKE_STAGING_PREFIX is a separate directory outside of the sysroot that CMake can install libraries to, in case the sysroot isn't somewhere you have permissions to write.

CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER tells cmake not to search for executables inside the target's sysroot. If you are cross compiling, the host system cannot run these.

The last 3 variables tell CMake to ignore the host's libraries, headers, packages when searching. If you are cross compiling, these will not be compatible with the target.

You pass this to CMake when configuring, using `cmake --toolchain-file my_cross_toolchain.cmake ...`.

### Go

Go does not depend on a libc at all, so there is no need to worry about a sysroot!

It is controlled by two environment variables, which you can set when invoking `go build`.
So, to build for x86_64 windows, from any OS with go installed, run:
`GOOS=windows GOARCH=amd64 go build`
For aarch64 linux:
`GOOS=linux GOARCH=arm64 go build`

I think this is epic, and probably the most advanced tooling for cross-compilation out of any language!
It is another way in which [Go's Tooling is Undervalued](https://nullprogram.com/blog/2020/01/21/)

If I had to make a minor criticism, it does not rely on standard target triples, and invents some unusual names for certain architectures (386 for "IA32"/x86).

### Crystal

Crystal is getting a mention because its [process of cross compilation is so unusual](https://crystal-lang.org/reference/1.17/syntax_and_semantics/cross-compilation.html), I have not seen it elsewhere. It emits an object file, along with a corresponding command to link it. You can either link it on the host with a normal cross compiling toolchain, or copy it to such a system and run the command there.

## Conclusion

This post has covered some of the major toolchains I'm familiar with, but there are many more out there - too many for me to possibly cover myself. I may expand this article a little in future, and feel free to describe how other tooling and languages work in the comments.