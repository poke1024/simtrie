# simtrie

`simtrie` is a library for fast, highly
configurable approximate string similarity
searches.

Here's a simple example:

```
import timeit

from nltk.corpus import wordnet as wn
lemmas = list(set(i for i in wn.words()))

print('creating set of %d words' % len(lemmas))
>> creating set of 147306 words
s = simtrie.Set(lemmas)

def search():
	return list(s.similar("bookish", 2))

print(timeit.timeit(stmt=search, number=1))
>> 0.00041486499958409695

print(search())
>> [('blockish', 2.0), ('bookie', 2.0), ('booking', 2.0), ('bookish', 0.0), ('boorish', 1.0), ('boxfish', 2.0), ('boyish', 2.0), ('foolish', 2.0), ('goodish', 2.0), ('monkish', 2.0), ('moorish', 2.0)]

```

`simtrie` allows you to fine-tune searches using custom
weighted metrics:

```
    metric = simtrie.Metric(
        (('c', None), 1.9),  # deletion cost
        (('ab', 'ba'), 1.5)  # transpose cost
    )
	s.similar("bookish", 2, metric, allow_transpose=True)
```

Some of simtrie's features:

* Stores string sets and dicts in ram using a prefix tree
* Fast, configurable similarity searches over large sets
* Pythonic API similar to regular `set` and `dict`
* Supports transpose, split and union weights

Note: binary data files are not portable between machine
architectures (they are either little or big endian).

# Credits

`simtrie` is a fork of pytrie/dawg. Its internal data structure
is a very clever C++ implementation of a DAFSA by Susumu Yata.

Various test cases and ideas were taken from the super clean
implementation at https://github.com/infoscout/weighted-levenshtein/.

# Similar Projects

* https://github.com/wolfgarbe/SymSpell

# License

Python code is licensed under the MIT License.

Bundled `dawgdic`_ C++ library and C++ extensions
for simtrie are licensed under the BSD license.
