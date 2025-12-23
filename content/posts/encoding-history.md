---
title: "The History of Text Encoding: From ASCII to Unicode"
date: 2025-12-23T00:00:00+00:00
draft: false
tags: ["programming", "encoding", "unicode", "history"]
categories: ["tutorials"]
comments: true
---

Text encoding is a topic that not enough programmers understand well. It rarely appears on computer science curriculums, even at universities, yet it's something almost every developer will encounter in the real world. It underpins every file you save, every message you send, every webpage you load. This represents a widespread and ongoing failure in programming education.

When I first tried to learn about this topic, I found most articles confusing and poorly written. The top search results were either too abstract or buried the important details under walls of jargon. I ended up putting off learning this topic for years. This set of articles are a resource I wish I had back then.

This is a 3-part series:
1. **The History of Text Encoding** (this post)
   An explanation of the history of text encodings, giving context to how UTF-8 and UTF-16 arose.
2. [How UTF-8 Encoding Works](/posts/encoding-utf8)
   Explains how to encode and decode UTF-8.
3. [How UTF-16 Encoding Works](/posts/encoding-utf16)
   Explains how to encode and decode UTF-16.

NOTE: This history is as I understand it. I did make some inferences and assumptions. If something is wrong, feel free to correct me in the comments.

## ASCII: The Foundation

In 1963, the American Standard Code for Information Interchange (ASCII) was published to standardize character encoding. ASCII uses 7 bits to represent 128 characters:

- 0-31: Control characters (newline, tab, bell, etc.)
- 32-126: Printable characters (letters, digits, punctuation)
- 127: DEL (delete)

ASCII was elegant, but it had an obvious limitation: it could only represent 128 characters. This was fine for English, but what about other languages?

## The 8-bit Extensions

As computers spread globally, the need for additional characters became apparent. Since most systems used 8-bit bytes, the unused 8th bit in ASCII could represent 128 additional characters.

This led to a proliferation of various incompatible 8-bit encodings.

Some notable ones are:

- **ISO 8859-1 (Latin-1)**: Western European languages
- **ISO 8859-5**: Cyrillic alphabet
- **Windows-1252**: Microsoft's extension of Latin-1
- **Shift JIS**: Japanese characters

I won't go into any technical detail on these encodings because they are all obsolete.

This system had several problems:

**Locales and Code Pages are global state**. The active encoding is a process-wide setting that alters the behavior of core functions like `libc`. This makes it impossible to handle data from multiple legacy encodings simultaneously, as the system can only support one interpretation of bytes at a time.

