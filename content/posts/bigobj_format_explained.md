---
title: "BigObj COFF Object Files: Binary Structure Explained"
date: 2025-09-28T12:00:00Z
draft: false
tags: ["programming", "windows", "compilers", "coff", "toolchains"]
comments: true
---

I recently implemented BigObj COFF file parsing in cgo ([golang/go#24341](https://github.com/golang/go/issues/24341)). In the process, I quickly discovered that Microsoft doesn't document the binary format anywhere. Their [official documentation](https://learn.microsoft.com/en-us/cpp/build/reference/bigobj-increase-number-of-sections-in-dot-obj-file?view=msvc-170) is the only reference they have to BigObj as far as I can tell, and it doesn't say anything about the binary format. I didn't see any other blogs or resources covering this topic either.

I figured it out by reading binutils and LLVM source code, so I'm documenting what I learned while the knowledge is still fresh in my memory.

I'm assuming readers are already familiar with COFF and how it's structured. This post focuses specifically on how BigObj differs from regular COFF object files.

## Header Structure

The first difference is the file header. Regular COFF files start with an `IMAGE_FILE_HEADER`, but BigObj files use a completely different header structure called `ANON_OBJECT_HEADER_BIGOBJ` (defined in `winnt.h`).

### Regular COFF Header (IMAGE_FILE_HEADER)
```c
typedef struct {
    WORD  Machine;
    WORD  NumberOfSections;     // 16-bit
    DWORD TimeDateStamp;
    DWORD PointerToSymbolTable;
    DWORD NumberOfSymbols;
    WORD  SizeOfOptionalHeader;
    WORD  Characteristics;
} IMAGE_FILE_HEADER;
```

### BigObj Header (ANON_OBJECT_HEADER_BIGOBJ)

```c
typedef struct {
    WORD  Sig1;                 // Must be 0x0
    WORD  Sig2;                 // Must be 0xFFFF
    WORD  Version;              // Currently 2
    WORD  Machine;
    DWORD TimeDateStamp;
    BYTE  ClassID[16];          // Magic bytes that identify this as bigobj format
    DWORD SizeOfData;
    DWORD Flags;
    DWORD MetaDataSize;
    DWORD MetaDataOffset;
    DWORD NumberOfSections;     // 32-bit field (16-bit in regular COFF)
    DWORD PointerToSymbolTable;
    DWORD NumberOfSymbols;
} ANON_OBJECT_HEADER_BIGOBJ;
```

### Differences

Comparing the two headers reveals several differences:

- **Supports more sections**: `NumberOfSections` expands from 16-bit to 32-bit. Obviously, this is the entire point of the format!
- **Format identification**: BigObj adds `Sig1`, `Sig2`, `Version`, and `ClassID`. I will explain these later.
- **Removed optional header**: No `SizeOfOptionalHeader` field (the optional header is only applicable to executables anyway)
- **Removed characteristics**: No `Characteristics` field (also only applicable to executables)
- **Additional metadata??**: BigObj adds `SizeOfData`, `Flags`, `MetaDataSize`, and `MetaDataOffset` fields. In practice, these are unused (every toolchain I checked sets them to zero). I am not sure what they are for.

### Detection

To detect whether a file is BigObj format, you need to check the following:

A valid BigObj file will always have these properties:
- `Sig1` = `0x0000` and `Sig2` = `0xFFFF` 
- `Version` is always `2`. Not sure if this needs to be checked.
- `ClassID` must match these magic bytes:
`{0xC7, 0xA1, 0xBA, 0xD1, 0xEE, 0xBA, 0xA9, 0x4B, 0xAF, 0x20, 0xFA, 0xF6, 0x6A, 0xA4, 0xDC, 0xB8}`

## Symbol Structure

BigObj also uses a different symbol format. While regular COFF symbols are 18 bytes each, BigObj symbols are 20 bytes, due to the 32-bit SectionNumber field.

### Regular COFF Symbol
```c
typedef struct {
    BYTE  Name[8];
    DWORD Value;
    WORD  SectionNumber;        // 16-bit
    WORD  Type;
    BYTE  StorageClass;
    BYTE  NumberOfAuxSymbols;
} IMAGE_SYMBOL;
```

### BigObj Symbol
```c
typedef struct {
    BYTE  Name[8];
    DWORD Value;
    DWORD SectionNumber;        // 32-bit!
    WORD  Type;
    BYTE  StorageClass;
    BYTE  NumberOfAuxSymbols;
} IMAGE_SYMBOL_EX;
```

You need to take this into account when indexing and reading the symbol table.

## Symbol Table Parsing

The `Name` field of the symbol is actually a union.
You can conceptually think of it like this:
```c
typedef union {
    BYTE ShortName[8];          // Name <= 8 chars: stored directly
    struct {
        DWORD Zeroes;           // 0x00000000 indicates long name
        DWORD Offset;           // Offset into string table
    } LongName;
} SYMBOL_NAME;
```

If the name of the symbol is more than 8 bytes, it is instead stored in the string table, and the latter 4 bytes of Name are an offset into the string table.
This applies to both regular COFF and BigObj.

The string table immediately follows the symbol table, so you need to take into account the symbol size to locate it:
```c
// Calculate string table location
DWORD stringTableStart;

if (isBigObj) {
    // BigObj: sizeof(IMAGE_SYMBOL_EX) = 20 bytes per symbol
    stringTableStart = header->PointerToSymbolTable + 
                      (sizeof(IMAGE_SYMBOL_EX) * header->NumberOfSymbols);
} else {
    // Regular COFF: sizeof(IMAGE_SYMBOL) = 18 bytes per symbol  
    stringTableStart = header->PointerToSymbolTable + 
                      (sizeof(IMAGE_SYMBOL) * header->NumberOfSymbols);
}
```

The first 4 bytes of the string table are its total size in bytes (including those initial 4 bytes).

## Conclusion

The key changes that BigObj makes are minimal:
- A different header structure
- 32-bit section counts instead of 16-bit  
- 32-bit symbol section numbers instead of 16-bit
- 20-byte symbols instead of 18-byte symbols

Everything else works exactly like regular COFF. Implementing BigObj support is relatively straightforward once you understand these differences.

Hopefully this saves someone else from having to dig through binutils and LLVM source like I did!