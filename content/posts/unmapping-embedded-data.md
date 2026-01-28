---
title: "Unmapping Embedded Executable Data on Linux"
date: 2026-01-28T12:00:00Z
draft: false
tags: ["programming", "linux", "elf", "memory-management"]
comments: true
---

In C and C++ programs, it's quite common to embed binary data directly in executables. Two straightforward ways are:

```c
// C23 #embed
const unsigned char texture[] = {
    #embed "texture.png"
};

// Or xxd codegen'd array
const unsigned char texture_png[] = {
    0x89, 0x50, 0x4e, 0x47, /* ... */
};
unsigned int texture_png_len = 12345;
```

This is quite convenient. The data is now part of the executable, and you don't need to worry about shipping separate files. It works well, but has a limitation I was recently thinking about.

For short-lived runtime resources, like a texture you upload to the GPU:

```c
int main() {
    // ...
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, texture);
    
    // Upload to GPU complete. No longer need array in CPU memory.
}
```

After the texture is uploaded to the GPU, there is typically no reason to keep the array around in the CPU side. 

The arrays take virtual address space and memory for the entire duration of the program's runtime. For most simple games and programs, this is not likely to be a big issue, as it's most likely a trivial amount of memory. On 64-bit systems, the virtual address space used is also likely a non-issue. But I can come up with (admittedly theoretical) scenarios where this might be unacceptable.

Wouldn't it be nice if there were methods to map and unmap this binary data at will? I was curious, and did some thinking about this. This post is what I came up with in my research.

Note: I am not an expert on ELF or recommending any of this in practice. I just had some findings that I thought could be interesting to some. Any bigger domain experts than me are welcome to chime in the comments.

First, naively unmapping the memory likeso:
```c
    munmap((void*)texture, sizeof(texture));
```

Doesn't work, and will segfault. This is because the data lands inside .rodata, which the ELF loader maps at load time, and contains a bunch of other essential data for the program's operation, like string literals, C++ vtables, and probably more.

Attempting to put the array inside a specific elf segment with something like:
```c
const unsigned char texture[] __attribute__((section(".mydata"))) = { /* ... */ };
```

Also didn't help make the array unmap-able. This attribute seems to only name the section in the object file, doesn't control how the linker puts it in the executable. Even with linker scripts, I couldn't find any reliable way to make sure the array was page-aligned and also a multiple of page size. But, that doesn't mean it's impossible. If you know how, please share!

## Solution

I found one working approach in my research, but there are surely others.

## Non-Allocatable Sections

Create ELF sections without the `alloc` flag. This is the same mechanism that debug information uses. The loader completely ignores them.

### Build

```bash
gcc -o program program.c

objcopy --add-section .texture=texture.png \
        --set-section-flags .texture=contents,readonly \
        program
```

Verify it's not in any PT_LOAD segment:

```bash
$ readelf -S program
  [Nr] Name              Type             Address           Offset
       Size              EntSize          Flags  Link  Info  Align
...
  [15] .rodata           PROGBITS         0000000000002000  00002000
       00000000000000c6  0000000000000000   A       0     0     8
...
  [28] .debug_info       PROGBITS         0000000000000000  000030d3
       0000000000000d47  0000000000000000           0     0     1
...
  [34] .texture          PROGBITS         0000000000000000  0002941a
       0000000000019000  0000000000000000           0     0     1
...
Key to Flags:
  W (write), A (alloc), X (execute), M (merge), S (strings), I (info),
  L (link order), O (extra OS processing required), G (group), T (TLS),
  C (compressed), x (unknown), o (OS specific), E (exclude),
  D (mbind), l (large), p (processor specific)
```

So as this output demonstrates, a mapped section like .rodata has an A (alloc*atable*) flag.
This means it occupies memory at runtime. 
But, the .debug_info section doesn't have any flags. And neither does .texture.
They also have an address of 0.

Because of this, the loader won't map it for us, so we need to do a bit of "reflection" by parsing the ELF to get a pointer to this data.

### Runtime: Parse ELF and Map

```c
#include <elf.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>

typedef struct {
    void *base;          // Page-aligned mmap base
    unsigned char *data; // Actual data (may be offset within page)
    size_t map_size;     // Total mapped size
    size_t data_size;    // Size of actual data
} embedded_section_info;

bool load_embedded_section(const char *section_name, embedded_section_info *result) {
    int fd = open("/proc/self/exe", O_RDONLY);
    if (fd < 0) return false;
    
    Elf64_Ehdr ehdr;
    if (read(fd, &ehdr, sizeof(ehdr)) != sizeof(ehdr)) {
        close(fd);
        return false;
    }
    
    lseek(fd, ehdr.e_shoff, SEEK_SET);
    Elf64_Shdr *shdr = malloc(ehdr.e_shnum * sizeof(Elf64_Shdr));
    read(fd, shdr, ehdr.e_shnum * sizeof(Elf64_Shdr));
    
    Elf64_Shdr *shstrtab = &shdr[ehdr.e_shstrndx];
    char *shstrtab_data = malloc(shstrtab->sh_size);
    lseek(fd, shstrtab->sh_offset, SEEK_SET);
    read(fd, shstrtab_data, shstrtab->sh_size);
    
    Elf64_Shdr *section = NULL;
    for (int i = 0; i < ehdr.e_shnum; i++) {
        char *name = shstrtab_data + shdr[i].sh_name;
        if (strcmp(name, section_name) == 0) {
            section = &shdr[i];
            break;
        }
    }
    
    if (!section) {
        free(shstrtab_data);
        free(shdr);
        close(fd);
        return false;
    }
    
    long page_size = sysconf(_SC_PAGE_SIZE);
    off_t page_offset = (section->sh_offset / page_size) * page_size;
    size_t offset_in_page = section->sh_offset - page_offset;
    size_t map_size = offset_in_page + section->sh_size;
    
    void *base = mmap(NULL, map_size, PROT_READ, MAP_PRIVATE, fd, page_offset);
    
    free(shstrtab_data);
    free(shdr);
    close(fd);
    
    if (base == MAP_FAILED) return false;
    
    result->base = base;
    result->data = (unsigned char*)base + offset_in_page;
    result->map_size = map_size;
    result->data_size = section->sh_size;
    
    return true;
}

void unload_embedded_section(embedded_section_info *data) {
    munmap(data->base, data->map_size);
}
```

The section's file offset might not be page-aligned. So, it requires rounding down to the page boundary and skipping the extra bytes.

Note this particular code only works for Elf64, not Elf32.
Some trivial adjustments will make it work, but that is left as an exercise for the reader.

### Usage

```c
int main() {
    embedded_section_info texture;

    if (!load_embedded_section(".texture", &texture)) {
        fprintf(stderr, "Failed to load\n");
        return 1;
    }

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, texture.data);

    unload_embedded_section(&texture);
    return 0;
}
```

