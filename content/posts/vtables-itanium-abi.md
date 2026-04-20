---
title: "How Virtual Tables Work in the Itanium C++ ABI"
date: 2026-02-28T12:00:00Z
draft: false
tags: ["programming", "c++", "compilers", "abi"]
comments: true
---

Virtual functions are one of C++'s core features, enabling runtime polymorphism. Most C++ programmers use them regularly, yet few understand how they work in practice. What does the compiler actually generate when you declare a function `virtual`? How does the program figure out which implementation to call at runtime? Where is the vtable data actually stored? This blog post is focused on answering these questions.

The C++ standard specifies behavior but not implementation. This post describes the [Itanium C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html) used by most platforms, with the notable exception of Microsoft MSVC.


## A Basic Example

Consider these classes with virtual functions:

```cpp
struct Base {
    virtual void foo() { __builtin_printf("Base::foo\n"); }
    virtual void bar() { __builtin_printf("Base::bar\n"); }
    virtual ~Base() {}
};

struct Derived : Base {
    void foo() override { __builtin_printf("Derived::foo\n"); }
};

void call_foo(Base* b) {
    b->foo();  // Which foo() gets called?
}

int main() {
    Base base;
    Derived derived;
    call_foo(&base);     // Should call Base::foo
    call_foo(&derived);  // Should call Derived::foo
}
```

The compiler doesn't know at compile time what type `b` points to in `call_foo()`. The function needs to dispatch to the correct `foo()` implementation based on the actual runtime type of the object. This is what vtables (short for virtual tables) enable.

## The Virtual Table Structure

Let's see what a vtable actually looks like. GCC has a useful flag `-fdump-lang-class` that dumps the class and vtable layout:

```bash
g++ -fdump-lang-class example.cpp
```

GCC should emit a file named `a-example.cpp.001l.class` containing info about the classes and vtables dumps.

Clang can dump similar information too, although the interface is different:

```bash
clang++ -Xclang -fdump-record-layouts -Xclang -fdump-vtable-layouts example.cpp
```

