---
title: "Make, shells and polyglot tests - How to write a cross-shell clean target."
date: 2025-07-22T12:00:00Z
draft: false
---

When executing various Makefiles with [w64devkit](https://github.com/skeeto/w64devkit), you can occasionally run across a Windows program with a Makefile written for cmd.exe. Often the only thing broken about them is the conventional `clean` target, which uses `del.exe` and will only work under `cmd.exe`.

```
make clean
del *.o /s
sh: del: not found
make: *** [Makefile:734: clean] Error 127
```

Confusingly, even if you then open `cmd.exe` and run `make clean` from there, you still get the same error!

The reason for this is that GNU Make for Windows searches the PATH for an `sh.exe` before selecting `cmd.exe`. This is documented in GNU Make's [README.W32](https://cgit.git.savannah.gnu.org/cgit/make.git/tree/README.W32#n175):

```
GNU Make and sh.exe:

        This port prefers if you have a working sh.exe somewhere on
        your system. If you don't have sh.exe, the port falls back to
        MSDOS mode for launching programs (via a batch file).  The
        MSDOS mode style execution has not been tested that carefully
        though (The author uses GNU bash as sh.exe).
```

Until now, I have only referred to `make`, but `mingw32-make` (a conventional prefix for several mingw(-w64) toolchains) does not differ in any way but name.

The most immediate solution is to run `make clean SHELL=cmd`. This will work, however it also brings in all the issues and misbehavior that come from cmd.exe itself, and won't work on some machines. Back in 2020 and 2021, when I was still in school, the computers there specifically had `cmd.exe` disabled. All it could do was print `The command prompt has been disabled by your administrator.`. However, busybox sh started through w64devkit functioned just fine! Of course, due to this restriction, none of the Makefiles could use cmd.exe.

Is there a way we could query what shell is executing build rules for recipes?

The answer is yes! Though it requires extensions from GNU Make. I've seen buggy code out there that tries to make an attempt, but gets it all wrong.

But first, I will clarify what *doesn't* work, so you can spot it in code review, or not waste your time testing it.

**1) Checking the presence of $ComSpec**

[Premake](https://premake.github.io) was trying to do this. This method might even insidiously seem to work, because all the unix-type shells on Windows capitalize environment variables, and GNU Make does case sensitive comparisons. You might think this fact is possible to harness to do shell detection, however, what really ends up being detected is whether the shell that invoked make is cmd or sh, not necessarily what the recipes themselves are executed with. So `make clean` in cmd.exe with an sh.exe present will be detected as cmd as well. 

Under every shell I tried, $COMSPEC was present and pointing to cmd.exe. I have not found a single circumstance where this variable differs, even in PowerShell. I am not sure what it *did* ever detect, if anything.

```
PS C:\WINDOWS\system32> echo $env:ComSpec
C:\WINDOWS\system32\cmd.exe
```

**2) Checking the value of $(SHELL)**

Make does not set this if it is unset. So it can only tell you if the value is being overridden or not, meaning your makefile cannot simply work with `make` in both circumstances of "have sh.exe" and "don't have sh.exe". Setting it in the Makefile itself to signal what shell you would like make to use also does not work.

Now, on to the method that actually works. Thanks to Kaz Kylheku from the GNU Make mailing list for telling me about this, though later I have talked to several people who seemed to know of this independently. I've still never seen it documented on another blog, so I will do so here.

The solution is to execute `echo` as a "polyglot test". Specifically, it exploits how cmd and sh handle quotes.

In cmd.exe, `echo "test"` outputs `"test"` with the quotes included. Under sh.exe, it strips the quotes and outputs just `test`. We can combine this behavioral difference with GNU make's [Conditional Syntax](https://www.gnu.org/software/make/manual/html_node/Conditional-Syntax.html) extension:

```
SHELLTYPE=sh
ifeq ($(shell echo "test"), "test")
    SHELLTYPE=cmd
endif
```

Then you can use this variable in your clean target:
```
.PHONY: clean
clean:
ifeq ($(SHELLTYPE), sh)
	rm *.o
else
	del /q *.o
endif
```

Now, your clean target will work just fine under both sh.exe and cmd.exe.

**Other Common Cross-Shell Issues**

Another operation that makefiles use regularly is `mkdir`. This one coincidentally has a common usage that works identically on Windows and Linux: `mkdir <dir>`. However, `mkdir -p` is effectively the default behavior on Windows, so if you need the `-p` flag, you're back to writing shell-specific commands.

The last problematic command that sometimes appears is `touch`, which has no `cmd.exe` equivalent I could find. I have no good solution for this one if your Makefile relies on it. Thankfully, it's rare in practice.

**A Better Build System Design?**

All of this complexity could have been avoided if common file operations were built-in to make itself, as intrinsics. Ninja, for comparison, requires you to explicitly declare outputs, so it knows exactly what to delete without shell commands.

However, Ninja lacks some of Make's pleasing "dumbness", and is much less pleasant to write by hand. If you're designing a replacement for make, I'd highly suggest limiting shell access and adding built-in operations for at least `rm`, `mkdir`, and `touch`. An escape hatch to the shell might still be needed for some unusual cases, but we shouldn't need shell commands just to delete a file. The fewer dependencies a build system has, the more robust it will be.

**Bonus Debugging Tip**

If you're debugging a makefile and want to see exactly what shell commands it runs (and it doesn't already have verbose output configured), you can use `make SHELL="sh -x"` to trace it.

Update: Skeeto wrote some further clarification about make's internals in this comment:
https://github.com/skeeto/w64devkit/issues/20#issuecomment-3109041922