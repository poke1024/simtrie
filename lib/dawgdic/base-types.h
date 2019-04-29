#ifndef DAWGDIC_BASE_TYPES_H
#define DAWGDIC_BASE_TYPES_H

#include <cstddef>

namespace dawgdic {

// 8-bit characters.
typedef char CharType;
typedef unsigned char UCharType;

// 32-bit integer.
typedef int32_t ValueType;

// 32-bit unsigned integer.
typedef uint32_t BaseType;

// 32 or 64-bit unsigned integer.
typedef std::size_t SizeType;

// Function for reading and writing data.
typedef int (*IOFunction)(void *stream, void *buf, size_t size);

}  // namespace dawgdic

#endif  // DAWGDIC_BASE_TYPES_H
