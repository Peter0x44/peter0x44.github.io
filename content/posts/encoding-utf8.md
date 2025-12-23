---
title: "How UTF-8 Encoding Works"
date: 2025-12-23T00:01:00+00:00
draft: false
tags: ["programming", "encoding", "unicode", "utf-8"]
categories: ["tutorials"]
comments: true
---

This post explains exactly how UTF-8 encodes Unicode code points into bytes. If you haven't read the history of how we got here, see [The History of Text Encoding]({{< ref "encoding-history.md" >}}).

## The Design Goals

UTF-8 was designed by Ken Thompson and Rob Pike with specific goals in mind:

1. **ASCII compatibility**: Bytes 0x00-0x7F mean exactly what they mean in ASCII
2. **Self-synchronization**: You can identify character boundaries from any position
3. **No NUL bytes**: Except for the actual NUL character (U+0000), no byte is ever 0x00
4. **Sortable**: Byte-wise sorting of UTF-8 strings sorts by code point order

## The Encoding Scheme

UTF-8 uses a variable number of bytes (1-4) depending on the code point:

| Code Point Range | Bytes | Byte 1 | Byte 2 | Byte 3 | Byte 4 |
|------------------|-------|--------|--------|--------|--------|
| U+0000 - U+007F | 1 | `0xxxxxxx` | | | |
| U+0080 - U+07FF | 2 | `110xxxxx` | `10xxxxxx` | | |
| U+0800 - U+FFFF | 3 | `1110xxxx` | `10xxxxxx` | `10xxxxxx` | |
| U+10000 - U+10FFFF | 4 | `11110xxx` | `10xxxxxx` | `10xxxxxx` | `10xxxxxx` |

The `x` bits are filled with the binary representation of the code point.

### Understanding the Bit Patterns

The leading byte tells you how many bytes are in this character:
- `0xxxxxxx`: 1-byte character (ASCII)
- `110xxxxx`: 2-byte character (first of 2)
- `1110xxxx`: 3-byte character (first of 3)
- `11110xxx`: 4-byte character (first of 4)

Continuation bytes always start with `10`:
- `10xxxxxx`: Continuation byte

