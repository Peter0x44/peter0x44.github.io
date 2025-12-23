---
title: "How UTF-16 Encoding Works"
date: 2025-12-23T00:02:00+00:00
draft: false
tags: ["programming", "encoding", "unicode", "utf-16"]
categories: ["tutorials"]
comments: true
---

This post explains exactly how UTF-16 encodes Unicode code points into bytes. If you haven't read the history of how we got here, see [The History of Text Encoding]({{< ref "encoding-history.md" >}}).

## From UCS-2 to UTF-16

Originally, Unicode was designed to fit in 16 bits - the **Basic Multilingual Plane (BMP)**, covering code points U+0000 to U+FFFF. The encoding **UCS-2** simply stored each code point as a 16-bit integer.

When Unicode expanded beyond 65,536 characters (adding emoji, historical scripts, rare CJK characters, etc.), UCS-2 couldn't represent the new code points. **UTF-16** was created as a backward-compatible extension using **surrogate pairs**.

## The Encoding Scheme

UTF-16 uses 16-bit **code units**. A code point is encoded as either:
- **1 code unit** (2 bytes) for BMP characters (U+0000 to U+FFFF, excluding surrogates)
- **2 code units** (4 bytes) for supplementary characters (U+10000 to U+10FFFF)

### BMP Characters (Direct Encoding)

For code points U+0000 to U+FFFF (except U+D800-U+DFFF):

```
Code point → 16-bit code unit (identical value)
```

Example: U+0041 ('A') → `0x0041`
Example: U+4E2D ('中') → `0x4E2D`

### Supplementary Characters (Surrogate Pairs)

For code points U+10000 to U+10FFFF, we need more than 16 bits. UTF-16 uses a pair of 16-bit code units called **surrogates**:

- **High surrogate**: U+D800 to U+DBFF (1024 values)
- **Low surrogate**: U+DC00 to U+DFFF (1024 values)

Together, 1024 × 1024 = 1,048,576 combinations, exactly enough for code points U+10000 to U+10FFFF.

The surrogates themselves are not valid Unicode characters - they exist solely for this encoding mechanism.

## The Surrogate Pair Algorithm

### Encoding (Code Point → Surrogate Pair)

To encode a code point `cp` where cp ≥ U+10000:

1. Subtract 0x10000: `cp' = cp - 0x10000`
   - Result is a 20-bit number (0x00000 to 0xFFFFF)

2. Split into two 10-bit halves:
   - High 10 bits: `hi = cp' >> 10` (right shift by 10)
   - Low 10 bits: `lo = cp' & 0x3FF` (mask with 0b1111111111)

3. Add to surrogate bases:
   - High surrogate: `0xD800 + hi`
   - Low surrogate: `0xDC00 + lo`

### Decoding (Surrogate Pair → Code Point)

Given high surrogate `hs` and low surrogate `ls`:

1. Extract the 10-bit values:
   - `hi = hs - 0xD800`
   - `lo = ls - 0xDC00`

2. Combine and add offset:
   - `cp = 0x10000 + (hi << 10) + lo`

## Encoding Examples

### Example 1: ASCII Character 'A' (U+0041)

Code point: U+0041 = 65

Since 65 < 0x10000, use direct encoding:
- Code unit: `0x0041`

In bytes (big-endian): `00 41`
In bytes (little-endian): `41 00`

### Example 2: Chinese Character '中' (U+4E2D)

Code point: U+4E2D = 20013

Since 20013 < 0x10000, use direct encoding:
- Code unit: `0x4E2D`

In bytes (big-endian): `4E 2D`
In bytes (little-endian): `2D 4E`

### Example 3: Emoji '😀' (U+1F600)

Code point: U+1F600 = 128512

Since 128512 ≥ 0x10000, use surrogate pair:

**Step 1**: Subtract 0x10000
```
0x1F600 - 0x10000 = 0x0F600
```

**Step 2**: Split into 10-bit halves
```
0x0F600 = 0b00 0011 1101 | 10 0000 0000
              high 10 bits   low 10 bits
         
0x0F600 >> 10 = 0b0000111101 = 0x003D = 61
0x0F600 & 0x3FF = 0b1000000000 = 0x0200 = 512
```

**Step 3**: Add to surrogate bases
```
High surrogate: 0xD800 + 0x003D = 0xD83D
Low surrogate:  0xDC00 + 0x0200 = 0xDE00
```

Result: `0xD83D 0xDE00`

In bytes (big-endian): `D8 3D DE 00`
In bytes (little-endian): `3D D8 00 DE`

### Example 4: Musical Symbol (U+1D11E) - 𝄞

Code point: U+1D11E (G Clef)