**Files didn't store which encoding they used**. The same byte value meant different characters depending on the code page, but there was no standard metadata to indicate which one applied. Software had to guess based on the user's locale or code page, sometimes incorrectly. Opening a document with the wrong encoding would display nonsense (known as [mojibake](https://en.wikipedia.org/wiki/Mojibake)).

**256 characters was still too limiting**. Languages like Chinese, Japanese, and Korean have thousands of characters. This resulted in the creation of several complicated and flawed multi-byte encoding schemes for those languages.

**Documents couldn't mix languages**. Each code page was designed for a specific region or language family. You couldn't write a document that contained several of them.

## The Next Evolution: Unicode

During the 1980s, it was clear that a universal character set was needed. Two efforts emerged almost simultaneously:

1. **Unicode**
2. **ISO 10646**

These efforts merged in 1991. Unicode became the standard, synchronized with ISO 10646. 

Unicode defines a **character set**: an abstract mapping of characters to numbers called **code points**. A Unicode code point is written as U+XXXX, where XXXX is a hexadecimal number. For example:
- U+0041 = 'A'
- U+00E9 = 'é'
- U+4E2D = '中'
- U+1F600 = '😀'

Originally, Unicode aimed to fit all characters in 16 bits. This seemed sufficient at the time. However, as more scripts, emojis, etc were added, Unicode expanded to use 21 bits, supporting over 1.1 million code points (though only about 150,000 are currently assigned).

## UCS-2: The Original Unicode Encoding

The first Unicode encoding was **UCS-2**. It was simple: each code point was stored as a 16-bit integer. This worked for the original 65,536 code points (known collectively as the Basic Multilingual Plane or BMP).

Windows NT, Java, and JavaScript all adopted UCS-2 internally, betting that 16 bits would be enough.

They were wrong.

## The Need for More: Surrogate Pairs and UTF-16

When Unicode expanded beyond 65,536 code points, UCS-2 had a problem. The solution was **UTF-16**, a backward-compatible extension of UCS-2.

UTF-16 uses **surrogate pairs** to represent code points above U+FFFF:
- Code points U+0000 to U+FFFF (except surrogates) are stored as single 16-bit units (same as UCS-2)
- Code points U+10000 to U+10FFFF are stored as pairs of 16-bit units

The surrogate ranges (U+D800-U+DFFF) were reserved specifically for this purpose. They cannot represent characters.

For a more detailed explanation of how UTF-16 encoding works, see [How UTF-16 Encoding Works](/posts/encoding-utf16).

## UTF-8: The Encoding That Won the Web

Some time between the creation of UCS-2 and UTF-16, a different approach was being developed.

On Wednesday September 2 1992, Ken Thompson and Rob Pike (of Unix and Go fame) designed **UTF-8** at a New Jersey diner, sketching it on a placemat. Their goals were:

1. **ASCII compatibility**: Valid ASCII text is valid UTF-8
2. **Self-synchronization**: You can find character boundaries without reading from the start
3. **No embedded NULs**: Important for C strings (which use NUL as a terminator)
4. **Byte-order independent**: No endianness issues

By Friday of that same week, they had fully implemented it in the Plan 9 operating system.

You can find Rob Pike's first hand account of this here:
https://web.archive.org/web/20250706204918/https://doc.cat-v.org/bell_labs/utf-8_history

UTF-8 is a variable-width encoding using 1 to 4 bytes per character. It uses prefix codes to determine the length of the sequence:

- **1 byte**: `0xxxxxxx` (ASCII)
- **2 bytes**: `110xxxxx 10xxxxxx`
- **3 bytes**: `1110xxxx 10xxxxxx 10xxxxxx`
- **4 bytes**: `11110xxx 10xxxxxx 10xxxxxx 10xxxxxx`

For a detailed explanation of how UTF-8 encoding works, see [How UTF-8 Encoding Works](/posts/encoding-utf8).

## The Byte-Order-Mark

One issue with UTF-16 is **byte order**. A 16-bit value like 0x0041 ('A') can be stored as:
- `00 41` (big-endian, UTF-16BE)
- `41 00` (little-endian, UTF-16LE)

To indicate which byte order is used, files often start with a **Byte Order Mark (BOM)**: U+FEFF. In big-endian, this is `FE FF`; in little-endian, `FF FE`.

UTF-8 doesn't need a BOM, because it operates only on single bytes, but sometimes one is added (`EF BB BF`) to signal "this is UTF-8.".
It mostly serves the purpose of preventing misdetection by shoddy encoding detection heuristics, like the ["Bush hid the facts"](https://en.wikipedia.org/wiki/Bush_hid_the_facts) problem.

## UTF-8 vs UTF-16: The Trade-offs

**UTF-8 advantages:**
- ASCII-compatible
- No byte-order issues
- Compact for ASCII-heavy text
- Self-synchronizing

**UTF-16 advantages:**
- More compact for texts heavy in BMP characters (CJK languages)

It should be clear that UTF-16 is inferior to UTF-8 in every important way.

## Conclusion

The industry has gone from ASCII, through the chaos of code pages and locales, ultimately arriving at the universal standard of Unicode.

While the journey was messy, the destination is clear: **UTF-8 has won**. It is the default encoding for the web. However, some historical ghosts remain. You will still encounter UTF-16 in Windows APIs, Java, Qt, and JavaScript.

Now that you understand the context, you are ready to understand the implementation. In the next parts, we'll look at the bit-level details of how these encodings actually work:

- [How UTF-8 Encoding Works](/posts/encoding-utf8)
- [How UTF-16 Encoding Works](/posts/encoding-utf16)
