---
title: "Making a Universal Vector2 Type in C++ - Part 2: Library Author Perspective"
date: 2025-08-28T12:30:00Z
draft: false
tags: ["programming", "c++", "templates"]
categories: ["tutorials"]
comments: true
---

In [part 1](/posts/universal_vector2_pt1/), we looked at how application developers can create a universal Vector2 type that converts to and from different library types. This approach works great when you control the application code, but what if you're a library author? How can you design your Vector2 type to be automatically compatible with other libraries without knowing which ones your users might combine with yours?

## The Library Author's Challenge

As a library author, you can't hard-code conversion operators for every possible Vector2 type that exists. You don't know which other libraries your users will combine with yours, and adding dependencies just for type compatibility would be unreasonable. What you need is a way to make your Vector2 type *generically* compatible with any other Vector2-like type that has the same structure.

Consider these different Vector2 types that might exist in a user's codebase:

```cpp
typedef struct { float x; float y;} b2Vec2;    // Box2D physics
typedef struct { float x; float y;} Vector2;   // raylib graphics  
struct Point2D { float x, y; };                // Custom math library
struct Vec2f { float x, y; };                  // Another graphics lib
```

Your library's Vector2 needs to work seamlessly with all of these, without knowing about them in advance.

## The Basic Template Approach

The simplest solution is to use a template conversion operator that works with any type:

```cpp
struct MyVec2 {
    float x, y;
    
    MyVec2(float x = 0.0f, float y = 0.0f) : x(x), y(y) {}
    
    // This will try to convert to ANY type
    template<typename T>
    operator T() const {
        return T{x, y};
    }
};
```

This works, but it's problematic - it will attempt to convert your Vector2 to *any* type that can be initialized using list initialization with two values. This leads to confusing behavior: your Vector2 might successfully convert to a `std::string` (treating the floats as chars) or `std::vector<int>` (truncating the floats to integers), which is almost certainly not what you intended. We need to constrain this template to only work with Vector2-like types.

## Adding Type Constraints

We need to constrain our template to only work with Vector2-like types to avoid strange and confusing implicit conversions to undesired types like `std::string` or `std::vector<int>`.

In this blog post, I will be demonstrating a type with these constraints for conversion:
1. Have `x` and `y` members that can be converted to `float`
2. Can be constructed from two `float`s
3. Support outgoing conversions to any type that has `x` and `y` members and can be constructed from two `float`s, including higher precision types like `double`
4. Prevent implicit incoming conversions from types with different member types (like `double`)

These are just examples, and you should adjust them to match your specific requirements. For instance, you might allow only exact type matches, permit bidirectional conversions with any precision, or restrict conversions to only one direction.

The implementation of these constraints varies dramatically depending on which C++ standard you're targeting. Let's see how this evolves from the modern versions down to the more complex legacy versions.

## C++20 Implementation with Concepts

C++20 concepts give us the most concise and readable solution:

```cpp
#include <concepts>

template<typename T>
concept HasXYMembers = requires(T t) {
    { t.x } -> std::convertible_to<float>;
    { t.y } -> std::convertible_to<float>;
};

// C++20 concept to check if a type has x,y members that are exactly float
template<typename T>
concept HasFloatXYMembers = requires(T t) {
    requires std::same_as<decltype(t.x), float>;
    requires std::same_as<decltype(t.y), float>;
};

template<typename T>
concept ConstructibleFromXY = requires(float x, float y) {
    T{x, y};  // Check if T can be constructed using aggregate initialization
};

// Concept for outgoing conversions (allows any convertible type)
template<typename T>
concept CompatibleVec2Out = HasXYMembers<T> && 
                           ConstructibleFromXY<T>;

// Concept for incoming conversions (only allows floats)
template<typename T>
concept CompatibleVec2In = HasFloatXYMembers<T> && 
                          ConstructibleFromXY<T>;

struct MyVec2 {
    float x, y;
    
    MyVec2(float x = 0.0f, float y = 0.0f) : x(x), y(y) {}
    
    // Converting constructor - only allows floats
    template<CompatibleVec2In T>
    MyVec2(const T& other) : x(other.x), y(other.y) {}
    
    // Conversion operator - allows any convertible type
    template<CompatibleVec2Out T>
    operator T() const {
        return T{x, y};
    }
};
```

The concepts approach is very clear and self-documenting. You can immediately see that `CompatibleVec2In` is stricter (float members only) while `CompatibleVec2Out` is more permissive (any convertible type). This means `MyVec2` can output to a `DoubleVec2`, but won't accept one as input.

## C++17 Implementation with SFINAE

C++17 lacks concepts, so we fall back to SFINAE (Substitution Failure Is Not An Error) with type traits. This gets significantly more verbose:

