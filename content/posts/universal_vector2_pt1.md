---
title: "Making a Universal Vector2 Type in C++ - Part 1: Library User Perspective"
date: 2025-08-06T12:00:00Z
draft: false
tags: ["programming", "c++"]
categories: ["tutorials"]
comments: true
---

## The Interoperability Problem

When using multiple libraries in your project, a quite frequent source of annoyance is trying to share their fundamental types, such as a two dimensional vector, quaternion, euler angle, etc. In each library, you can find various names for exactly the same concept.

Consider a hypothetical game development scenario: you could be using Box2D for physics (which has `b2Vec2`), raylib for graphics (which has `Vector2`). Despite that two types represent exactly the same thing, they cannot be used interchangeably. This forces you to copy one object into another, every time you wish to pass data and convert between them. Since these conversions are needed quite frequently, constantly operating on copies can become a source of bugs, along with being generally unergonomic. What if we could make our own type to rule them all? 

## The C Approach: Preprocessor

Some more mindful libraries offer macro flags to prevent emitting declarations for structs, which could look something like:

```c
#ifndef SOMELIB_VEC2_TYPE
#define SOMELIB_VEC2_TYPE

    typedef struct { float x; float y; } slVec2;

#endif
```

You can now define SOMELIB_VEC2_TYPE and use your own preferred Vector2 type with a typedef instead:
```c
typedef struct { float x,y; } MyVec2;
#define SOMELIB_VEC2_TYPE
typedef slVec2 MyVec2;
#include "somelib.h"
```

I believe this approach represents the most ergonomic solution currently available in C, though it comes with a significant limitation: it depends entirely on library authors having the foresight to include this option in their APIs. While I would strongly encourage more library authors to adopt this pattern, the reality is that very few do.

## The C++ Approach: Conversion Operators

C++ offers a better solution through conversion operators. You can create a Vector2 type that can automatically convert to other Vector2 types:

```cpp
struct MyVec2 {
    float x, y;
    MyVec2(float x, float y) : x(x), y(y) {}
    
    // Conversion operators for different libraries
    operator b2Vec2() const {
        return b2Vec2{x, y};
    }
    operator Vector2() const {
        return Vector2{x, y};
    }
};
```

Now MyVec2 can be passed to any function expecting a b2Vec2 or Vector2.

```cpp
MyVec2 position(10.0f, 20.0f);
b2Body_SetTransform(body, position, angle);
DrawTexture(texture, position, WHITE);
```

But this won't cover the case of assigning MyVec2 to a function returning a Vector2.
For that you need to add converting constructors:

```cpp
struct MyVec2 {
    float x, y;
    
    MyVec2(float x, float y) : x(x), y(y) {}
    
    // Converting constructors from other vector types
    MyVec2(const b2Vec2& v) : x(v.x), y(v.y) {}
    MyVec2(const Vector2& v) : x(v.x), y(v.y) {}
    
    // Conversion operators
    operator b2Vec2() const { return b2Vec2{x, y}; }
    operator Vector2() const { return Vector2{x, y}; }
};
```

Now you can directly assign a MyVec2 from a function returning b2Vec2 or Vector2:     
```cpp
MyVec2 physicsPos = b2Body_GetPosition(bodyId);
MyVec2 mousePos = GetMousePosition();
```

For most practical purposes, this approach solves the interoperability problem completely. If you're working on an application that uses multiple libraries, you can implement the conversion operators and converting constructors right away and eliminate a lot of conversions in your codebase.

However, library authors face a different challenge: The type cannot know the details of the other dependencies that might be used alongside it, so it's not possible to provide the relevant conversion operators and converting constructors. This requires a more sophisticated approach using templates, which is covered in [part 2](/posts/universal_vector2_pt2/).