I learned about this from [Dumping a C++ object's memory layout with Clang](https://eli.thegreenplace.net/2012/12/17/dumping-a-c-objects-memory-layout-with-clang).

I think GCC has a slightly nicer output format, so all quoted output below is from `gcc -fdump-lang-class`.

For our `Base` class, GCC outputs:

```
Vtable for Base
Base::_ZTV4Base: 6 entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI4Base)
16    (int (*)(...))Base::foo
24    (int (*)(...))Base::bar
32    (int (*)(...))Base::~Base
40    (int (*)(...))Base::~Base

Class Base
   size=8 align=8
   base size=8 base align=8
Base (0x0x23116c0) 0
    vptr=((& Base::_ZTV4Base) + 16)
```

Let's break down what we're seeing here.

### Mangled Names

Before looking at the entries, notice the symbol name: `_ZTV4Base`. This is the **mangled name** for the vtable.

- `_Z` prefix indicates Itanium name mangling
- `T` is a special name prefix (used for vtables, typeinfo, thunks, and other compiler-generated symbols)
- `V` means vtable (`I` is typeinfo)
- `4` is the length of the following name
- `Base` is the class name

Similarly:
- `_ZTV7Derived` = vtable for Derived
- `_ZTI4Base` = typeinfo for Base

### Vtable Layout

The vtable named `_ZTV4Base` has 6 entries, each 8 bytes apart (on a 64-bit system). The structure is:

```
Offset 0:  offset-to-top       = 0
Offset 8:  typeinfo pointer    = &_ZTI4Base
Offset 16: foo()                = &Base::foo
Offset 24: bar()                = &Base::bar
Offset 32: ~Base()              = &Base::~Base (D1)(complete object destructor)
Offset 40: ~Base()              = &Base::~Base (D0)(deleting destructor)
```

### Virtual Function Pointers

Each virtual function declared in the class gets an entry in the vtable, in declaration order. Functions declared in `Base` are `foo()`, `bar()`, and the destructor.

Destructors get two vtable entries in the Itanium ABI:
- **Complete object destructor (D1)** (offset 32): Destroys the object but doesn't free memory. Used for stack objects, members, and array elements.
- **Deleting destructor (D0)** (offset 40): Calls the complete destructor (D1), then calls `operator delete` to free memory. Used when you write `delete ptr`.

There's also a third variant, the **base object destructor (D2)**, which doesn't appear in vtables and is only called directly by derived destructors. We'll see why it exists when we look at virtual inheritance.

### Offset-to-Top

This field records how far the vptr sits from the start of the complete object. In single inheritance, its value is zero, so it looks uninteresting. It becomes important once multiple inheritance is involved.

### RTTI Typeinfo Pointer

The typeinfo pointer enables runtime type identification (RTTI). It points to a `std::type_info` object for the class, which is used by `dynamic_cast`, `typeid`, and exception handling.

If `-fno-rtti` is used, this field is null.

## Where Do Vtables Live?

Vtables are static data structures that live in the `.rodata` section of the binary. But which translation unit actually emits them?

The Itanium ABI uses the **key function rule**: the vtable is emitted in the translation unit that defines the first non-inline virtual function.

```cpp
// base.h
struct Base {
    virtual void foo() { /* ... */ }; // Inline, not the key function
    virtual void bar(); // Not inline - this is the key function
    virtual ~Base();
};

// base.cpp
void Base::bar() { /* ... */ }  // key function - vtable will be in this TU

// Vtable for Base is emitted in base.cpp
```

This rule is the source of a common linker error:

```
undefined reference to `vtable for Base'
```

This happens when the key function is declared but not defined anywhere.

If all virtual functions are inline, there's no key function. The vtable is instead emitted with weak linkage in every translation unit that uses the class.

## Object Layout: The VPtr

Each object that has virtual functions contains a hidden member called the **virtual table pointer** (vptr for short). In this simple case using only single-inheritance, it sits at offset 0 of the object. Virtual dispatch reads `*(void**)this` to find the vtable.

With multiple inheritance there are several vptrs (one per base class). I will cover that later.

```
Class Base
   size=8 align=8
   base size=8 base align=8
Base (0x0x22606c0) 0 nearly-empty
    vptr=((& Base::_ZTV4Base) + 16)
```

Note that the vptr doesn't point to the start of the vtable. Instead, it points to the vtable's **address point**. In this case, it is the first function entry in the vtable (+16). The typeinfo pointer and offset-to-top live at negative offsets from the address point.

You can imagine, conceptually, that the compiler is turning this:
```cpp
struct Base {
    virtual void foo();
    int x;
};
```
Into something like:
```cpp
struct Base {
    void** __vptr;  // Points to vtable
    int x;
};
```

## Inheritance: Vtable Extension

When a derived class overrides virtual functions, it gets its own vtable based on the base class layout:

```cpp
struct Derived : Base {
    void foo() override;
    virtual void baz();
};
```

```
vtable for Derived:
  [offset-to-top]      = 0
  [typeinfo]           = &typeinfo for Derived
  [foo()]              = &Derived::foo        (overridden)
  [bar()]              = &Base::bar           (inherited)
  [~Derived()]         = &Derived::~Derived   (complete object destructor)
  [~Derived()]         = &Derived::~Derived   (deleting destructor)
  [baz()]              = &Derived::baz        (new virtual function)
```

The inherited slots stay in the same positions. The function at offset 0 is still `foo()`, it just points to a different implementation.

So `foo()` is replaced with `Derived::foo`, `bar()` still points to the base implementation, and `baz()` is appended at the end.

## Virtual Function Calls: The Dispatch Mechanism

Now let's see what actually happens when you call a virtual function:

```cpp
void call_foo(Base* b) {
    b->foo();
}
```

The compiler transforms this roughly into:

```cpp
void call_foo(Base* b) {
    // Load the vptr from the object
    void** vtable = *(void***)b;
    
    // Load the function pointer from the vtable
    //    foo() is at index 0
    void (*func)(Base*) = (void(*)(Base*))vtable[0];
    
    // Call the function
    func(b);
}
```

Here's what GCC generated for `call_foo` with `-Os`:
```asm
call_foo(Base*):
        movq    (%rdi), %rax # load vptr
        jmp     *(%rax)      # call first function in vtable
```
If `foo` was the second function in the vtable, the call would instead look like:
```asm
        jmp     *8(%rax)      # call second function in vtable
```
Because `call_foo` doesn't need to do anything after the virtual function returns, GCC chose to turn this into a tail call (jmp instead of call). Neat.

## Multiple Inheritance: One Object, Multiple Vptrs

So far, the model has been simple: one vptr at the start of the object, and one vtable corresponding to the object. Multiple inheritance adds more complexity on top.

Consider:

```cpp
struct Left {
    virtual void left_func() {}
    int left_data;
};

struct Right {
    virtual void right_func() {}
    int right_data;
};

struct MultiDerived : Left, Right {
    void left_func() override {}
    [[gnu::noinline]] void right_func() override { right_data = 42; }
};

int main() {
    MultiDerived md;
    MultiDerived* md_ptr = &md;
    Right* r_ptr = md_ptr;  // cast adds 16 bytes
    __builtin_printf("MultiDerived* : %p\n", (void*)md_ptr);
    __builtin_printf("Right*        : %p\n", (void*)r_ptr);
}
```
A `MultiDerived` object has to work as both a `Left*` and a `Right*`. This means it contains a `Left` part and a `Right` part. Those embedded base-class parts are what the ABI calls **base subobjects**.

The actual layout is something like this:

```cpp
struct MultiDerived {
    // Left base subobject
    void** __vptr_Left;
    int left_data;

    // Right base subobject
    void** __vptr_Right;
    int right_data;
};
```

If the compiler has a `MultiDerived*`, it knows this layout at compile time, so accesses like `md_ptr->left_data` and `md_ptr->right_data` are just fixed offsets from the start of the complete object.

The tricky part is making the base pointers work too:

- `Left*` should point to the `Left` part of the object
- `Right*` should point to the `Right` part of the object

In this example, the `Left` part is at offset 0, so `MultiDerived*` and `Left*` have the same address. The `Right` part is 16 bytes later, so casting a `MultiDerived*` to `Right*` will add 16 bytes to the pointer. That is what the printf of the pointer demonstrates.

Because both base subobjects are polymorphic, a `Left*` must be able to find a `Left`-compatible vtable from the start of the `Left` part, and a `Right*` must be able to find a `Right`-compatible vtable from the start of the `Right` part. That is why the object has two vptrs. 

Let's inspect the layout using GCC's `-fdump-lang-class` to see how this is implemented:

```
Vtable for MultiDerived
MultiDerived::_ZTV12MultiDerived: 7 entries
0     (int (*)(...))0
8     (int (*)(...))(& _ZTI12MultiDerived)
16    (int (*)(...))MultiDerived::left_func
24    (int (*)(...))MultiDerived::right_func
32    (int (*)(...))-16
40    (int (*)(...))(& _ZTI12MultiDerived)
48    (int (*)(...))MultiDerived::_ZThn16_N12MultiDerived10right_funcEv

Class MultiDerived
   size=32 align=8
   base size=28 base align=8
MultiDerived (0x0x23aa000) 0
    vptr=((& MultiDerived::_ZTV12MultiDerived) + 16)
Left (0x0x2311960) 0
      primary-for MultiDerived (0x0x23aa000)
Right (0x0x23119c0) 16
      vptr=((& MultiDerived::_ZTV12MultiDerived) + 48)
```

The class dump shows that there are **two vptrs**, one at offset 0 for the `Left` part and another at offset 16 for the `Right` part.

Both vptrs point into the same `_ZTV12MultiDerived` symbol at different offsets. This symbol is a **virtual table group**: a primary virtual table followed by one or more **secondary virtual tables**, one per non-primary base class:

**Primary virtual table** (for `Left`, entries at offsets 0-24):
```
Offset  0: offset-to-top = 0
Offset  8: typeinfo pointer
Offset 16: left_func     = &MultiDerived::left_func
Offset 24: right_func    = &MultiDerived::right_func
```

**Secondary virtual table** (for `Right`, entries at offsets 32-48):
```
Offset 32: offset-to-top = -16
Offset 40: typeinfo pointer
Offset 48: right_func    = &MultiDerived::_ZThn16_N12MultiDerived10right_funcEv  (thunk)
```

The `Right` subobject lives at offset 16 within `MultiDerived`. When you cast `MultiDerived*` to `Right*`, the compiler adds 16 bytes to the pointer so that member accesses e.g. `r->right_data` (which are fixed offsets from `this`) land on the correct fields. The pointer now points to the `Right` vptr, which points into the corresponding virtual table.

The secondary virtual table is the interesting one. A call through `Right*` starts from a pointer to the `Right` part of the object, so it has to use the `Right` vptr and the `Right` view of the virtual table.

The `right_func` slot in the `Right` secondary virtual table doesn't point directly at `MultiDerived::right_func`. Instead it points at a **non-virtual thunk**: a tiny wrapper that adjusts `this` from the `Right` subobject back to the complete object, then calls the real implementation. Because that adjustment is fixed for this class layout, it can be hardcoded into the thunk. Hence it is "non-virtual".

Its mangled name breaks down as:

- `_Z` - Itanium mangling prefix
- `T` - start of a special-name (same meaning as in `TV` for vtables)
- `h` - non-virtual call-offset thunk (virtual thunks are `v` instead)
- `n16` - the adjustment: `n` prefix means negative, so -16
- `_` - end of call-offset
- `N12MultiDerived10right_funcEv` - the target function (`MultiDerived::right_func()`)

GCC emits this code:

```asm
        .set    .LTHUNK0,_ZN12MultiDerived10right_funcEv
_ZThn16_N12MultiDerived10right_funcEv:
        subq    $16, %rdi
        jmp     .LTHUNK0
```

In C++, this is roughly:

```cpp
void non_virtual_thunk_to_MultiDerived_right_func(Right* this) {
    MultiDerived* complete = (MultiDerived*)((char*)this - 16);
    MultiDerived::right_func(complete);
}
```

The `.set` creates a local alias for `MultiDerived::right_func`. The thunk then calls that alias rather than the external symbol directly, which avoids going through the PLT on Linux.

The **offset-to-top** field lets runtime code find the start of the complete object from a base subobject pointer. The main user is `dynamic_cast`: `dynamic_cast<void*>(r)` reads `offset-to-top` from the secondary vtable and adds it to `this` to find the most-derived object.

To summarize, a suitable multiple-inheritance mental model is:

- one object can contain multiple polymorphic base-class parts
- converting to a base pointer may change the address
- each polymorphic base part gets its own vptr and vtable view
- calls through a non-primary base may need a thunk to repair `this` using a hardcoded adjustment
- `offset-to-top` lets runtime code recover the start of the complete object from any base subobject pointer

## Virtual Inheritance

Virtual inheritance is C++'s solution to the [diamond problem](https://en.wikipedia.org/wiki/Multiple_inheritance#The_diamond_problem). Consider:

```cpp
struct Base {
    virtual void f();
    int x;
};

struct Left : virtual Base {
    virtual void g();
};

struct Right : virtual Base {
    virtual void h();
};

struct Derived : Left, Right {
    void f() override;
};
```

The `virtual` keyword on `Left : virtual Base` and `Right : virtual Base` tells the compiler that `Base` is a *virtual base*: all paths through the inheritance graph share a single `Base` subobject. Without it, `Derived` would contain two separate `Base` copies (one through `Left` and one through `Right`), so accessing `Base::x` through `Derived` would be ambiguous. This is the diamond problem.

Sharing the base is what we want, but it breaks the assumption behind the previous section's thunks. With ordinary multiple inheritance, every base subobject sits at a fixed offset from the complete object, so a non-virtual thunk can hardcode the adjustment. With virtual inheritance, the offset to a virtual base depends on the final most-derived type. `Left` does not know where `Base` will end up when embedded inside `Derived`. That is only known when laying out the complete object.

That has several consequences:

- dispatch through a virtual base needs a runtime-determined `this` adjustment
- construction cannot assume each base's standalone vtable layout
- destruction has to avoid destroying the shared base more than once

The next sections will cover the various strategies the ABI uses to deal with this.

### Virtual Thunks

In the previous section, a non-virtual thunk hardcoded the adjustment (`subq $16, %rdi`). With virtual inheritance that is not possible because the offset to a virtual base depends on the complete type. The fix is two new kinds of vtable slot, and a thunk that reads from them at runtime.

Let's look at the GCC output for the `Derived` hierarchy first:

```
Class Derived
   size=32 align=8
   base size=16 base align=8
Derived (0x0x77a8cf3dc000) 0
    vptridx=0 vptr=((& Derived::_ZTV7Derived) + 24)
Left (0x0x77a8cf20e3a8) 0 nearly-empty
      primary-for Derived (0x0x77a8cf3dc000)
      subvttidx=8
Base (0x0x77a8cf3d52a0) 16 virtual
        vptridx=40 vbaseoffset=-24 vptr=((& Derived::_ZTV7Derived) + 96)
Right (0x0x77a8cf20e410) 8 nearly-empty
      subvttidx=24 vptridx=48 vptr=((& Derived::_ZTV7Derived) + 64)
Base (0x0x77a8cf3d52a0) alternative-path
```

The layout is:
- offset 0: `Left` subobject
- offset 8: `Right` subobject
- offset 16: shared `Base` subobject (vptr at 16, `int x` at 24)

The vtable group for `Derived` has three sections:

```
Vtable for Derived
Derived::_ZTV7Derived: 13 entries
0     16                  <- vptr[-3]: vbase offset (Base is +16 from Left's vptr)
8     (int (*)(...))0     <- vptr[-2]: offset-to-top = 0
16    (int (*)(...))(& _ZTI7Derived)   <- vptr[-1]: typeinfo
24    (int (*)(...))Left::g            <- vptr[0]:  address point
32    (int (*)(...))Derived::f         <- vptr[1]

40    8                   <- vptr[-3]: vbase offset (Base is +8 from Right's vptr)
48    (int (*)(...))-8    <- vptr[-2]: offset-to-top = -8
56    (int (*)(...))(& _ZTI7Derived)   <- vptr[-1]: typeinfo
64    (int (*)(...))Right::h           <- vptr[0]:  address point

72    -16  <- vptr[-3]: vcall offset for Base's f() thunk
80    (int (*)(...))-16   <- vptr[-2]: offset-to-top = -16
88    (int (*)(...))(& _ZTI7Derived)   <- vptr[-1]: typeinfo
96    (int (*)(...))Derived::_ZTv0_n24_N7Derived1fEv  <- vptr[0]: virtual thunk for f()
```

The `Left` and `Right` sections each start with a **vbase offset** at `vptr[-3]`. A vbase offset is used to navigate *from a subobject to its virtual base* — it answers "where is `Base` relative to this vptr?" For `Left` that is `+16`; for `Right`, `+8`. Any code that needs to reach `Base` from a `Left*` or `Right*` reads this slot at runtime. 

The `Base` section has a **vcall offset** at `vptr[-3]` instead: `-16`. A vcall offset navigates in the opposite direction — *from the virtual base back to the complete object*. It is read exclusively by virtual thunks to adjust a `Base*` back up to `Derived` before jumping to the actual implementation:

Now, lets have a look at generated code for a virtual thunk:
```asm
virtual thunk to Derived::f():      # _ZTv0_n24_N7Derived1fEv
        movq    (%rdi), %r10        # load vptr
        addq    -24(%r10), %rdi     # read vcall offset from vptr[-3], adjust this
        jmp     .LTHUNK0            # jump to Derived::f()
```

In C++, this is roughly:

```cpp
void virtual_thunk_to_Derived_f(Base* this) {
    void** vptr = *(void***)this;
    this = (Base*)((char*)this + ((ptrdiff_t*)vptr)[-3]);  // read vcall offset
    Derived::f(this);
}
```

The virtual thunk's mangled name (_ZTv0_n24_N7Derived1fEv) breaks down like this:

- `Tv` — virtual thunk
- `0` — no non-virtual `this` adjustment before reading the vcall offset
- `n24` — vcall offset is 24 bytes before the address point (`vptr[-3]`)
- `N7Derived1fEv` — target is `Derived::f()`

Each vtable section has one negative slot per virtual base: a vbase offset in the non-virtual-base sections, and a vcall offset in the virtual base's own section.

A class can be both a virtual base and have virtual bases of its own, in which case its section carries vbase offsets first (one per virtual base it inherits), then vcall offsets (one per virtual function that needs a thunk).

### Construction: Yet another table

C++ guarantees virtual dispatch works inside constructor bodies, so the vptr must be valid before the constructor body runs. But, we established prior that `Left` doesn't know where `Base` will land until the final complete type is laid out.

`Left`'s vtable records what it knew at compile time: in a standalone `Left`, `Base` is 8 bytes away. When embedded in `Derived`, `Base` ends up 16 bytes away. `Left`'s constructor can only install its own vtable, which still says `8`, so a virtual thunk firing during `Left`'s construction inside `Derived` will compute the wrong address for `Base`.

The fix is a **construction vtable**: a context-specific copy of `Left`'s vtable with offsets corrected for the actual complete object being built. It is installed into the vptr before `Left`'s constructor body runs, and overwritten with the real vtable once `Left`'s constructor returns. GCC emits one for every base class that has virtual bases — for this hierarchy, `_ZTC7Derived0_4Left` and `_ZTC7Derived8_5Right`.

The mangled name `_ZTC7Derived0_4Left` breaks down as:

- `TC` — construction vtable
- `7Derived` — complete class
- `0` — byte offset of `Left` within `Derived`
- `4Left` — base class

`_ZTC7Derived8_5Right` is the same thing: `Right` sits at offset `8` in `Derived`.

Now there needs to be a way to deliver the right construction vtable to each base constructor. That's the purpose of the **VTT** (Virtual Table Table): an array of vtable pointers for a specific construction context, one entry per subobject vptr that needs to be set.

Constructors for classes with virtual bases come in two variants, similar to destructors:
- **C1** (complete-object constructor): what you call to create a standalone object. Constructs virtual bases first, then calls each non-virtual base's constructor as **C2**, and finally installs the final vtable pointers for all subobjects.
- **C2** (base-object constructor): what C1 calls for each base subobject. Does not construct virtual bases — the outermost C1 owns them. If the class has virtual bases, receives a **sub-VTT** (a contiguous slice of the VTT with one entry per vptr in that subobject) and installs the construction vtable pointers from it for the duration of construction.

`Left` and `Right` both have `Base` as a virtual base, so their C2s receive a sub-VTT. `Base` has no virtual bases, therefore it has no C2/C1 split and no sub-VTT.

```
VTT for Derived
Derived::_ZTT7Derived: 7 entries
0     ((& Derived::_ZTV7Derived) + 24)           <- [0] Derived's own vtable (used if Derived is itself a subobject)

8     ((& Derived::_ZTC7Derived0_4Left) + 24)    <- [1] sub-VTT for Left::C2:  Left's vptr
16    ((& Derived::_ZTC7Derived0_4Left) + 56)    <- [2]                        Base's vptr

24    ((& Derived::_ZTC7Derived8_5Right) + 24)   <- [3] sub-VTT for Right::C2: Right's vptr
32    ((& Derived::_ZTC7Derived8_5Right) + 56)   <- [4]                        Base's vptr

40    ((& Derived::_ZTV7Derived) + 96)           <- [5] permanent vptr for Base
48    ((& Derived::_ZTV7Derived) + 64)           <- [6] permanent vptr for Right
```

The VTT has three logical regions:

- **`[0]`** — `Derived`'s own primary vtable pointer. Only used if `Derived` is itself a base of another class; unused here.
- **`[1]`-`[4]`** — sub-VTT slices, one per base class that needs one. Each is a contiguous block of vtable pointers passed to that base's C2. `Left`'s slice is `[1]`-`[2]` (its own vptr + `Base`'s vptr); `Right`'s is `[3]`-`[4]`.
- **`[5]`-`[6]`** — the permanent vptrs into `Derived`'s own vtable, written once all base constructors finish. `Base` and `Right` each get a slot. `Left` doesn't — it is `Derived`'s primary base, so their vptrs share the same memory location at offset 0, and installing `Derived`'s vtable there covers both at once.

In pseudocode, the flow is:

```cpp
// Left's C2 — installs whichever construction vtables the caller supplies
void Left_C2(Left* this, void** vtt) {
    this->vptr = vtt[0];                            // Left's construction vtable
    ptrdiff_t off = ((ptrdiff_t*)this->vptr)[-3];   // vbaseoffset
    ((Base*)((char*)this + off))->vptr = vtt[1];    // Base's construction vtable
    // ... constructor body ...
}

// Derived's C1 — drives the whole sequence
void Derived_C1(Derived* this) {
    base->vptr = &Base::vtable;                // seed Base with something valid
    Left_C2 ((Left*)this,        &VTT[1]);     // Left  uses VTT[1..2]
    Right_C2((Right*)(this + 8), &VTT[3]);     // Right uses VTT[3..4]
    // Install the final vtable pointers once all bases are constructed
    left->vptr  = &Derived::vtable[Left_section];
    right->vptr = &Derived::vtable[Right_section];
    base->vptr  = &Derived::vtable[Base_section];
    // ... constructor body ...
}
```

Now, lets look at the actual assembly for `Left::Left` C2:

```asm
Left::Left() [base object constructor]:  # _ZN4LeftC2Ev
        movq    (%rsi), %rax             # read Left's construction vtable ptr from VTT
        movq    %rax, (%rdi)             # install it into Left's vptr
        movq    -24(%rax), %rax          # read vbaseoffset: byte offset to Base's vptr within this object
        movq    8(%rsi), %rdx            # read Base's construction vtable ptr from VTT
        movq    %rdx, (%rdi,%rax)        # install it into Base's vptr
        # ... constructor body ...
        ret
```

And `Derived::Derived` C1, which drives the whole sequence:

```asm
Derived::Derived() [complete object constructor]:  # _ZN7DerivedC1Ev
        movq    %rdi, %rbx
        leaq    16+_ZTV4Base(%rip), %rax
        movq    %rax, 16(%rdi)                  # construct Base: install its vtable at offset 16
        leaq    8+_ZTT7Derived(%rip), %rbp      # %rbp = &VTT[1]
        movq    %rbp, %rsi
        call    _ZN4LeftC2Ev                    # Left::C2(this,      &VTT[1])
        leaq    16(%rbp), %rsi                  # %rsi = &VTT[3]
        leaq    8(%rbx), %rdi
        call    _ZN5RightC2Ev                   # Right::C2(this+8,   &VTT[3])
        leaq    24+_ZTV7Derived(%rip), %rax
        movq    %rax, (%rbx)                    # install final vtable into Left/Derived's vptr (offset 0)
        leaq    72(%rax), %rax
        movq    %rax, 16(%rbx)                  # install into Base's vptr (offset 16)
        leaq    -32(%rax), %rax
        movq    %rax, 8(%rbx)                   # install into Right's vptr (offset 8)
        # ... constructor body ...
        ret
```

Virtual bases are constructed before non-virtual bases, so `Base` goes first. `Base` has no virtual bases, so GCC inlines its vtable install directly rather than emitting a constructor call. Then `Left_C2` and `Right_C2` each run with their corresponding sub-VTT. Both install a construction vtable pointer into `Base`'s vptr, using the entry from their own sub-VTT. Both sub-VTTs point into construction vtables that have the vcall offsets corrected for `Base`'s actual position inside `Derived`. Once both C2s finish, C1 installs `Derived`'s final vtable into all three vptrs.

### Destruction and `D2`

Destruction has a similar problem: the shared `Base` subobject must only be destroyed once.

When you destroy a standalone `Left`, `Left::~Left` destroys `Base` too, because there is nothing else to do it. But when you destroy a `Derived`, `Derived::~Derived` takes responsibility for `Base`, and the `Left` and `Right` destructors must skip it.

That is the role of the aforementioned `D2` (the base-object destructor): destroy this subobject only, and leave virtual bases alone.

The call chain for `delete derived_ptr`:

- `D0` (deleting destructor): calls `D1`, then `operator delete`
- `D1` (complete-object destructor): destroys `Derived`'s own members, calls `Left::~Left` and `Right::~Right` as `D2`, then destroys `Base`
- `D2` (base-object destructor): destroys the subobject's own members and stops — virtual bases are left alone

The most-derived destructor owns virtual bases. Everything else uses `D2`.

## Conclusion

I spent a long digging through compiler output and the ABI spec to understand this properly, and this blog post is the result of that research. Hopefully writing it all down makes it easier for other people to understand this topic, too.

If this post helped you understand something that was previously unclear, I'd love to hear about it in the comments. Equally, if I got something wrong or oversimplified something in a misleading way, please leave a correction.

If my explanations didn't quite click, Nimrod has written two posts covering part of this topic that might work better for you:

- [What does C++ Object Layout Look Like?](https://nimrod.blog/posts/what-does-cpp-object-layout-look-like/)
- [C++ Virtual Table Tables (VTT)](https://nimrod.blog/posts/cpp-virtual-table-tables/)

For the low-level details in standardese, the official Itanium C++ ABI specification is available at https://itanium-cxx-abi.github.io/cxx-abi/abi.html.
