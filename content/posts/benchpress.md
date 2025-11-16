---
title: "benchpress: A Self-Building Benchmark Harness Generator"
date: 2025-11-16
draft: false
tags: ["compilers", "benchmarking", "tooling", "C", "Python"]
categories: ["Programming"]
---

Recently, I was bored and decided to test the performance of a 4x4 matrix multiply. I wanted to compare how GCC and Clang optimize the same code with different flags. So I manually wrote a benchmark harness using a neat trick: a C file that's also a valid shell script.

The idea is simple. You embed shell commands in C comments at the top of the file. When you run `sh benchmark.c`, the shell sees the commands and executes them to compile and run the benchmark. When the C compiler processes it, the commands are just comments.

```c
#if 0
gcc -O3 -c benchmark.c -o bench_gcc.o ...
clang -O3 -c benchmark.c -o bench_clang.o ...
gcc benchmark.c bench_gcc.o bench_clang.o -o benchmark
./benchmark
exit
#endif

#include <stdio.h>
// ... rest of the C code
```

I first remember seeing this trick in [libmemory](https://github.com/skeeto/w64devkit/blob/master/src/libmemory.c) by skeeto, though he probably wasn't the first to do it. It's a neat way to make self-contained, self-building C files. You can simply run them with `sh benchmark.c`.

After I manually wrote a testcase with a harness using this trick, I immediately started wondering if it could be automated. And that is how I came up with benchpress.

## How It Works

benchpress is a tool that generates these self-building benchmark harnesses automatically. You write a template C file with three types of annotations:

1. **`BENCHFUNC`** - The function(s) you want to compile with different configurations
2. **`WARMUP`** - Code to warm up caches before each benchmark run
3. **`BENCHMARK`** - The actual benchmark iterations

You can have multiple `BENCHMARK` functions to test different scenarios. The warmup function pairs with a benchmark by naming convention: append `_warmup` to the benchmark name. So `run_benchmark_warmup` pairs with `run_benchmark`. Each benchmark must have a corresponding warmup function.

Here's the example that started it all:

```c
// matmul_template.c
#include <stdint.h>

typedef struct { float data[16]; } Matrix4x4;

void init_matrix(Matrix4x4 *m) {
    for (int i = 0; i < 16; i++) {
        m->data[i] = (float)(i + 1);
    }
}

BENCHFUNC void matmul(Matrix4x4 *a, Matrix4x4 *b, Matrix4x4 *result) {
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            float sum = 0.0f;
            for (int k = 0; k < 4; k++) {
                sum += a->data[i*4+k] * b->data[k*4+j];
            }
            result->data[i*4+j] = sum;
        }
    }
}

WARMUP void run_benchmark_warmup(void) {
    Matrix4x4 a, b, result;
    init_matrix(&a);
    init_matrix(&b);
    for (int64_t i = 0; i < 1000000; i++) {
        matmul(&a, &b, &result);
    }
}

BENCHMARK void run_benchmark(void) {
    Matrix4x4 a, b, result;
    init_matrix(&a);
    init_matrix(&b);
    for (int64_t i = 0; i < 1000000000; i++) {
        matmul(&a, &b, &result);
    }
}
```

Then, run benchpress to generate a benchmark harness:

```bash
python3 benchpress.py matmul_template.c \
  --compilers gcc:clang \
  --flags="-O2:-O3" \
  -o benchmark.c
```

Run it:

```bash
sh benchmark.c
```

Output:
```
GCC version: gcc (GCC) 15.2.0
Clang version: clang version 20.1.6

gcc -O2: 6.374 seconds
gcc -O3: 3.681 seconds
clang -O2: 6.163 seconds
clang -O3: 3.801 seconds
gcc -O2 vs clang -O2: clang -O2 was 1.03x faster
clang -O3 vs gcc -O3: gcc -O3 was 1.03x faster
```

The generated `benchmark.c` file is completely self-contained. It uses the same polyglot trick described earlier. You can share it as a single file, and anyone with gcc and clang installed can run it with `sh benchmark.c`.

## Key Features

### Automatic Combinations

benchpress can generate all combinations of compilers and flags:

```bash
benchpress.py template.c \
  --compilers gcc:clang \
  --flags="-O2:-O3:-O3 -march=native" \
  -o benchmark.c
```

This creates 6 configurations (2 compilers × 3 flag sets) and automatically compares results.

### Custom Configurations

For more control, specify individual configurations with `--config`:

```bash
benchpress.py template.c \
  --config gcc:-O2 \
  --config gcc:-O3 \
  --compare "gcc -O2,gcc -O3" \
  -o benchmark.c
```

This generates a benchmark that compares `gcc -O3` to `gcc -O2`.

## Use Cases

Here is a short list of usecases for benchpress:
- **Quick experiments**: Does that optimization flag actually make a difference? Generate a benchmark and find out in seconds
- **Compiler comparisons**: Which produces faster code for this algorithm - GCC or Clang? Test it directly
- **Bug reports**: Attach a single self-contained file demonstrating a performance regression
- **Architecture flags**: Measure the actual impact of `-march=native` or other hardware-specific optimizations
- **Sharing benchmarks**: Send someone a file they can run with `sh benchmark.c` - no build instructions needed

## Try It Out

The tool is open source and available on [GitHub](https://github.com/Peter0x44/benchpress). Feel free to open issues, send me an email, or leave comments on this blog post. Suggestions, contributions and feedback are welcome!