This design enables self-synchronization. If you land in the middle of a character, you can scan backward or forward to find a leading byte (anything that doesn't start with `10`).

## Encoding Examples

### Example 1: ASCII Character 'A' (U+0041)

Code point: U+0041 = 65 = `0100 0001` in binary

Since 65 < 128, we use 1 byte:
```
0xxxxxxx
0100 0001
```

Result: `0x41` (identical to ASCII)

### Example 2: Latin Character 'é' (U+00E9)

Code point: U+00E9 = 233 = `1110 1001` in binary

Since 128 ≤ 233 < 2048, we use 2 bytes. We need to fit 8 bits into the pattern:
```
110xxxxx 10xxxxxx
```

Split the code point bits (we need 11 bits total, pad with zeros on the left):
- 233 = `000 1110 1001`
- First 5 bits: `00011` → `110 00011` = `0xC3`
- Last 6 bits: `101001` → `10 101001` = `0xA9`

Result: `0xC3 0xA9`

### Example 3: Chinese Character '中' (U+4E2D)

Code point: U+4E2D = 20013 = `0100 1110 0010 1101` in binary

Since 2048 ≤ 20013 < 65536, we use 3 bytes:
```
1110xxxx 10xxxxxx 10xxxxxx
```

Split 16 bits into 4 + 6 + 6:
- `0100 1110 0010 1101`
- First 4 bits: `0100` → `1110 0100` = `0xE4`
- Next 6 bits: `111000` → `10 111000` = `0xB8`
- Last 6 bits: `101101` → `10 101101` = `0xAD`

Result: `0xE4 0xB8 0xAD`

### Example 4: Emoji '😀' (U+1F600)

Code point: U+1F600 = 128512 = `0001 1111 0110 0000 0000` in binary

Since 65536 ≤ 128512, we use 4 bytes:
```
11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
```

Split 21 bits into 3 + 6 + 6 + 6:
- `0 0001 1111 0110 0000 0000` (padded to 21 bits)
- First 3 bits: `000` → `11110 000` = `0xF0`
- Next 6 bits: `011111` → `10 011111` = `0x9F`
- Next 6 bits: `011000` → `10 011000` = `0x98`
- Last 6 bits: `000000` → `10 000000` = `0x80`

Result: `0xF0 0x9F 0x98 0x80`

## Decoding UTF-8

To decode, you reverse the process:

1. Read the first byte
2. Determine the length from the leading bits
3. Read continuation bytes
4. Extract and concatenate the payload bits
5. Interpret as a code point

### Example: Decoding `0xC3 0xA9`

1. First byte: `0xC3` = `1100 0011`
2. Pattern `110xxxxx` → 2-byte sequence
3. Extract bits: `00011` from first byte
4. Second byte: `0xA9` = `1010 1001`
5. Pattern `10xxxxxx` → continuation, extract `101001`
6. Concatenate: `00011` + `101001` = `000 1110 1001` = 233 = U+00E9 = 'é'

## Validation and Error Handling

Not all byte sequences are valid UTF-8. Invalid sequences include:

### Overlong Encodings

Using more bytes than necessary is invalid. For example, 'A' (U+0041) must be encoded as `0x41`, not as:
- `0xC1 0x81` (2-byte form)
- `0xE0 0x81 0x81` (3-byte form)

### Invalid Continuation Bytes

A continuation byte (`10xxxxxx`) cannot appear as the first byte:
- `0x80` alone is invalid
- `0xC3` without a continuation byte is invalid

### Invalid Byte Values

Some byte values never appear in valid UTF-8:
- `0xC0`, `0xC1`: Would only be used for overlong encodings of ASCII
- `0xF5`-`0xFF`: Would encode code points beyond U+10FFFF

### Surrogate Code Points

The range U+D800-U+DFFF (surrogates used by UTF-16) are invalid UTF-8.

## Reference Implementation

Here is a simple implementation of a UTF-8 encoder in C.

```c
// Encode a code point to UTF-8, returns number of bytes written
// Returns 0 if the code point is invalid
int utf8_encode(uint32_t cp, uint8_t *out) {
    // Check for invalid code points
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
        return 0;
    }

    if (cp < 0x80) {
        out[0] = cp;
        return 1;
    } else if (cp < 0x800) {
        out[0] = 0xC0 | (cp >> 6);
        out[1] = 0x80 | (cp & 0x3F);
        return 2;
    } else if (cp < 0x10000) {
        out[0] = 0xE0 | (cp >> 12);
        out[1] = 0x80 | ((cp >> 6) & 0x3F);
        out[2] = 0x80 | (cp & 0x3F);
        return 3;
    } else {
        out[0] = 0xF0 | (cp >> 18);
        out[1] = 0x80 | ((cp >> 12) & 0x3F);
        out[2] = 0x80 | ((cp >> 6) & 0x3F);
        out[3] = 0x80 | (cp & 0x3F);
        return 4;
    }
}
```

And a decoder:

```c
// Decode UTF-8 to a code point, returns number of bytes consumed
// Returns 0 if the sequence is invalid.
int utf8_decode(const uint8_t *in, uint32_t *cp) {
    if ((in[0] & 0x80) == 0) {
        *cp = in[0];
        return 1;
    }
    
    uint32_t code_point = 0;
    int bytes = 0;
    
    if ((in[0] & 0xE0) == 0xC0) {
        code_point = in[0] & 0x1F;
        bytes = 2;
    } else if ((in[0] & 0xF0) == 0xE0) {
        code_point = in[0] & 0x0F;
        bytes = 3;
    } else if ((in[0] & 0xF8) == 0xF0) {
        code_point = in[0] & 0x07;
        bytes = 4;
    } else {
        return 0; // Invalid start byte
    }

    for (int i = 1; i < bytes; i++) {
        if ((in[i] & 0xC0) != 0x80) return 0; // Invalid continuation
        code_point = (code_point << 6) | (in[i] & 0x3F);
    }

    // Check for overlong encodings
    if (bytes == 2 && code_point < 0x80) return 0;
    if (bytes == 3 && code_point < 0x800) return 0;
    if (bytes == 4 && code_point < 0x10000) return 0;

    // Check for surrogates (U+D800 - U+DFFF)
    if (code_point >= 0xD800 && code_point <= 0xDFFF) return 0;

    // Check for max value
    if (code_point > 0x10FFFF) return 0;

    *cp = code_point;
    return bytes;
}
```

## Conclusion

UTF-8 has become the dominant text encoding for the web and data interchange. However, some platforms like Windows, Java, and JavaScript still use UTF-16 internally. To understand how UTF-16 works and why these systems use it, see [how UTF-16 encoding works]({{< ref "encoding-utf16.md" >}}).