**Step 1**: Subtract 0x10000
```
0x1D11E - 0x10000 = 0x0D11E
```

**Step 2**: Split into 10-bit halves
```
0x0D11E >> 10 = 0x34 = 52
0x0D11E & 0x3FF = 0x11E = 286
```

**Step 3**: Add to surrogate bases
```
High surrogate: 0xD800 + 0x34 = 0xD834
Low surrogate:  0xDC00 + 0x11E = 0xDD1E
```

Result: `0xD834 0xDD1E`

## Byte Order: UTF-16BE vs UTF-16LE

Unlike UTF-8, UTF-16's 16-bit code units are stored differently depending on byte order:

### Big-Endian (UTF-16BE)
Most significant byte first:
- `0x0041` → `00 41`
- `0x4E2D` → `4E 2D`

### Little-Endian (UTF-16LE)
Least significant byte first:
- `0x0041` → `41 00`
- `0x4E2D` → `2D 4E`

### The Byte Order Mark (BOM)

To indicate endianness, UTF-16 files often start with a **Byte Order Mark** - the code point U+FEFF:

- Big-endian: `FE FF`
- Little-endian: `FF FE`

When a decoder sees `FE FF` at the start, it knows the file is big-endian. When it sees `FF FE`, it knows it's little-endian.

Note: U+FFFE is permanently unassigned in Unicode specifically to make this detection unambiguous.

## Detecting Surrogates

You can check if a 16-bit code unit is a surrogate:

```c
bool is_high_surrogate(uint16_t cu) {
    return (cu >= 0xD800) && (cu <= 0xDBFF);
}

bool is_low_surrogate(uint16_t cu) {
    return (cu >= 0xDC00) && (cu <= 0xDFFF);
}

bool is_surrogate(uint16_t cu) {
    return (cu >= 0xD800) && (cu <= 0xDFFF);
}
```

## Reference Implementation

Here is a simple implementation of a UTF-16 encoder in C.

```c
// Encode code point to UTF-16, returns number of code units written
// Returns 0 if the code point is invalid
int utf16_encode(uint32_t cp, uint16_t *out) {
    // Check for invalid code points
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
        return 0;
    }
    
    if (cp < 0x10000) {
        // BMP character - direct encoding
        out[0] = (uint16_t)cp;
        return 1;
    } else {
        // Supplementary character - surrogate pair
        cp -= 0x10000;
        out[0] = 0xD800 + (cp >> 10);      // High surrogate
        out[1] = 0xDC00 + (cp & 0x3FF);    // Low surrogate
        return 2;
    }
}
```

And a decoder:

```c
// Decode UTF-16 to code point, returns number of code units consumed
int utf16_decode(const uint16_t *in, uint32_t *cp) {
    uint16_t cu = in[0];
    
    if (cu < 0xD800 || cu > 0xDFFF) {
        // BMP character
        *cp = cu;
        return 1;
    } else if (cu <= 0xDBFF) {
        // High surrogate - expect low surrogate next
        uint16_t next = in[1];
        if (next < 0xDC00 || next > 0xDFFF) {
            // Not a valid low surrogate
            return -1;
        }
        uint16_t hi = cu - 0xD800;
        uint16_t lo = next - 0xDC00;
        *cp = 0x10000 + (hi << 10) + lo;
        return 2;
    } else {
        // Lone low surrogate - error!
        return -1;
    }
}
```

## Validation and Error Handling

Invalid UTF-16 sequences include:

### Lone Surrogates
A high surrogate not followed by a low surrogate, or a low surrogate not preceded by a high surrogate:
- `D800` alone
- `DC00` alone
- `D800 D800` (two high surrogates)
- `DC00 DC00` (two low surrogates)

### Wrong Order
A low surrogate before a high surrogate:
- `DC00 D800` is invalid

These situations occur in real-world data, especially in:
- Filenames on Windows (NTFS allows invalid UTF-16)
- User input that was truncated mid-character
- Data corruption

Different systems handle these errors differently:
- Replace with U+FFFD (replacement character)
- Skip the invalid unit
- Treat as an error

## UTF-16 in the Wild

UTF-16 is used internally by:
- **Windows**: "Wide string" APIs (`wchar_t` is 16 bits, `W` suffix functions like `CreateFileW`)
- **Java and JavaScript**: Strings are sequences of 16-bit code units, so `"😀".length` returns 2, not 1
- **.NET**: strings are UTF-16 internally and exhibit the same behavior as JavaScript.

## Conclusion
Despite UTF-16's continued importance in some systems, UTF-8 has become the standard. Its ASCII compatibility makes it the preferred choice for a vast majority of applications. To understand how UTF-8 works, see [how UTF-8 encoding works]({{< ref "encoding-utf8.md" >}}).