```cpp
#include <type_traits>

template<typename T, typename = void>
struct has_xy_members : std::false_type {};

template<typename T>
struct has_xy_members<T, std::void_t<
    decltype(std::declval<T>().x),
    decltype(std::declval<T>().y)
>> : std::conjunction<
    std::is_convertible<decltype(std::declval<T>().x), float>,
    std::is_convertible<decltype(std::declval<T>().y), float>
> {};

// Type trait to detect if a type has x and y members that are exactly float
template<typename T, typename = void>
struct has_float_xy_members : std::false_type {};

template<typename T>
struct has_float_xy_members<T, std::void_t<
    decltype(std::declval<T>().x),
    decltype(std::declval<T>().y)
>> : std::conjunction<
    std::is_same<decltype(std::declval<T>().x), float>,
    std::is_same<decltype(std::declval<T>().y), float>
> {};

template<typename T, typename = void>
struct is_constructible_from_xy : std::false_type {};

template<typename T>
struct is_constructible_from_xy<T, std::void_t<
    decltype(T{std::declval<float>(), std::declval<float>()})
>> : std::true_type {};

// Type trait for outgoing conversions (allows any convertible type)
template<typename T>
struct is_compatible_vec2_out : std::conjunction<
    has_xy_members<T>,
    is_constructible_from_xy<T>
> {};

// Type trait for incoming conversions (only allows floats)
template<typename T>
struct is_compatible_vec2_in : std::conjunction<
    has_float_xy_members<T>,
    is_constructible_from_xy<T>
> {};

template<typename T>
constexpr bool is_compatible_vec2_out_v = is_compatible_vec2_out<T>::value;

template<typename T>
constexpr bool is_compatible_vec2_in_v = is_compatible_vec2_in<T>::value;

struct MyVec2 {
    float x, y;
    
    MyVec2(float x = 0.0f, float y = 0.0f) : x(x), y(y) {}
    
    // Converting constructor - only allows floats
    template<typename T, std::enable_if_t<is_compatible_vec2_in_v<T>, int> = 0>
    MyVec2(const T& other) : x(other.x), y(other.y) {}
    
    // Conversion operator - allows any convertible type
    template<typename T>
    operator T() const {
        static_assert(is_compatible_vec2_out_v<T>, 
            "Target type must have x,y members and be constructible from (float, float)");
        return T{x, y};
    }
};
```

The complexity has increased dramatically! We need custom type traits using `std::void_t` for SFINAE, and the intent is much less clear than the concepts version.

## C++11 Implementation

C++11 lacks many modern conveniences, making this significantly more complex:

```cpp
#include <type_traits>

// C++11 doesn't have std::void_t, so we roll our own
template<typename...>
using void_t = void;

// C++11 doesn't have std::conjunction either
template<typename...>
struct conjunction : std::true_type {};

template<typename T>
struct conjunction<T> : T {};

template<typename T, typename... Ts>
struct conjunction<T, Ts...> : std::conditional<bool(T::value), conjunction<Ts...>, T>::type {};

template<typename T, typename = void>
struct has_xy_members : std::false_type {};

template<typename T>
struct has_xy_members<T, void_t<
    decltype(std::declval<T>().x),
    decltype(std::declval<T>().y)
>> : conjunction<
    std::is_convertible<decltype(std::declval<T>().x), float>,
    std::is_convertible<decltype(std::declval<T>().y), float>
> {};

template<typename T, typename = void>
struct is_constructible_from_xy : std::false_type {};

template<typename T>
struct is_constructible_from_xy<T, void_t<
    decltype(T{std::declval<float>(), std::declval<float>()})
>> : std::true_type {};

// Type trait to detect if a type has x and y members that are exactly float
template<typename T, typename = void>
struct has_float_xy_members : std::false_type {};

template<typename T>
struct has_float_xy_members<T, void_t<
    decltype(std::declval<T>().x),
    decltype(std::declval<T>().y)
>> : conjunction<
    std::is_same<decltype(std::declval<T>().x), float>,
    std::is_same<decltype(std::declval<T>().y), float>
> {};

// Type trait for outgoing conversions (allows any convertible type)
template<typename T>
struct is_compatible_vec2_out : conjunction<
    has_xy_members<T>,
    is_constructible_from_xy<T>
> {};

// Trait for incoming conversions (only allows floats)
template<typename T>
struct is_compatible_vec2_in : conjunction<
    has_float_xy_members<T>,
    is_constructible_from_xy<T>
> {};

// C++11 doesn't have variable templates, so we use function templates
template<typename T>
constexpr bool is_compatible_vec2_out_v() { return is_compatible_vec2_out<T>::value; }

template<typename T>
constexpr bool is_compatible_vec2_in_v() { return is_compatible_vec2_in<T>::value; }

struct MyVec2 {
    float x, y;
    
    MyVec2(float x = 0.0f, float y = 0.0f) : x(x), y(y) {}
    
    // Converting constructor - only allows floats
    template<typename T>
    MyVec2(const T& other, typename std::enable_if<is_compatible_vec2_in_v<T>(), int>::type = 0) 
        : x(other.x), y(other.y) {}
    
    // Conversion operator - allows any convertible type
    template<typename T>
    operator T() const {
        static_assert(is_compatible_vec2_out_v<T>(), 
            "Target type must have x,y members and be constructible from (float, float)");
        return T{x, y};
    }
};
```

This C++11 version is quite inconvenient! We had to implement our own versions of `void_t` and `conjunction` since they don't exist yet. We also can't use variable templates, so function templates have to be used instead.

## The Evolution of C++

Looking at these three implementations provides an excellent demonstration of how C++ has evolved over time. The same functionality requires:

- **C++20**: ~25 lines of clear, readable code with concepts
- **C++17**: ~50 lines with complex SFINAE
- **C++11**: ~70+ lines with manual implementation of missing standard library features

Each newer standard makes the code much more concise and readable.

## Conclusion

Now you know how to create a generic Vector2 type that users can use with their own types and other libraries seamlessly. You can find a complete implementation with all three C++ standard versions at [this gist](https://gist.github.com/Peter0x44/cb65b9b500db4f351d7e70513f12dcb1).